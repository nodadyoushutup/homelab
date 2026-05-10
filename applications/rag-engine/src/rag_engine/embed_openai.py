from __future__ import annotations

import logging
import os
import random
import re
import time
from typing import Any

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


def build_openai_client() -> Any:
    from openai import OpenAI

    key = (os.getenv("OPENAI_API_KEY") or "").strip()
    if not key:
        raise RuntimeError("OPENAI_API_KEY is required when RAG_EMBEDDING_PROVIDER=openai")
    kwargs: dict[str, Any] = {"api_key": key}
    if base_url := (os.getenv("OPENAI_BASE_URL") or "").strip():
        kwargs["base_url"] = base_url
    if organization := (
        os.getenv("OPENAI_ORG_ID") or os.getenv("OPENAI_ORGANIZATION") or ""
    ).strip():
        kwargs["organization"] = organization
    if project := (os.getenv("OPENAI_PROJECT") or "").strip():
        kwargs["project"] = project
    if timeout := _env_float("RAG_OPENAI_TIMEOUT_SEC", 0.0):
        kwargs["timeout"] = timeout
    return OpenAI(**kwargs)


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


def _embedding_dimensions(model: str) -> int | None:
    raw = (os.getenv("RAG_OPENAI_EMBEDDING_DIMENSIONS") or "").strip()
    if not raw:
        return None
    if not model.startswith("text-embedding-3"):
        log.warning("ignoring RAG_OPENAI_EMBEDDING_DIMENSIONS for model=%s", model)
        return None
    try:
        value = int(raw)
    except ValueError as exc:
        raise RuntimeError("RAG_OPENAI_EMBEDDING_DIMENSIONS must be an integer") from exc
    if value <= 0:
        raise RuntimeError("RAG_OPENAI_EMBEDDING_DIMENSIONS must be greater than zero")
    return value


def _embed_slice(client: Any, model: str, texts: list[str]) -> list[list[float]]:
    kwargs: dict[str, Any] = {
        "model": model,
        "input": texts,
        "encoding_format": "float",
    }
    if dimensions := _embedding_dimensions(model):
        kwargs["dimensions"] = dimensions
    resp = client.embeddings.create(**kwargs)
    return _vectors_from_response(resp)


def _embed_slice_with_retry(
    client: Any,
    model: str,
    texts: list[str],
    *,
    max_retries: int,
    base_delay: float,
    max_delay: float,
) -> list[list[float]]:
    last_err: BaseException | None = None
    for attempt in range(max_retries):
        try:
            vectors = _embed_slice(client, model, texts)
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
                "openai embedding transient error (attempt %s/%s), sleeping %.2fs: %s",
                attempt + 1,
                max_retries,
                backoff,
                exc,
            )
            time.sleep(backoff)
    assert last_err is not None
    raise last_err


def embed_batch(client: Any, model: str, texts: list[str]) -> list[list[float]]:
    """Return OpenAI embedding vectors in the same order as ``texts``."""
    if not texts:
        return []
    mid = (model or "").strip() or "text-embedding-3-small"
    max_retries = max(1, _env_int("RAG_EMBED_MAX_RETRIES", 8))
    base_delay = max(0.01, _env_float("RAG_EMBED_BASE_DELAY_SEC", 1.0))
    max_delay = max(base_delay, _env_float("RAG_EMBED_MAX_DELAY_SEC", 120.0))
    min_interval = max(0.0, _env_float("RAG_EMBED_MIN_INTERVAL_SEC", 0.0))
    batch_size = max(1, _env_int("RAG_OPENAI_EMBED_BATCH_SIZE", 128))
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
                max_retries=max_retries,
                base_delay=base_delay,
                max_delay=max_delay,
            )
        )
    return out


def _vectors_from_response(resp: Any) -> list[list[float]]:
    data = getattr(resp, "data", None)
    if data is None and isinstance(resp, dict):
        data = resp.get("data")
    if data is None:
        return []
    rows: list[tuple[int, list[float]]] = []
    for fallback_index, item in enumerate(data):
        if isinstance(item, dict):
            raw_index = item.get("index", fallback_index)
            embedding = item.get("embedding")
        else:
            raw_index = getattr(item, "index", fallback_index)
            embedding = getattr(item, "embedding", None)
        if embedding is None:
            continue
        try:
            index = int(raw_index)
        except (TypeError, ValueError):
            index = fallback_index
        rows.append((index, list(embedding)))
    return [vector for _, vector in sorted(rows, key=lambda row: row[0])]
