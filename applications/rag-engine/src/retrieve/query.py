from __future__ import annotations

import logging
import os
from typing import Any

from embeddings import embed_batch, embedding_provider

log = logging.getLogger(__name__)


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)).strip())
    except ValueError:
        return default


def top_k() -> int:
    """Number of nearest-neighbor chunks to retrieve (``RAG_TOP_K``)."""
    return max(1, _env_int("RAG_TOP_K", 20))


def query_k_max() -> int:
    """Hard cap for per-request ``k`` overrides (``RAG_QUERY_K_MAX``)."""
    return max(1, _env_int("RAG_QUERY_K_MAX", 50))


def resolve_query_k(k: int | None) -> int:
    """Use ``RAG_TOP_K`` by default; honor ``k`` up to ``query_k_max()``."""
    default = top_k()
    if k is None:
        return default
    try:
        requested = int(k)
    except (TypeError, ValueError):
        return default
    if requested < 1:
        return default
    return min(requested, query_k_max())


def normalize_path_prefix(path_prefix: str) -> str:
    return path_prefix.strip().replace("\\", "/").lstrip("/")


def path_prefix_where(path_prefix: str) -> dict[str, Any] | None:
    norm = normalize_path_prefix(path_prefix)
    if not norm:
        return None
    return {"path": {"$contains": norm}}


def merge_where(
    where: dict[str, Any] | None,
    path_prefix: str | None,
) -> dict[str, Any] | None:
    prefix_filter = path_prefix_where(path_prefix) if path_prefix else None
    if prefix_filter is None:
        return where
    if not where:
        return prefix_filter
    return {"$and": [where, prefix_filter]}


def run_query(
    collection: Any,
    genai_client: Any,
    *,
    query_text: str,
    embedding_model: str,
    where: dict[str, Any] | None = None,
    path_prefix: str | None = None,
    k: int | None = None,
) -> dict[str, Any]:
    """Semantic search over Chroma with the same embedding model used for indexing."""
    text = (query_text or "").strip()
    if not text:
        return {"error": "query is empty", "results": [], "top_k": 0}
    effective_where = merge_where(where, path_prefix)
    result_k = resolve_query_k(k)
    provider = embedding_provider()
    vec = embed_batch(
        genai_client,
        embedding_model.strip(),
        [text],
        provider=provider,
        input_type="query",
    )
    if not vec:
        return {"error": "embedding failed", "results": [], "top_k": 0}
    kwargs: dict[str, Any] = {
        "query_embeddings": [vec[0]],
        "n_results": result_k,
        "include": ["documents", "metadatas", "distances"],
    }
    if effective_where:
        kwargs["where"] = effective_where
    try:
        raw = collection.query(**kwargs)
    except Exception as exc:
        log.exception("chroma query failed")
        return {"error": str(exc), "results": [], "top_k": 0}

    ids = raw.get("ids") or [[]]
    docs = raw.get("documents") or [[]]
    metas = raw.get("metadatas") or [[]]
    dists = raw.get("distances") or [[]]
    row_ids = ids[0] if ids else []
    row_docs = docs[0] if docs else []
    row_metas = metas[0] if metas else []
    row_dists = dists[0] if dists else []
    results: list[dict[str, Any]] = []
    for i, cid in enumerate(row_ids):
        results.append(
            {
                "id": cid,
                "document": row_docs[i] if i < len(row_docs) else "",
                "metadata": row_metas[i] if i < len(row_metas) else {},
                "distance": row_dists[i] if i < len(row_dists) else None,
            }
        )
    return {"results": results, "top_k": len(results)}
