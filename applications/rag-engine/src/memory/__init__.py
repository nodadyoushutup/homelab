"""Long-term memory storage in dedicated Chroma collections (episodic / declarative).

Contracts are exercised by ``tests/test_memory.py`` and consumed by ``api.server`` and
``ingest.pipeline`` (stale marking after embed).
"""

from __future__ import annotations

import logging
import os
import secrets
import time
from datetime import datetime, timezone
from typing import Any

import chromadb

from embeddings import embed_batch, embedding_model, embedding_provider

log = logging.getLogger(__name__)

KIND_EPISODIC = "episodic"
KIND_DECLARATIVE = "declarative"
SOURCE_FAILURE_RESOLUTION = "failure_resolution"
SOURCE_USER_ASSERTION = "user_assertion"

_VALID_DECL_SCOPES = frozenset({"workflow", "policy", "schedule", "env", "other"})


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)).strip())
    except ValueError:
        return default


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)).strip())
    except ValueError:
        return default


def _now_ts() -> int:
    return int(time.time())


def _new_memory_id(kind: str) -> str:
    ts = int(time.time() * 1000)
    return f"memory:{kind}:{ts:013d}:{secrets.token_hex(4)}"


def _ts_to_iso(ts: int) -> str:
    if ts <= 0:
        return ""
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse_iso_to_ts(raw: str) -> int:
    text = (raw or "").strip()
    if not text:
        return 0
    try:
        if text.endswith("Z"):
            text = text[:-1] + "+00:00"
        return int(datetime.fromisoformat(text).timestamp())
    except ValueError:
        return 0


def _normalize_cited_paths(raw: Any) -> list[str]:
    if raw is None:
        return []
    if isinstance(raw, str):
        parts = [p.strip() for p in raw.replace(",", " ").split() if p.strip()]
    elif isinstance(raw, (list, tuple)):
        parts = [str(p).strip() for p in raw if isinstance(p, str) and p.strip()]
    else:
        return []
    out: list[str] = []
    seen: set[str] = set()
    for p in parts:
        norm = p.lstrip("/").replace("\\", "/")
        if not norm or norm in seen:
            continue
        seen.add(norm)
        out.append(norm)
    return out


def _truncate_body(text: str, max_chars: int) -> tuple[str, bool]:
    if len(text) <= max_chars:
        return text, False
    return text[:max_chars], True


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
    if kind == KIND_EPISODIC:
        if source != SOURCE_FAILURE_RESOLUTION:
            return f"episodic memories require source={SOURCE_FAILURE_RESOLUTION!r}, got {source!r}"
        if not failure_class.strip():
            return "failure_class is required for episodic memories"
        if not cited_paths and not failure_signature.strip():
            return "episodic memory requires cited_paths and/or failure_signature"
    elif kind == KIND_DECLARATIVE:
        if source != SOURCE_USER_ASSERTION:
            return f"declarative memories require source={SOURCE_USER_ASSERTION!r}, got {source!r}"
        sc = scope.strip()
        if sc and sc not in _VALID_DECL_SCOPES:
            return f"scope must be one of {sorted(_VALID_DECL_SCOPES)}, got {scope!r}"
    else:
        return f"unknown kind {kind!r}"
    if not title.strip() or not body.strip():
        return "title and body must be non-empty"
    return None


def _chroma_client() -> chromadb.HttpClient:
    from chroma_config import chroma_http_client

    return chroma_http_client()


def chroma_memory_episodic_collection() -> Any:
    name = (os.getenv("RAG_MEMORY_EPISODIC_COLLECTION") or "memories_episodic").strip()
    return _chroma_client().get_or_create_collection(name=name, metadata={"hnsw:space": "cosine"})


def chroma_memory_declarative_collection() -> Any:
    name = (os.getenv("RAG_MEMORY_DECLARATIVE_COLLECTION") or "memories_declarative").strip()
    return _chroma_client().get_or_create_collection(name=name, metadata={"hnsw:space": "cosine"})


def _collection_for_kind(kind: str) -> Any:
    if kind == KIND_EPISODIC:
        return chroma_memory_episodic_collection()
    if kind == KIND_DECLARATIVE:
        return chroma_memory_declarative_collection()
    raise ValueError(f"unknown memory kind {kind!r}")


def _dedup_threshold() -> float:
    return _env_float("RAG_MEMORY_DEDUP_DISTANCE_MAX", 0.05)


def _recall_cap() -> int:
    return max(1, _env_int("RAG_MEMORY_RECALL_MAX_K", 3))


