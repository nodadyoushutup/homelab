"""Long-term agent memory storage on top of the existing Chroma + Gemini stack.

Two collections, written through strict promotion gates:

- ``memories_episodic`` (kind=``episodic``) — failure→solution pairs, source=``failure_resolution``.
- ``memories_declarative`` (kind=``declarative``) — user-asserted facts, source=``user_assertion``.

Storage, embedder, and auth are deliberately shared with the repo RAG path (no parallel stack).
Agent-facing rules live in ``applications/google-adk/agent/sub_agents/rag/instructions.md`` and
the orchestrator ``applications/google-adk/agent/instructions.md``; RAG + MCP overview in
``docs/workflows/development/rag-agent-mcp-integration-roadmap.md``.
"""
from __future__ import annotations

import logging
import os
import secrets
import time
from datetime import datetime, timezone
from typing import Any, Iterable

import chromadb
from google import genai

from rag_worker.embed_google import build_genai_client, embed_batch

log = logging.getLogger(__name__)

KIND_EPISODIC = "episodic"
KIND_DECLARATIVE = "declarative"
SOURCE_FAILURE_RESOLUTION = "failure_resolution"
SOURCE_USER_ASSERTION = "user_assertion"

VALID_KINDS = (KIND_EPISODIC, KIND_DECLARATIVE)
VALID_SOURCES = (SOURCE_FAILURE_RESOLUTION, SOURCE_USER_ASSERTION)
VALID_SCOPES = ("workflow", "policy", "schedule", "env", "other")

_KIND_SOURCE_MATRIX: dict[str, str] = {
    KIND_EPISODIC: SOURCE_FAILURE_RESOLUTION,
    KIND_DECLARATIVE: SOURCE_USER_ASSERTION,
}


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)).strip())
    except (TypeError, ValueError):
        return default


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)).strip())
    except (TypeError, ValueError):
        return default


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _now_ts() -> int:
    return int(time.time())


