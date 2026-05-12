"""Embeddings for ``RAG_EMBEDDING_PROVIDER=anthropic``.

Anthropic does not serve text-embedding vectors from ``api.anthropic.com``; the
Claude documentation points to `Voyage AI`_ embedding models for RAG. This
module calls Voyage's OpenAI-compatible ``/v1/embeddings`` HTTP API using
``VOYAGE_API_KEY`` (``Authorization: Bearer``).

.. _Voyage AI: https://docs.voyageai.com/reference/embeddings-api
"""

from __future__ import annotations

import logging
import os
import random
import re
import time
from typing import Any

import httpx

log = logging.getLogger(__name__)

_RETRY_AFTER_HEADER_RE = re.compile(r"retry[-_]?after[:\s]+(\d+(?:\.\d+)?)", re.I)


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)).strip())
    except ValueError:
        return default


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)).strip())
    except ValueError:
        return default


def _output_dimension() -> int | None:
    raw = (os.getenv("RAG_ANTHROPIC_EMBEDDING_DIMENSIONS") or "").strip()
    if not raw:
        return None
    try:
        value = int(raw)
    except ValueError as exc:
        raise RuntimeError("RAG_ANTHROPIC_EMBEDDING_DIMENSIONS must be an integer") from exc
    if value <= 0:
        raise RuntimeError("RAG_ANTHROPIC_EMBEDDING_DIMENSIONS must be greater than zero")
    return value


def build_anthropic_client() -> httpx.Client:
    key = (os.getenv("VOYAGE_API_KEY") or "").strip()
    if not key:
        raise RuntimeError(
            "VOYAGE_API_KEY is required when RAG_EMBEDDING_PROVIDER=anthropic "
            "(Voyage hosts the embedding models used in the Claude ecosystem; "
            "see https://docs.voyageai.com/reference/embeddings-api)"
        )
    base = (os.getenv("RAG_VOYAGE_BASE_URL") or "https://api.voyageai.com/v1").strip().rstrip("/")
    timeout = _env_float("RAG_ANTHROPIC_TIMEOUT_SEC", 120.0)
    if timeout <= 0:
        timeout = 120.0
    limits = httpx.Limits(max_keepalive_connections=5, max_connections=10)
    return httpx.Client(
        base_url=base,
        headers={"Authorization": f"Bearer {key}"},
        timeout=httpx.Timeout(timeout),
        limits=limits,
    )


def _collect_status_codes(exc: BaseException) -> set[int]:
    codes: set[int] = set()
    seen: set[int] = set()
    stack: list[BaseException] = [exc]
    while stack:
        e = stack.pop()
        eid = id(e)
        if eid in seen:
            continue
        seen.add(eid)
        for attr in ("status_code", "http_status", "code"):
            raw = getattr(e, attr, None)
            if isinstance(raw, int):
                codes.add(raw)
            elif isinstance(raw, str) and raw.isdigit():
                codes.add(int(raw))
        resp = getattr(e, "response", None)
        if resp is not None:
            sc = getattr(resp, "status_code", None)
            if isinstance(sc, int):
                codes.add(sc)
        nxt = getattr(e, "__cause__", None) or getattr(e, "__context__", None)
        if isinstance(nxt, BaseException):
            stack.append(nxt)
    return codes


def _is_transient_error(exc: BaseException) -> bool:
    codes = _collect_status_codes(exc)
    if codes & {408, 409, 429, 500, 502, 503, 504}:
        return True
    msg = str(exc).upper()
    for token in (
        "429",
        "500",
        "503",
        "RATE",
        "QUOTA",
        "THROTTLE",
        "TIMEOUT",
        "TRY AGAIN",
        "TEMPORARILY",
        "ECONNRESET",
        "CONNECTION",
    ):
        if token in msg:
            return True
    return False


def _retry_after_seconds(exc: BaseException) -> float | None:
    resp = getattr(exc, "response", None)
    if resp is not None:
        headers = getattr(resp, "headers", None)
        if headers is not None:
            raw = headers.get("retry-after") or headers.get("Retry-After")
            if raw is not None:
                try:
                    return float(str(raw).strip())
                except ValueError:
                    pass
    m = _RETRY_AFTER_HEADER_RE.search(str(exc))
    if m:
        try:
            return float(m.group(1))
        except ValueError:
            return None
    return None