def _episodic_ttl_sec() -> int:
    return max(1, _env_int("RAG_MEMORY_EPISODIC_TTL_DAYS", 30)) * 86400


def _body_max_chars() -> int:
    return max(256, _env_int("RAG_MEMORY_BODY_MAX_CHARS", 16000))


def save_memory(
    genai_client: Any,
    *,
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
    paths = _normalize_cited_paths(cited_paths)
    err = _validate_save(
        kind=kind,
        source=source,
        title=title.strip(),
        body=body.strip(),
        cited_paths=paths,
        failure_class=failure_class,
        failure_signature=failure_signature,
        scope=scope,
    )
    if err:
        return {"error": err}

    model = embedding_model().strip()
    provider = embedding_provider()
    text = f"{title.strip()}\n\n{body.strip()}"
    truncated, was_trunc = _truncate_body(body.strip(), _body_max_chars())
    embed_text = f"{title.strip()}\n\n{truncated}"
    vec = embed_batch(
        genai_client,
        model,
        [embed_text],
        provider=provider,
        input_type="document",
    )
    if not vec:
        return {"error": "embedding_failed", "message": "embed_batch returned no vectors"}

    collection = _collection_for_kind(kind)
    now = _now_ts()
    expires_ts = 0
    if kind == KIND_EPISODIC:
        expires_ts = now + _episodic_ttl_sec()
    else:
        expires_ts = _parse_iso_to_ts(expires_at) if expires_at.strip() else 0

    q = collection.query(
        query_embeddings=[vec[0]],
        n_results=3,
        include=["distances", "metadatas", "documents"],
    )
    best_id: str | None = None
    best_dist: float | None = None
    ids_batch = (q.get("ids") or [[]])[0]
    dists_batch = (q.get("distances") or [[]])[0]
    for i, rid in enumerate(ids_batch):
        if not rid:
            continue
        dist = dists_batch[i] if i < len(dists_batch) else None
        if dist is None:
            continue
        if best_dist is None or dist < best_dist:
            best_dist = float(dist)
            best_id = str(rid)

    thresh = _dedup_threshold()
    if best_id is not None and best_dist is not None and best_dist <= thresh:
        cur = collection.get(ids=[best_id], include=["metadatas", "documents"])
        metas = cur.get("metadatas") or []
        docs = cur.get("documents") or []
        meta = dict(metas[0]) if metas else {}
        old_body = (docs[0] if docs else "") or ""
        merged_paths = sorted(set((meta.get("cited_paths") or "").split(",")) | set(paths) - {""})
        new_body = old_body if old_body.strip() else truncated
        if truncated.strip() and truncated not in new_body:
            new_body = f"{new_body.rstrip()}\n\n---\n\n{truncated.strip()}"
        meta["cited_paths"] = ",".join(merged_paths)
        meta["recall_count"] = int(meta.get("recall_count") or 0) + 1
        meta["stale_since_commit"] = ""
        collection.update(ids=[best_id], documents=[new_body], metadatas=[meta])
        return {
            "id": best_id,
            "kind": kind,
            "dedup": {"action": "merged", "distance": best_dist},
            "truncated": was_trunc,
        }

    mem_id = _new_memory_id(kind)
    verified = kind == KIND_DECLARATIVE and source == SOURCE_USER_ASSERTION
    meta: dict[str, Any] = {
        "kind": kind,
        "source": source,
        "title": title.strip(),
        "failure_class": failure_class.strip(),
        "failure_signature": failure_signature.strip(),
        "topic": topic.strip(),
        "scope": scope.strip(),
        "expires_at": expires_at.strip(),
        "author": author.strip(),
        "commit_at_write": commit.strip(),
        "cited_paths": ",".join(paths),
        "expires_at_ts": int(expires_ts),
        "created_at_ts": now,
        "recall_count": 0,
        "verified": bool(verified),
        "stale_since_commit": "",
    }
    collection.add(ids=[mem_id], embeddings=[vec[0]], documents=[truncated], metadatas=[meta])
    return {
        "id": mem_id,
        "kind": kind,
        "dedup": {"action": "created"},
        "truncated": was_trunc,
    }


def _hit_from_row(
    rid: str,
    *,
    kind: str,
    document: str,
    metadata: dict[str, Any],
    score: float | None,
) -> dict[str, Any]:
    created = int(metadata.get("created_at_ts") or 0)
    age_days = max(0, int((_now_ts() - created) / 86400)) if created else 0
    cites = (metadata.get("cited_paths") or "").split(",") if metadata.get("cited_paths") else []
    return {
        "id": rid,
        "kind": kind,
        "source": metadata.get("source") or "",
        "title": metadata.get("title") or "",
        "body": document or "",
        "score": float(score) if score is not None else None,
        "age_days": age_days,
        "recall_count": int(metadata.get("recall_count") or 0),
        "verified": bool(metadata.get("verified", False)),
        "cited_paths": [c for c in cites if c.strip()],
        "stale_since_commit": metadata.get("stale_since_commit") or "",
        "expires_at": metadata.get("expires_at") or "",
    }


def recall_memory(
    genai_client: Any,
    *,
    query_text: str,
    k: int,
    kind: str,
    where: dict[str, Any] | None = None,
    include_expired: bool = False,
) -> dict[str, Any]:
    text = (query_text or "").strip()
    if not text:
        return {"error": "query is empty", "results": [], "n_results": 0}

    model = embedding_model().strip()
    provider = embedding_provider()
    vec = embed_batch(
        genai_client,
        model,
        [text],
        provider=provider,
        input_type="query",
    )
    if not vec:
        return {"error": "embedding_failed", "results": [], "n_results": 0}

    cap = min(max(1, k), _recall_cap())
    kinds_to_query: list[str]
    if kind in ("", "auto"):
        kinds_to_query = [KIND_EPISODIC, KIND_DECLARATIVE]
    elif kind == KIND_EPISODIC:
        kinds_to_query = [KIND_EPISODIC]
    elif kind == KIND_DECLARATIVE:
        kinds_to_query = [KIND_DECLARATIVE]
    else:
        return {"error": f"invalid kind {kind!r}", "results": [], "n_results": 0}

    now = _now_ts()
    merged: list[tuple[float, str, str, str, dict[str, Any]]] = []
    for kd in kinds_to_query:
        col = _collection_for_kind(kd)
        kwargs: dict[str, Any] = {
            "query_embeddings": [vec[0]],
            "n_results": cap,
            "include": ["documents", "metadatas", "distances"],
        }
        if where:
            kwargs["where"] = where
        raw = col.query(**kwargs)
        ids = (raw.get("ids") or [[]])[0]
        docs = (raw.get("documents") or [[]])[0]
        metas = (raw.get("metadatas") or [[]])[0]
        dists = (raw.get("distances") or [[]])[0]
        for i, rid in enumerate(ids):
            if not rid:
                continue
            meta = metas[i] if i < len(metas) else {}
            if not include_expired:
                exp_ts = int(meta.get("expires_at_ts") or 0)
                if exp_ts and exp_ts < now:
                    continue
            dist = dists[i] if i < len(dists) else None
            merged.append((float(dist) if dist is not None else 1e9, kd, rid, docs[i] if i < len(docs) else "", meta))

    merged.sort(key=lambda x: x[0])
    merged = merged[:cap]
    results: list[dict[str, Any]] = []
    for dist, kd, rid, doc, meta in merged:
        results.append(_hit_from_row(rid, kind=kd, document=doc, metadata=meta, score=dist))
        try:
            col2 = _collection_for_kind(kd)
            new_meta = dict(meta)
            new_meta["recall_count"] = int(meta.get("recall_count") or 0) + 1
            col2.update(ids=[rid], metadatas=[new_meta])
        except Exception as exc:
            log.warning("recall increment failed id=%s: %s", rid, exc)

    return {"results": results, "n_results": len(results)}


def forget_memory(
    *,
    ids: list[str],
    where: dict[str, Any] | None = None,
    dry_run: bool = False,
) -> dict[str, Any]:
    deleted = 0
    for kd in (KIND_EPISODIC, KIND_DECLARATIVE):
        col = _collection_for_kind(kd)
        if ids:
            cur = col.get(ids=ids, include=[])
            present = set(cur.get("ids") or [])
            if dry_run:
                deleted += len(present)
            else:
                if present:
                    col.delete(ids=list(present))
                deleted += len(present)
        elif where is not None:
            cur = col.get(where=where, include=[])
            id_list = list(cur.get("ids") or [])
            if dry_run:
                deleted += len(id_list)
            elif id_list:
                col.delete(ids=id_list)
                deleted += len(id_list)
    return {"deleted": deleted, "dry_run": dry_run}


def sweep_expired(*, dry_run: bool, kinds: list[str] | None) -> dict[str, Any]:
    now = _now_ts()
    targets = kinds if kinds else [KIND_EPISODIC, KIND_DECLARATIVE]
    deleted_total = 0
    for kd in targets:
        if kd not in (KIND_EPISODIC, KIND_DECLARATIVE):
            continue
        col = _collection_for_kind(kd)
        data = col.get(include=["metadatas"], limit=10_000)
        id_list: list[str] = []
        for i, rid in enumerate(data.get("ids") or []):
            meta = (data.get("metadatas") or [])[i] if i < len(data.get("metadatas") or []) else {}
            try:
                exp_ts = int(meta.get("expires_at_ts") or 0)
            except (TypeError, ValueError):
                exp_ts = 0
            if exp_ts > 0 and exp_ts <= now:
                id_list.append(str(rid))
        if not id_list:
            continue
        if dry_run:
            deleted_total += len(id_list)
        else:
            col.delete(ids=id_list)
            deleted_total += len(id_list)
    return {"deleted_total": deleted_total, "dry_run": dry_run}


def list_stale_memories(*, kinds: list[str] | None, limit: int | None) -> dict[str, Any]:
    targets = kinds if kinds else [KIND_EPISODIC, KIND_DECLARATIVE]
    lim = limit if isinstance(limit, int) and limit > 0 else 10_000
    by_kind: dict[str, Any] = {}
    total = 0
    for kd in targets:
        if kd not in (KIND_EPISODIC, KIND_DECLARATIVE):
            continue
        col = _collection_for_kind(kd)
        data = col.get(include=["metadatas", "documents"], limit=lim)
        rows: list[dict[str, Any]] = []
        for i, rid in enumerate(data.get("ids") or []):
            meta = (data.get("metadatas") or [])[i] if i < len(data.get("metadatas") or []) else {}
            if not (meta.get("stale_since_commit") or "").strip():
                continue
            doc = (data.get("documents") or [])[i] if i < len(data.get("documents") or []) else ""
            rows.append(_hit_from_row(str(rid), kind=kd, document=str(doc or ""), metadata=dict(meta or {}), score=None))
        by_kind[kd] = rows
        total += len(rows)
    return {"total": total, "by_kind": by_kind}


def mark_memories_stale_for_paths(
    *,
    paths: list[str],
    commit_sha: str,
    kinds: list[str] | None = None,
) -> dict[str, Any]:
    norm_paths: list[str] = []
    for p in paths:
        norm_paths.extend(_normalize_cited_paths([str(p)]))
    seen_np: set[str] = set()
    deduped: list[str] = []
    for p in norm_paths:
        if p not in seen_np:
            seen_np.add(p)
            deduped.append(p)
    norm_paths = deduped
    if not norm_paths:
        return {
            "updated_total": 0,
            "by_kind": {
                KIND_EPISODIC: {"updated": 0, "scanned": 0, "ids": []},
                KIND_DECLARATIVE: {"updated": 0, "scanned": 0, "ids": []},
            },
        }

    targets = kinds if kinds else [KIND_EPISODIC, KIND_DECLARATIVE]
    updated_total = 0
    by_kind: dict[str, dict[str, Any]] = {}
    commit = (commit_sha or "").strip()

    for kd in targets:
        if kd not in (KIND_EPISODIC, KIND_DECLARATIVE):
            continue
        col = _collection_for_kind(kd)
        data = col.get(include=["metadatas"], limit=50_000)
        ids = data.get("ids") or []
        metas = data.get("metadatas") or []
        scanned = 0
        updated_ids: list[str] = []
        for i, rid in enumerate(ids):
            scanned += 1
            meta = dict(metas[i]) if i < len(metas) else {}
            cites_raw = (meta.get("cited_paths") or "").split(",")
            cites = {c.strip().lstrip("/").replace("\\", "/") for c in cites_raw if c.strip()}
            hit = any(np in cites for np in norm_paths)
            if not hit:
                continue
            prev = (meta.get("stale_since_commit") or "").strip()
            if prev == commit:
                continue
            meta["stale_since_commit"] = commit
            col.update(ids=[str(rid)], metadatas=[meta])
            updated_ids.append(str(rid))
        updated_total += len(updated_ids)
        by_kind[kd] = {"updated": len(updated_ids), "scanned": scanned, "ids": updated_ids}

    for kd in (KIND_EPISODIC, KIND_DECLARATIVE):
        by_kind.setdefault(kd, {"updated": 0, "scanned": 0, "ids": []})

    return {"updated_total": updated_total, "by_kind": by_kind}
