from __future__ import annotations

import logging
import os
import random
import re
import time
from typing import Any

from google import genai

log = logging.getLogger(__name__)

_RETRY_AFTER_HEADER_RE = re.compile(r"retry[-_]?after[:\s]+(\d+(?:\.\d+)?)", re.I)


def _truthy(name: str) -> bool:
    return os.getenv(name, "0").strip().lower() in ("1", "true", "yes", "on")


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


def build_genai_client() -> genai.Client:
    if _truthy("GOOGLE_GENAI_USE_VERTEXAI"):
        project = (os.getenv("GOOGLE_CLOUD_PROJECT") or "").strip()
        if not project:
            raise RuntimeError("GOOGLE_CLOUD_PROJECT is required when GOOGLE_GENAI_USE_VERTEXAI is set")
        location = (os.getenv("GOOGLE_CLOUD_LOCATION") or "us-central1").strip()
        return genai.Client(vertexai=True, project=project, location=location)
    key = (os.getenv("GOOGLE_API_KEY") or "").strip()
    if not key:
        raise RuntimeError("GOOGLE_API_KEY is required when GOOGLE_GENAI_USE_VERTEXAI is unset or false")
    return genai.Client(api_key=key)


def _normalize_model_id(model: str) -> str:
    m = model.strip()
    if not m:
        return "gemini-embedding-001"
    if m.startswith("models/"):
        return m
    return m


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
    if codes & {408, 429, 500, 502, 503, 504}:
        return True
    msg = str(exc).upper()
    for token in (
        "429",
        "503",
        "RESOURCE_EXHAUSTED",
        "UNAVAILABLE",
        "DEADLINE",
        "RATE",
        "QUOTA",
        "THROTTLE",
        "TRY AGAIN",
        "TIMEOUT",
        "ECONNRESET",
        "TEMPORARILY",
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


def _embed_single_with_retry(
    client: genai.Client,
    model: str,
    text: str,
    *,
    max_retries: int,
    base_delay: float,
    max_delay: float,
) -> list[float]:
    last_err: BaseException | None = None
    for attempt in range(max_retries):
        try:
            resp = client.models.embed_content(model=model, contents=text)
            vectors = _vectors_from_response(resp)
            if len(vectors) != 1:
                raise RuntimeError(f"expected 1 embedding per text, got {len(vectors)}")
            return vectors[0]
        except BaseException as exc:
            last_err = exc
            if attempt + 1 >= max_retries or not _is_transient_error(exc):
                raise
            backoff = min(base_delay * (2**attempt) + random.uniform(0, base_delay), max_delay)
            ra = _retry_after_seconds(exc)
            if ra is not None:
                backoff = max(backoff, ra)
            log.warning(
                "embedding transient error (attempt %s/%s), sleeping %.2fs: %s",
                attempt + 1,
                max_retries,
                backoff,
                exc,
            )
            time.sleep(backoff)
    assert last_err is not None
    raise last_err


def embed_batch(client: genai.Client, model: str, texts: list[str]) -> list[list[float]]:
    """Return embedding vectors in the same order as ``texts``.

    Retries transient API errors with exponential backoff. Optional
    ``RAG_EMBED_MIN_INTERVAL_SEC`` spaces calls to reduce burst rate.
    """
    if not texts:
        return []
    mid = _normalize_model_id(model)
    max_retries = max(1, _env_int("RAG_EMBED_MAX_RETRIES", 8))
    base_delay = max(0.01, _env_float("RAG_EMBED_BASE_DELAY_SEC", 1.0))
    max_delay = max(base_delay, _env_float("RAG_EMBED_MAX_DELAY_SEC", 120.0))
    min_interval = max(0.0, _env_float("RAG_EMBED_MIN_INTERVAL_SEC", 0.0))
    out: list[list[float]] = []
    for i, text in enumerate(texts):
        if i > 0 and min_interval > 0:
            time.sleep(min_interval)
        out.append(_embed_single_with_retry(client, mid, text, max_retries=max_retries, base_delay=base_delay, max_delay=max_delay))
    return out


def _vectors_from_response(resp: Any) -> list[list[float]]:
    embeddings = getattr(resp, "embeddings", None)
    if embeddings is None:
        return []
    vectors: list[list[float]] = []
    for emb in embeddings:
        values = getattr(emb, "values", None)
        if values is not None:
            vectors.append(list(values))
    return vectors
