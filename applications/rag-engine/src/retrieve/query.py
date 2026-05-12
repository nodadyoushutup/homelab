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


def run_query(
    collection: Any,
    genai_client: Any,
    *,
    query_text: str,
    n_results: int,
    embedding_model: str,
    where: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Semantic search over Chroma with the same embedding model used for indexing."""
    text = (query_text or "").strip()
    if not text:
        return {"error": "query is empty", "results": []}
    cap = max(1, _env_int("RAG_QUERY_MAX_N_RESULTS", 50))
    n = max(1, min(int(n_results), cap))
    provider = embedding_provider()
    vec = embed_batch(genai_client, embedding_model.strip(), [text], provider=provider)
    if not vec:
        return {"error": "embedding failed", "results": []}
    kwargs: dict[str, Any] = {
        "query_embeddings": [vec[0]],
        "n_results": n,
        "include": ["documents", "metadatas", "distances"],
    }
    if where:
        kwargs["where"] = where
    try:
        raw = collection.query(**kwargs)
    except Exception as exc:
        log.exception("chroma query failed")
        return {"error": str(exc), "results": []}

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
    return {"results": results, "n_results": len(results)}