def _vectors_from_payload(payload: dict[str, Any]) -> list[list[float]]:
    data = payload.get("data")
    if not isinstance(data, list):
        return []
    rows: list[tuple[int, list[float]]] = []
    for fallback_index, item in enumerate(data):
        if not isinstance(item, dict):
            continue
        raw_index = item.get("index", fallback_index)
        embedding = item.get("embedding")
        if embedding is None:
            continue
        try:
            index = int(raw_index)
        except (TypeError, ValueError):
            index = fallback_index
        rows.append((index, [float(x) for x in embedding]))
    return [vector for _, vector in sorted(rows, key=lambda row: row[0])]


def _embed_slice(
    client: httpx.Client,
    model: str,
    texts: list[str],
    *,
    input_type: str | None,
) -> list[list[float]]:
    body: dict[str, Any] = {"model": model, "input": texts}
    if input_type in ("query", "document"):
        body["input_type"] = input_type
    if (dim := _output_dimension()) is not None:
        body["output_dimension"] = dim
    resp = client.post("/embeddings", json=body)
    resp.raise_for_status()
    payload = resp.json()
    if not isinstance(payload, dict):
        raise RuntimeError("voyage embeddings response must be a JSON object")
    return _vectors_from_payload(payload)


def _embed_slice_with_retry(
    client: httpx.Client,
    model: str,
    texts: list[str],
    *,
    input_type: str | None,
    max_retries: int,
    base_delay: float,
    max_delay: float,
) -> list[list[float]]:
    last_err: BaseException | None = None
    for attempt in range(max_retries):
        try:
            vectors = _embed_slice(client, model, texts, input_type=input_type)
            if len(vectors) != len(texts):
                raise RuntimeError(f"expected {len(texts)} embeddings, got {len(vectors)}")
            return vectors
        except BaseException as exc:
            last_err = exc
            if attempt + 1 >= max_retries or not _is_transient_error(exc):
                raise
            backoff = min(base_delay * (2**attempt) + random.uniform(0, base_delay), max_delay)
            ra = _retry_after_seconds(exc)
            if ra is not None:
                backoff = max(backoff, ra)
            log.warning(
                "anthropic/voyage embedding transient error (attempt %s/%s), sleeping %.2fs: %s",
                attempt + 1,
                max_retries,
                backoff,
                exc,
            )
            time.sleep(backoff)
    assert last_err is not None
    raise last_err


def embed_batch(
    client: httpx.Client,
    model: str,
    texts: list[str],
    *,
    input_type: str | None = None,
) -> list[list[float]]:
    """Return Voyage embedding vectors in the same order as ``texts``.

    ``input_type`` should be ``\"document\"`` for corpus indexing and
    ``\"query\"`` for search queries when using retrieval-tuned Voyage models.
    """
    if not texts:
        return []
    mid = (model or "").strip() or "voyage-3.5"
    max_retries = max(1, _env_int("RAG_EMBED_MAX_RETRIES", 8))
    base_delay = max(0.01, _env_float("RAG_EMBED_BASE_DELAY_SEC", 1.0))
    max_delay = max(base_delay, _env_float("RAG_EMBED_MAX_DELAY_SEC", 120.0))
    min_interval = max(0.0, _env_float("RAG_EMBED_MIN_INTERVAL_SEC", 0.0))
    batch_size = max(1, _env_int("RAG_ANTHROPIC_EMBED_BATCH_SIZE", 128))
    out: list[list[float]] = []
    for offset in range(0, len(texts), batch_size):
        if offset > 0 and min_interval > 0:
            time.sleep(min_interval)
        chunk = texts[offset : offset + batch_size]
        out.extend(
            _embed_slice_with_retry(
                client,
                mid,
                chunk,
                input_type=input_type,
                max_retries=max_retries,
                base_delay=base_delay,
                max_delay=max_delay,
            )
        )
    return out