def _parse_iso_to_ts(value: str | None) -> int:
    if not value:
        return 0
    raw = value.strip()
    if not raw:
        return 0
    if raw.endswith("Z"):
        raw = raw[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(raw)
    except ValueError:
        return 0
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return int(dt.timestamp())


def _new_memory_id(kind: str) -> str:
    """Sortable, unique id without external deps. Format: ``memory:{kind}:{ms}:{rand}``."""
    ms = int(time.time() * 1000)
    rand = secrets.token_hex(8)
    return f"memory:{kind}:{ms:013d}:{rand}"


def _episodic_collection_name() -> str:
    return (os.getenv("RAG_MEMORY_EPISODIC_COLLECTION") or "memories_episodic").strip()


def _declarative_collection_name() -> str:
    return (os.getenv("RAG_MEMORY_DECLARATIVE_COLLECTION") or "memories_declarative").strip()


def _chroma_client():
    host = (os.getenv("RAG_CHROMA_HOST") or "chromadb").strip()
    port = int((os.getenv("RAG_CHROMA_PORT") or "8000").strip())
    return chromadb.HttpClient(host=host, port=port)


def _open_collection(name: str):
    client = _chroma_client()
    return client.get_or_create_collection(name=name, metadata={"hnsw:space": "cosine"})


def chroma_memory_episodic_collection():
    """Shared Chroma collection handle for episodic memories."""
    return _open_collection(_episodic_collection_name())


def chroma_memory_declarative_collection():
    """Shared Chroma collection handle for declarative memories."""
    return _open_collection(_declarative_collection_name())


def _collection_for_kind(kind: str):
    if kind == KIND_EPISODIC:
        return chroma_memory_episodic_collection()
    if kind == KIND_DECLARATIVE:
        return chroma_memory_declarative_collection()
    raise ValueError(f"unknown kind: {kind!r}")


def _embedding_model() -> str:
    return (os.getenv("RAG_EMBEDDING_MODEL") or "gemini-embedding-001").strip()


def _normalize_cited_paths(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        items: Iterable[str] = value.split(",")
    elif isinstance(value, (list, tuple, set)):
        items = (str(v) for v in value if v is not None and not isinstance(v, bool))
    else:
        return []
    cleaned: list[str] = []
    seen: set[str] = set()
    for item in items:
        norm = item.strip().replace("\\", "/").lstrip("/")
        if not norm or norm in seen:
            continue
        cleaned.append(norm)
        seen.add(norm)
    return cleaned


def _join_cited_paths(paths: list[str]) -> str:
    return ",".join(paths)


def _split_cited_paths(value: Any) -> list[str]:
    if not value:
        return []
    return [p for p in str(value).split(",") if p]


def _build_episodic_document(
    *, title: str, body: str, failure_class: str, failure_signature: str
) -> str:
    parts = [title.strip(), f"{failure_class}: {failure_signature}".strip(), "---", body.strip()]
    return "\n".join(p for p in parts if p)


def _build_declarative_document(*, title: str, body: str, scope: str) -> str:
    header = title.strip() if not scope else f"{title.strip()} [{scope}]"
    return f"{header}\n---\n{body.strip()}"


def _build_document(*, kind: str, fields: dict[str, str]) -> str:
    if kind == KIND_EPISODIC:
        return _build_episodic_document(
            title=fields.get("title", ""),
            body=fields.get("body", ""),
            failure_class=fields.get("failure_class", ""),
            failure_signature=fields.get("failure_signature", ""),
        )
    return _build_declarative_document(
        title=fields.get("title", ""),
        body=fields.get("body", ""),
        scope=fields.get("scope", ""),
    )


def _validate_save(
    *,
    kind: str,
    source: str,
    title: str,
    body: str,
    cited_paths: list[str],
    failure_class: str,
    failure_signature: str,
    scope: str,
) -> str | None:
    if kind not in VALID_KINDS:
        return f"kind must be one of {VALID_KINDS}"
    if source not in VALID_SOURCES:
        return f"source must be one of {VALID_SOURCES}"
    expected_source = _KIND_SOURCE_MATRIX[kind]
    if source != expected_source:
        return f"kind={kind!r} requires source={expected_source!r} (got {source!r})"
    if not title.strip():
        return "title is required"
    if not body.strip():
        return "body is required"
    if kind == KIND_EPISODIC:
        if not cited_paths and not failure_signature.strip():
            return "episodic memories require at least one cited_path or a non-empty failure_signature"
        if not failure_class.strip():
            return "episodic memories require failure_class"
    if kind == KIND_DECLARATIVE:
        if scope and scope not in VALID_SCOPES:
            return f"scope must be one of {VALID_SCOPES} when set"
    return None


def _meta_to_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _truncate_body(body: str, limit: int) -> tuple[str, bool]:
    if len(body) <= limit:
        return body, False
    return body[: max(0, limit - 1)] + "…", True


def _hit_to_payload(
    *, raw_id: str, document: str, metadata: dict[str, Any], distance: float | None, body_limit: int
) -> dict[str, Any]:
    body = document.split("\n---\n", 1)[-1] if "\n---\n" in document else document
    truncated_body, truncated = _truncate_body(body, body_limit)
    created_at = str(metadata.get("created_at") or "")
    created_ts = _parse_iso_to_ts(created_at)
    age_days: int | None
    if created_ts:
        age_days = max(0, (_now_ts() - created_ts) // 86400)
    else:
        age_days = None
    return {
        "id": raw_id,
        "kind": str(metadata.get("kind") or ""),
        "source": str(metadata.get("source") or ""),
        "title": str(metadata.get("title") or ""),
        "body": truncated_body,
        "truncated": truncated,
        "score": None if distance is None else float(distance),
        "age_days": age_days,
        "recall_count": _meta_to_int(metadata.get("recall_count")),
        "verified": bool(metadata.get("verified")),
        "expires_at": str(metadata.get("expires_at") or "") or None,
        "cited_paths": _split_cited_paths(metadata.get("cited_paths")),
        "stale_since_commit": str(metadata.get("stale_since_commit") or "") or None,
        "failure_class": str(metadata.get("failure_class") or "") or None,
        "failure_signature": str(metadata.get("failure_signature") or "") or None,
        "topic": str(metadata.get("topic") or "") or None,
        "scope": str(metadata.get("scope") or "") or None,
        "created_at": created_at or None,
        "updated_at": str(metadata.get("updated_at") or "") or None,
    }


def _dedup_distance_max() -> float:
    return max(0.0, _env_float("RAG_MEMORY_DEDUP_DISTANCE_MAX", 0.08))


def _recall_max_k() -> int:
    return max(1, _env_int("RAG_MEMORY_RECALL_MAX_K", 3))


def _recall_body_max_chars() -> int:
    return max(64, _env_int("RAG_MEMORY_RECALL_BODY_MAX_CHARS", 1024))


def _recall_refresh_days() -> int:
    return max(0, _env_int("RAG_MEMORY_RECALL_REFRESH_DAYS", 30))


def _episodic_ttl_days() -> int:
    return max(0, _env_int("RAG_MEMORY_EPISODIC_TTL_DAYS", 90))


def _declarative_tie_bias() -> float:
    return max(0.0, _env_float("RAG_MEMORY_DECLARATIVE_TIE_BIAS", 0.02))


def _expires_at_for_save(*, kind: str, requested: str) -> tuple[str, int, int]:
    """Return (iso, ts, ttl_days) honoring an explicit value, otherwise defaulting per kind.

    Declarative defaults to indefinite (``ts=0``); episodic defaults to ``RAG_MEMORY_EPISODIC_TTL_DAYS``.
    """
    if requested:
        ts = _parse_iso_to_ts(requested)
        if ts <= 0:
            return "", 0, 0
        ttl_days = max(0, (ts - _now_ts()) // 86400)
        return requested, ts, ttl_days
    if kind == KIND_EPISODIC:
        ttl_days = _episodic_ttl_days()
        if ttl_days <= 0:
            return "", 0, 0
        ts = _now_ts() + ttl_days * 86400
        return _ts_to_iso(ts), ts, ttl_days
    return "", 0, 0


def _ts_to_iso(ts: int) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _build_metadata(
    *,
    kind: str,
    source: str,
    title: str,
    cited_paths: list[str],
    author: str,
    failure_class: str,
    failure_signature: str,
    topic: str,
    scope: str,
    expires_at: str,
    expires_at_ts: int,
    ttl_days: int,
    commit: str,
    verified: bool,
) -> dict[str, Any]:
    now_iso = _now_iso()
    meta: dict[str, Any] = {
        "kind": kind,
        "source": source,
        "title": title.strip(),
        "created_at": now_iso,
        "updated_at": now_iso,
        "commit_at_write": commit.strip(),
        "author": author.strip(),
        "verified": verified,
        "recall_count": 0,
        "last_recalled_at": "",
        "cited_paths": _join_cited_paths(cited_paths),
        "ttl_days": ttl_days,
        "expires_at": expires_at,
        "expires_at_ts": expires_at_ts,
        "stale_since_commit": "",
    }
    if kind == KIND_EPISODIC:
        meta["failure_class"] = failure_class.strip()
        meta["failure_signature"] = failure_signature.strip()
    if kind == KIND_DECLARATIVE:
        meta["topic"] = (topic or title).strip()
        meta["scope"] = scope.strip()
    return meta


def _find_dedup_match(
    collection,
    *,
    embedding: list[float],
    kind: str,
    distance_max: float,
) -> dict[str, Any] | None:
    if distance_max <= 0:
        return None
    try:
        raw = collection.query(
            query_embeddings=[embedding],
            n_results=1,
            where={"kind": kind},
            include=["documents", "metadatas", "distances"],
        )
    except Exception as exc:
        log.warning("dedup lookup failed for kind=%s: %s", kind, exc)
        return None
    ids = (raw.get("ids") or [[]])[0]
    if not ids:
        return None
    distances = (raw.get("distances") or [[]])[0]
    documents = (raw.get("documents") or [[]])[0]
    metadatas = (raw.get("metadatas") or [[]])[0]
    distance = distances[0] if distances else None
    if distance is None or float(distance) > distance_max:
        return None
    return {
        "id": ids[0],
        "distance": float(distance),
        "document": documents[0] if documents else "",
        "metadata": metadatas[0] if metadatas else {},
    }


def _merge_into_existing(
    collection,
    *,
    existing_id: str,
    existing_metadata: dict[str, Any],
    existing_document: str,
    new_document: str,
    new_cited_paths: list[str],
) -> str:
    merged_paths = _split_cited_paths(existing_metadata.get("cited_paths")) + new_cited_paths
    seen: set[str] = set()
    deduped: list[str] = []
    for p in merged_paths:
        if p and p not in seen:
            deduped.append(p)
            seen.add(p)
    chosen_document = new_document if len(new_document) > len(existing_document) else existing_document
    new_meta = dict(existing_metadata)
    new_meta["updated_at"] = _now_iso()
    new_meta["recall_count"] = _meta_to_int(existing_metadata.get("recall_count")) + 1
    new_meta["cited_paths"] = _join_cited_paths(deduped)
    new_meta["stale_since_commit"] = ""
    update_kwargs: dict[str, Any] = {"ids": [existing_id], "metadatas": [new_meta]}
    if chosen_document != existing_document:
        update_kwargs["documents"] = [chosen_document]
    collection.update(**update_kwargs)
    return existing_id


def save_memory(
    *,
    genai_client: genai.Client,
    kind: str,
    source: str,
    title: str,
    body: str,
    cited_paths: Any = None,
    failure_class: str = "",
    failure_signature: str = "",
    topic: str = "",
    scope: str = "",
    expires_at: str = "",
    author: str = "",
    commit: str = "",
) -> dict[str, Any]:
    """Persist a memory through one of the two promotion gates.

    Returns ``{"id", "kind", "embedded", "dedup": {"matched_id"?, "action": ...}}``.
    """
    title = (title or "").strip()
    body = (body or "").strip()
    failure_class = (failure_class or "").strip()
    failure_signature = (failure_signature or "").strip()
    topic = (topic or "").strip()
    scope = (scope or "").strip()
    expires_at = (expires_at or "").strip()
    author = (author or "").strip()
    commit = (commit or "").strip()
    cited_list = _normalize_cited_paths(cited_paths)
    err = _validate_save(
        kind=kind,
        source=source,
        title=title,
        body=body,
        cited_paths=cited_list,
        failure_class=failure_class,
        failure_signature=failure_signature,
        scope=scope,
    )
    if err is not None:
        return {"error": "invalid_input", "message": err}
    document = _build_document(
        kind=kind,
        fields={
            "title": title,
            "body": body,
            "failure_class": failure_class,
            "failure_signature": failure_signature,
            "scope": scope,
        },
    )
    vectors = embed_batch(genai_client, _embedding_model(), [document])
    if not vectors:
        return {"error": "embedding_failed", "message": "embedder returned no vectors"}
    embedding = vectors[0]
    collection = _collection_for_kind(kind)
    distance_max = _dedup_distance_max()
    match = _find_dedup_match(
        collection, embedding=embedding, kind=kind, distance_max=distance_max
    )
    if match is not None:
        merged_id = _merge_into_existing(
            collection,
            existing_id=match["id"],
            existing_metadata=match["metadata"] if isinstance(match["metadata"], dict) else {},
            existing_document=str(match["document"] or ""),
            new_document=document,
            new_cited_paths=cited_list,
        )
        return {
            "id": merged_id,
            "kind": kind,
            "embedded": True,
            "dedup": {
                "matched_id": match["id"],
                "distance": match["distance"],
                "action": "merged",
            },
        }
    expires_iso, expires_ts, ttl_days = _expires_at_for_save(kind=kind, requested=expires_at)
    verified = source == SOURCE_USER_ASSERTION
    metadata = _build_metadata(
        kind=kind,
        source=source,
        title=title,
        cited_paths=cited_list,
        author=author,
        failure_class=failure_class,
        failure_signature=failure_signature,
        topic=topic,
        scope=scope,
        expires_at=expires_iso,
        expires_at_ts=expires_ts,
        ttl_days=ttl_days,
        commit=commit,
        verified=verified,
    )
    new_id = _new_memory_id(kind)
    collection.add(
        ids=[new_id],
        embeddings=[embedding],
        documents=[document],
        metadatas=[metadata],
    )
    return {
        "id": new_id,
        "kind": kind,
        "embedded": True,
        "dedup": {"action": "created"},
    }


def _build_recall_where(
    *, kind_filter: str | None, include_expired: bool, extra_where: dict[str, Any] | None
) -> dict[str, Any] | None:
    clauses: list[dict[str, Any]] = []
    if kind_filter is not None:
        clauses.append({"kind": kind_filter})
    if not include_expired:
        clauses.append(
            {"$or": [{"expires_at_ts": 0}, {"expires_at_ts": {"$gt": _now_ts()}}]}
        )
    if extra_where:
        clauses.append(extra_where)
    if not clauses:
        return None
    if len(clauses) == 1:
        return clauses[0]
    return {"$and": clauses}


def _query_one_collection(
    collection,
    *,
    embedding: list[float],
    k: int,
    where: dict[str, Any] | None,
) -> list[dict[str, Any]]:
    kwargs: dict[str, Any] = {
        "query_embeddings": [embedding],
        "n_results": max(1, k),
        "include": ["documents", "metadatas", "distances"],
    }
    if where is not None:
        kwargs["where"] = where
    raw = collection.query(**kwargs)
    ids = (raw.get("ids") or [[]])[0]
    documents = (raw.get("documents") or [[]])[0]
    metadatas = (raw.get("metadatas") or [[]])[0]
    distances = (raw.get("distances") or [[]])[0]
    out: list[dict[str, Any]] = []
    for i, raw_id in enumerate(ids):
        out.append(
            {
                "id": raw_id,
                "document": documents[i] if i < len(documents) else "",
                "metadata": metadatas[i] if i < len(metadatas) else {},
                "distance": distances[i] if i < len(distances) else None,
            }
        )
    return out


def _refresh_recall_metadata(collection, *, hit_id: str, metadata: dict[str, Any], kind: str) -> None:
    new_meta = dict(metadata)
    new_meta["recall_count"] = _meta_to_int(metadata.get("recall_count")) + 1
    new_meta["last_recalled_at"] = _now_iso()
    if kind == KIND_EPISODIC:
        refresh_days = _recall_refresh_days()
        if refresh_days > 0:
            current_ts = _meta_to_int(metadata.get("expires_at_ts"))
            target_ts = _now_ts() + refresh_days * 86400
            if current_ts == 0 or target_ts > current_ts:
                new_meta["expires_at_ts"] = target_ts
                new_meta["expires_at"] = _ts_to_iso(target_ts)
                new_meta["ttl_days"] = max(_meta_to_int(metadata.get("ttl_days")), refresh_days)
    try:
        collection.update(ids=[hit_id], metadatas=[new_meta])
    except Exception as exc:
        log.warning("recall metadata refresh failed for id=%s: %s", hit_id, exc)


def recall_memory(
    *,
    genai_client: genai.Client,
    query_text: str,
    k: int = 3,
    kind: str = "auto",
    where: dict[str, Any] | None = None,
    include_expired: bool = False,
) -> dict[str, Any]:
    """Semantic recall across one or both memory collections.

    ``kind`` is ``"auto"`` (blend both, declarative tie-break bias), ``"episodic"``, or
    ``"declarative"``.
    """
    text = (query_text or "").strip()
    if not text:
        return {"error": "query_empty", "message": "query is required", "results": []}
    if kind not in ("auto", KIND_EPISODIC, KIND_DECLARATIVE):
        return {
            "error": "invalid_kind",
            "message": f"kind must be one of 'auto', {KIND_EPISODIC!r}, {KIND_DECLARATIVE!r}",
            "results": [],
        }
    requested_k = max(1, int(k or 1))
    capped_k = min(requested_k, _recall_max_k())
    body_limit = _recall_body_max_chars()
    vectors = embed_batch(genai_client, _embedding_model(), [text])
    if not vectors:
        return {"error": "embedding_failed", "message": "embedder returned no vectors", "results": []}
    embedding = vectors[0]
    collected: list[tuple[float, dict[str, Any], Any, str]] = []
    if kind in ("auto", KIND_EPISODIC):
        coll = chroma_memory_episodic_collection()
        for raw in _query_one_collection(
            coll,
            embedding=embedding,
            k=capped_k,
            where=_build_recall_where(
                kind_filter=KIND_EPISODIC, include_expired=include_expired, extra_where=where
            ),
        ):
            distance = float(raw["distance"]) if raw["distance"] is not None else float("inf")
            collected.append((distance, raw, coll, KIND_EPISODIC))
    if kind in ("auto", KIND_DECLARATIVE):
        bias = _declarative_tie_bias() if kind == "auto" else 0.0
        coll = chroma_memory_declarative_collection()
        for raw in _query_one_collection(
            coll,
            embedding=embedding,
            k=capped_k,
            where=_build_recall_where(
                kind_filter=KIND_DECLARATIVE, include_expired=include_expired, extra_where=where
            ),
        ):
            distance = float(raw["distance"]) if raw["distance"] is not None else float("inf")
            collected.append((max(0.0, distance - bias), raw, coll, KIND_DECLARATIVE))
    collected.sort(key=lambda t: t[0])
    final = collected[:capped_k]
    payloads: list[dict[str, Any]] = []
    for distance, raw, coll, hit_kind in final:
        meta = raw["metadata"] if isinstance(raw["metadata"], dict) else {}
        payload = _hit_to_payload(
            raw_id=str(raw["id"]),
            document=str(raw["document"] or ""),
            metadata=meta,
            distance=None if distance == float("inf") else distance,
            body_limit=body_limit,
        )
        payloads.append(payload)
        _refresh_recall_metadata(coll, hit_id=str(raw["id"]), metadata=meta, kind=hit_kind)
    return {
        "results": payloads,
        "n_results": len(payloads),
        "k_requested": requested_k,
        "k_effective": capped_k,
        "include_expired": include_expired,
    }


def forget_memory(
    *,
    ids: list[str] | None = None,
    where: dict[str, Any] | None = None,
    dry_run: bool = False,
) -> dict[str, Any]:
    """Delete memories by id (preferred) or by a ``where`` clause.

    Operates on both collections so callers do not need to know which one a row lives in.
    """
    cleaned_ids = [i.strip() for i in (ids or []) if isinstance(i, str) and i.strip()]
    if not cleaned_ids and not where:
        return {"error": "missing_target", "message": "ids or where is required"}
    deleted_count = 0
    targets: list[tuple[str, Any]] = [
        (KIND_EPISODIC, chroma_memory_episodic_collection()),
        (KIND_DECLARATIVE, chroma_memory_declarative_collection()),
    ]
    matched_ids: dict[str, list[str]] = {KIND_EPISODIC: [], KIND_DECLARATIVE: []}
    for kind_label, coll in targets:
        if cleaned_ids:
            try:
                row = coll.get(ids=cleaned_ids, include=[])
            except Exception as exc:
                log.warning("forget lookup failed for kind=%s: %s", kind_label, exc)
                row = {"ids": []}
            present = [i for i in (row.get("ids") or []) if i]
            if not present:
                continue
            matched_ids[kind_label].extend(present)
            if not dry_run:
                coll.delete(ids=present)
            deleted_count += len(present)
        elif where:
            try:
                preview = coll.get(where=where, include=[])
            except Exception as exc:
                log.warning("forget where-lookup failed for kind=%s: %s", kind_label, exc)
                preview = {"ids": []}
            ids_in_kind = [i for i in (preview.get("ids") or []) if i]
            matched_ids[kind_label].extend(ids_in_kind)
            if ids_in_kind and not dry_run:
                coll.delete(where=where)
            deleted_count += len(ids_in_kind)
    return {
        "dry_run": dry_run,
        "deleted": 0 if dry_run else deleted_count,
        "matched": deleted_count,
        "matched_ids": matched_ids,
    }


def _stale_list_limit(limit: int | None) -> int:
    if limit is None:
        return _env_int("RAG_MEMORY_STALE_LIST_DEFAULT", 200)
    try:
        return max(1, int(limit))
    except (TypeError, ValueError):
        return _env_int("RAG_MEMORY_STALE_LIST_DEFAULT", 200)


def mark_memories_stale_for_paths(
    *,
    paths: Iterable[str],
    commit_sha: str = "",
    kinds: list[str] | None = None,
) -> dict[str, Any]:
    """Tag any memory whose ``cited_paths`` intersect ``paths`` with ``stale_since_commit``.

    Called from the commit-driven embed path so memories that referenced a now-changed
    file get downgraded on next recall (they surface ``stale_since_commit`` to the
    agent, who downgrades trust per its instructions). Does **not** delete; the human
    or a fresh failure→solution save through Gate 1 clears the flag (see
    :func:`_merge_into_existing`).
    """
    selected = kinds or list(VALID_KINDS)
    invalid = [k for k in selected if k not in VALID_KINDS]
    if invalid:
        return {"error": "invalid_kind", "message": f"unknown kinds: {invalid}"}
    touched = set(_normalize_cited_paths(list(paths)))
    summary: dict[str, Any] = {
        "commit_sha": (commit_sha or "").strip(),
        "touched_paths": len(touched),
        "by_kind": {},
        "updated_total": 0,
    }
    if not touched:
        for k in selected:
            summary["by_kind"][k] = {"scanned": 0, "updated": 0, "ids": []}
        return summary
    new_value = (commit_sha or "").strip() or _now_iso()
    for kind in selected:
        coll = _collection_for_kind(kind)
        try:
            page = coll.get(where={"kind": kind}, include=["metadatas"])
        except Exception as exc:
            log.warning("stale scan get failed for kind=%s: %s", kind, exc)
            page = {"ids": [], "metadatas": []}
        ids = list(page.get("ids") or [])
        metas = list(page.get("metadatas") or [])
        scanned = len(ids)
        updated_ids: list[str] = []
        update_metas: list[dict[str, Any]] = []
        for idx, raw_id in enumerate(ids):
            meta = metas[idx] if idx < len(metas) and isinstance(metas[idx], dict) else {}
            cited = set(_split_cited_paths(meta.get("cited_paths")))
            if not cited or cited.isdisjoint(touched):
                continue
            if str(meta.get("stale_since_commit") or "") == new_value:
                continue
            new_meta = dict(meta)
            new_meta["stale_since_commit"] = new_value
            updated_ids.append(raw_id)
            update_metas.append(new_meta)
        if updated_ids:
            try:
                coll.update(ids=updated_ids, metadatas=update_metas)
            except Exception as exc:
                log.warning("stale update failed for kind=%s: %s", kind, exc)
                updated_ids = []
        summary["by_kind"][kind] = {
            "scanned": scanned,
            "updated": len(updated_ids),
            "ids": updated_ids[:50],
        }
        summary["updated_total"] += len(updated_ids)
    return summary


def list_stale_memories(
    *,
    kinds: list[str] | None = None,
    limit: int | None = None,
) -> dict[str, Any]:
    """Return memories with ``stale_since_commit`` set, for periodic human review."""
    selected = kinds or list(VALID_KINDS)
    invalid = [k for k in selected if k not in VALID_KINDS]
    if invalid:
        return {"error": "invalid_kind", "message": f"unknown kinds: {invalid}"}
    cap = _stale_list_limit(limit)
    where = {"$and": [{"kind": {"$in": []}}]}  # placeholder, replaced per kind below
    summary: dict[str, Any] = {"by_kind": {}, "total": 0, "limit": cap}
    for kind in selected:
        coll = _collection_for_kind(kind)
        where = {"$and": [{"kind": kind}, {"stale_since_commit": {"$ne": ""}}]}
        try:
            page = coll.get(where=where, include=["metadatas", "documents"], limit=cap)
        except Exception as exc:
            log.warning("list_stale failed for kind=%s: %s", kind, exc)
            page = {"ids": [], "metadatas": [], "documents": []}
        ids = list(page.get("ids") or [])
        metas = list(page.get("metadatas") or [])
        rows: list[dict[str, Any]] = []
        for idx, raw_id in enumerate(ids):
            meta = metas[idx] if idx < len(metas) and isinstance(metas[idx], dict) else {}
            created_at = str(meta.get("created_at") or "")
            created_ts = _parse_iso_to_ts(created_at)
            age_days = max(0, (_now_ts() - created_ts) // 86400) if created_ts else None
            rows.append(
                {
                    "id": raw_id,
                    "kind": kind,
                    "title": str(meta.get("title") or ""),
                    "stale_since_commit": str(meta.get("stale_since_commit") or ""),
                    "cited_paths": _split_cited_paths(meta.get("cited_paths")),
                    "recall_count": _meta_to_int(meta.get("recall_count")),
                    "verified": bool(meta.get("verified")),
                    "age_days": age_days,
                    "created_at": created_at or None,
                    "updated_at": str(meta.get("updated_at") or "") or None,
                }
            )
        summary["by_kind"][kind] = rows
        summary["total"] += len(rows)
    return summary


def sweep_expired(*, dry_run: bool = False, kinds: list[str] | None = None) -> dict[str, Any]:
    """Remove rows whose ``expires_at_ts > 0`` and ``expires_at_ts < now``."""
    selected = kinds or list(VALID_KINDS)
    invalid = [k for k in selected if k not in VALID_KINDS]
    if invalid:
        return {"error": "invalid_kind", "message": f"unknown kinds: {invalid}"}
    now_ts = _now_ts()
    where = {
        "$and": [
            {"expires_at_ts": {"$gt": 0}},
            {"expires_at_ts": {"$lt": now_ts}},
        ]
    }
    summary: dict[str, Any] = {"dry_run": dry_run, "now_ts": now_ts, "by_kind": {}}
    total = 0
    for kind in selected:
        coll = _collection_for_kind(kind)
        try:
            preview = coll.get(where=where, include=[])
        except Exception as exc:
            log.warning("sweep lookup failed for kind=%s: %s", kind, exc)
            preview = {"ids": []}
        ids_to_delete = [i for i in (preview.get("ids") or []) if i]
        n = len(ids_to_delete)
        if n and not dry_run:
            coll.delete(where=where)
        summary["by_kind"][kind] = {
            "matched": n,
            "deleted": 0 if dry_run else n,
            "sample_ids": ids_to_delete[:50],
        }
        total += n
    summary["matched_total"] = total
    summary["deleted_total"] = 0 if dry_run else total
    return summary


def build_default_genai_client() -> genai.Client:
    """Convenience for callers that just want the same client the worker uses."""
    return build_genai_client()
