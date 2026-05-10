from __future__ import annotations

import hashlib
import logging
import os
import random
import time
from pathlib import Path
from typing import Any, Callable, TypeVar

import chromadb
import httpx

from rag_engine.chunking import chunk_text
from rag_engine.embeddings import (
    build_embedding_client,
    embed_batch,
    embedding_dimensions_label,
    embedding_model,
    embedding_provider,
)
from rag_engine.memory import mark_memories_stale_for_paths
from rag_engine.path_rules import file_has_excluded_suffix, path_has_excluded_segment
from rag_engine.office_chunks import (
    build_docx_chunks,
    build_odt_chunks,
    build_pptx_chunks,
    office_docx_profile,
    office_odt_profile,
    office_pptx_profile,
)
from rag_engine.pdf_hybrid import build_pdf_hybrid_chunks, pdf_ingest_profile
from rag_engine.git_line_meta import GIT_LINE_META_VERSION, enrich_chunk_git_metadata
from rag_engine.structured_chunks import build_structured_chunks, index_schema_version
from rag_engine.tabular_chunks import build_xlsx_chunks, tabular_csv_profile, tabular_xlsx_profile

log = logging.getLogger(__name__)

_T = TypeVar("_T")


def _chroma_env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)).strip())
    except ValueError:
        return default


def _chroma_env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)).strip())
    except ValueError:
        return default


def _is_chroma_transient_http_error(exc: BaseException) -> bool:
    """Disconnects and other retryable failures talking to the Chroma HTTP API."""
    if isinstance(
        exc,
        (
            httpx.RemoteProtocolError,
            httpx.ConnectError,
            httpx.ReadTimeout,
            httpx.WriteTimeout,
            httpx.PoolTimeout,
            httpx.ConnectTimeout,
        ),
    ):
        return True
    if isinstance(exc, httpx.HTTPStatusError) and exc.response is not None:
        return exc.response.status_code in (408, 502, 503, 504)
    cur: BaseException | None = exc
    seen: set[int] = set()
    while cur is not None and id(cur) not in seen:
        seen.add(id(cur))
        if isinstance(cur, (BrokenPipeError, ConnectionResetError, ConnectionAbortedError)):
            return True
        cur = cur.__cause__ or cur.__context__
    return False


def _chroma_retryable_call(op_name: str, fn: Callable[[], _T]) -> _T:
    max_retries = max(1, _chroma_env_int("RAG_CHROMA_HTTP_MAX_RETRIES", 6))
    base_delay = max(0.01, _chroma_env_float("RAG_CHROMA_HTTP_BASE_DELAY_SEC", 1.0))
    max_delay = max(base_delay, _chroma_env_float("RAG_CHROMA_HTTP_MAX_DELAY_SEC", 60.0))
    last_err: BaseException | None = None
    for attempt in range(max_retries):
        try:
            return fn()
        except BaseException as exc:
            last_err = exc
            if attempt + 1 >= max_retries or not _is_chroma_transient_http_error(exc):
                raise
            backoff = min(base_delay * (2**attempt) + random.uniform(0, base_delay), max_delay)
            log.warning(
                "chroma %s transient error (attempt %s/%s), sleeping %.2fs: %s",
                op_name,
                attempt + 1,
                max_retries,
                backoff,
                exc,
            )
            time.sleep(backoff)
    assert last_err is not None
    raise last_err


def _chroma_delete_by_path(collection, rel_norm: str) -> None:
    _chroma_retryable_call("delete", lambda: collection.delete(where={"path": rel_norm}))


def _chroma_add_batched(
    collection,
    *,
    ids: list[str],
    embeddings: list,
    documents: list[str],
    metadatas: list[dict],
) -> None:
    batch = _chroma_env_int("RAG_CHROMA_ADD_BATCH_SIZE", 0)
    n = len(ids)
    if n == 0:
        return

    def add_slice(lo: int, hi: int) -> None:
        collection.add(
            ids=ids[lo:hi],
            embeddings=embeddings[lo:hi],
            documents=documents[lo:hi],
            metadatas=metadatas[lo:hi],
        )

    if batch <= 0 or n <= batch:
        _chroma_retryable_call("add", lambda: add_slice(0, n))
        return
    for lo in range(0, n, batch):
        hi = min(lo + batch, n)
        _chroma_retryable_call("add_batch", lambda lo=lo, hi=hi: add_slice(lo, hi))


def _workspace_root() -> Path:
    return Path(os.environ["RAG_WORKSPACE_MOUNT"]).resolve()


def _allowed_prefixes() -> list[str]:
    raw = (
        os.getenv("RAG_ALLOWED_PATH_PREFIXES")
        or "docs/,applications/,kubernetes/,terraform/,scripts/,pipelines/,packer/,AGENTS.md"
    ).strip()
    out: list[str] = []
    for p in raw.split(","):
        p = p.strip().replace("\\", "/").lstrip("/")
        if p:
            out.append(p)
    return out


def _matches_allowed_prefix(rel_norm: str) -> bool:
    if not rel_norm or ".." in Path(rel_norm).parts:
        return False
    for p in _allowed_prefixes():
        if p.endswith("/"):
            base = p.rstrip("/")
            if rel_norm == base or rel_norm.startswith(base + "/"):
                return True
        elif rel_norm == p:
            return True
    return False


def _should_index_path(rel_norm: str) -> bool:
    """Prefix allowlist and not under excluded segments (venv, node_modules, …)."""
    if not _matches_allowed_prefix(rel_norm):
        return False
    if path_has_excluded_segment(rel_norm):
        return False
    if file_has_excluded_suffix(rel_norm):
        return False
    return True


def _collection():
    host = (os.getenv("RAG_CHROMA_HOST") or "chromadb").strip()
    port = int((os.getenv("RAG_CHROMA_PORT") or "8000").strip())
    name = (os.getenv("RAG_CHROMA_COLLECTION") or "repo_rag").strip()
    client = chromadb.HttpClient(host=host, port=port)
    return client.get_or_create_collection(name=name, metadata={"hnsw:space": "cosine"})


def chroma_repo_collection():
    """Shared Chroma collection handle (same as embed / backfill)."""
    return _collection()


def _file_bytes_and_digest(full_path: Path) -> tuple[bytes, str]:
    raw = full_path.read_bytes()
    return raw, hashlib.sha256(raw).hexdigest()


def _stored_index_fingerprint(collection, rel_norm: str) -> dict | None:
    """First chunk metadata for ``path`` (all chunks share the same fingerprint fields)."""
    r = _chroma_retryable_call(
        "get",
        lambda: collection.get(where={"path": rel_norm}, limit=1, include=["metadatas"]),
    )
    ids = r.get("ids") or []
    if not ids:
        return None
    metas = r.get("metadatas") or []
    if not metas:
        return None
    return metas[0] if isinstance(metas[0], dict) else None


def _structured_max_chars() -> int:
    try:
        return int(os.getenv("RAG_STRUCTURED_MAX_CHUNK_CHARS", "12000").strip())
    except ValueError:
        return 12000


def _fingerprint_matches_disk(
    stored: dict | None,
    *,
    content_sha256: str,
    provider: str,
    model: str,
    dimensions: str,
    schema_ver: str,
    chunk_strategy: str,
    chunk_chars: int,
    overlap: int,
    structured_max: int,
) -> bool:
    if not stored:
        return False
    try:
        if int(stored.get("git_line_meta_version", 0)) != GIT_LINE_META_VERSION:
            return False
    except (TypeError, ValueError):
        return False
    if (stored.get("content_sha256") or "") != content_sha256:
        return False
    if str(stored.get("embedding_provider") or "google").lower() != provider:
        return False
    if (stored.get("model") or "") != model:
        return False
    if str(stored.get("embedding_dimensions") or "") != dimensions:
        return False
    if (stored.get("index_schema_version") or "") != schema_ver:
        return False
    if (stored.get("chunk_strategy") or "") != chunk_strategy:
        return False
    try:
        if chunk_strategy == "char":
            if int(stored.get("chunk_chars", -1)) != chunk_chars:
                return False
            if int(stored.get("chunk_overlap", -1)) != overlap:
                return False
        else:
            if int(stored.get("structured_max_chars", -1)) != structured_max:
                return False
            if chunk_strategy == "pdf_hybrid":
                if (stored.get("pdf_ingest_profile") or "") != pdf_ingest_profile():
                    return False
            elif chunk_strategy == "ast_csv":
                if (stored.get("tabular_ingest_profile") or "") != tabular_csv_profile():
                    return False
            elif chunk_strategy == "ast_xlsx":
                if (stored.get("tabular_ingest_profile") or "") != tabular_xlsx_profile():
                    return False
            elif chunk_strategy == "office_docx":
                if (stored.get("office_ingest_profile") or "") != office_docx_profile():
                    return False
            elif chunk_strategy == "office_pptx":
                if (stored.get("office_ingest_profile") or "") != office_pptx_profile():
                    return False
            elif chunk_strategy == "office_odt":
                if (stored.get("office_ingest_profile") or "") != office_odt_profile():
                    return False
    except (TypeError, ValueError):
        return False
    return True


def delete_paths(collection, paths: list[str]) -> int:
    n = 0
    for rel in paths:
        rel_norm = rel.strip().replace("\\", "/").lstrip("/")
        if not _matches_allowed_prefix(rel_norm):
            log.warning("skip delete (not under RAG prefix): %s", rel)
            continue
        collection.delete(where={"path": rel_norm})
        n += 1
    return n


def _chroma_list_batch_size() -> int:
    try:
        return max(100, int(os.getenv("RAG_CHROMA_LIST_BATCH", "5000").strip()))
    except ValueError:
        return 5000


def collect_indexed_paths(collection) -> set[str]:
    """Distinct ``path`` metadata values currently stored in the collection."""
    paths: set[str] = set()
    offset = 0
    batch = _chroma_list_batch_size()
    while True:
        r = collection.get(include=["metadatas"], limit=batch, offset=offset)
        ids = r.get("ids") or []
        if not ids:
            break
        metas = r.get("metadatas") or []
        for m in metas:
            if not isinstance(m, dict):
                continue
            raw = m.get("path")
            if raw is None:
                continue
            rel_norm = str(raw).strip().replace("\\", "/").lstrip("/")
            if rel_norm:
                paths.add(rel_norm)
        offset += len(ids)
    return paths


def prune_orphan_paths(collection, *, dry_run: bool = False) -> dict[str, Any]:
    """Remove Chroma rows whose ``path`` is not in the current backfill-eligible file set.

    Safe: only deletes by exact ``path`` metadata (same as ``delete_paths``). Paths outside
    ``RAG_ALLOWED_PATH_PREFIXES`` are reported but not deleted.
    """
    desired = set(collect_backfill_relative_paths())
    indexed = collect_indexed_paths(collection)
    orphans = sorted(indexed - desired)
    actionable = [p for p in orphans if _matches_allowed_prefix(p)]
    outside = [p for p in orphans if not _matches_allowed_prefix(p)]
    deleted_ops = 0
    if actionable and not dry_run:
        deleted_ops = delete_paths(collection, actionable)
    return {
        "dry_run": dry_run,
        "indexed_distinct_paths": len(indexed),
        "desired_paths": len(desired),
        "orphans_total": len(orphans),
        "orphans_actionable": len(actionable),
        "outside_allowed_prefix": len(outside),
        "delete_operations": deleted_ops if not dry_run else 0,
        "orphan_paths_sample": actionable[:200],
        "outside_prefix_sample": outside[:50],
    }


def upsert_paths(
    collection,
    genai_client,
    paths: list[str],
    commit: str,
    *,
    skip_unchanged: bool = False,
) -> dict:
    provider = embedding_provider()
    model = embedding_model(provider)
    dimensions = embedding_dimensions_label(provider)
    chunk_chars = int(os.getenv("RAG_CHUNK_CHARS", "1500"))
    overlap = int(os.getenv("RAG_CHUNK_OVERLAP", "200"))
    try:
        struct_overlap = int(os.getenv("RAG_STRUCTURED_CHUNK_OVERLAP", "200").strip())
    except ValueError:
        struct_overlap = 200
    root = _workspace_root()
    stats = {"indexed": 0, "chunks": 0, "skipped": 0, "unchanged": 0, "errors": []}

    for rel in paths:
        rel_norm = rel.strip().replace("\\", "/").lstrip("/")
        if not _should_index_path(rel_norm):
            log.info("skip upsert (prefix or exclude rule): %s", rel_norm)
            stats["skipped"] += 1
            continue
        full = (root / rel_norm).resolve()
        try:
            full.relative_to(root)
        except ValueError:
            log.warning("path escapes workspace: %s", rel_norm)
            stats["skipped"] += 1
            continue
        if not full.is_file():
            log.info("not a file at HEAD, removing vectors if any: %s", rel_norm)
            _chroma_delete_by_path(collection, rel_norm)
            stats["skipped"] += 1
            continue
        try:
            raw, digest = _file_bytes_and_digest(full)
        except OSError as exc:
            stats["errors"].append(f"{rel_norm}: read failed: {exc}")
            continue
        schema_ver = index_schema_version()
        structured_max = _structured_max_chars()
        is_pdf = rel_norm.lower().endswith(".pdf")
        is_xlsx = rel_norm.lower().endswith(".xlsx")
        low = rel_norm.lower()
        is_docx = low.endswith(".docx")
        is_pptx = low.endswith(".pptx")
        is_odt = low.endswith(".odt")
        structured: list | None = None
        st: str | None = None
        body = ""

        if is_pdf:
            try:
                structured = build_pdf_hybrid_chunks(rel_norm, raw)
            except Exception as exc:
                stats["errors"].append(f"{rel_norm}: pdf ingest: {exc}")
                continue
            st = "pdf_hybrid" if structured else None
            eff_strategy = st if structured else "char"
        elif is_xlsx:
            try:
                structured = build_xlsx_chunks(rel_norm, raw)
            except Exception as exc:
                stats["errors"].append(f"{rel_norm}: xlsx ingest: {exc}")
                continue
            st = "ast_xlsx" if structured else None
            eff_strategy = st if structured else "char"
        elif is_docx:
            try:
                structured = build_docx_chunks(rel_norm, raw, max_chars=structured_max, overlap=struct_overlap)
            except Exception as exc:
                stats["errors"].append(f"{rel_norm}: docx ingest: {exc}")
                continue
            st = "office_docx" if structured else None
            eff_strategy = st if structured else "char"
        elif is_pptx:
            try:
                structured = build_pptx_chunks(rel_norm, raw, max_chars=structured_max, overlap=struct_overlap)
            except Exception as exc:
                stats["errors"].append(f"{rel_norm}: pptx ingest: {exc}")
                continue
            st = "office_pptx" if structured else None
            eff_strategy = st if structured else "char"
        elif is_odt:
            try:
                structured = build_odt_chunks(rel_norm, raw, max_chars=structured_max, overlap=struct_overlap)
            except Exception as exc:
                stats["errors"].append(f"{rel_norm}: odt ingest: {exc}")
                continue
            st = "office_odt" if structured else None
            eff_strategy = st if structured else "char"
        else:
            body = raw.decode("utf-8-sig", errors="replace")
            st, structured = build_structured_chunks(rel_norm, body)
            eff_strategy = st if structured else "char"

        if skip_unchanged:
            fp = _stored_index_fingerprint(collection, rel_norm)
            if _fingerprint_matches_disk(
                fp,
                content_sha256=digest,
                provider=provider,
                model=model,
                dimensions=dimensions,
                schema_ver=schema_ver,
                chunk_strategy=eff_strategy,
                chunk_chars=chunk_chars,
                overlap=overlap,
                structured_max=structured_max,
            ):
                stats["unchanged"] += 1
                continue

        if structured:
            documents = [c.document for c in structured]
            metas_extra = [c.extra_metadata() for c in structured]
            enrich_chunk_git_metadata(
                root, rel_norm, structured, metas_extra, eff_strategy=eff_strategy
            )
        elif is_pdf or is_xlsx or is_docx or is_pptx or is_odt:
            _chroma_delete_by_path(collection, rel_norm)
            stats["indexed"] += 1
            continue
        else:
            documents = chunk_text(body, chunk_chars, overlap)
            metas_extra = [{} for _ in documents]
            enrich_chunk_git_metadata(
                root, rel_norm, None, metas_extra, eff_strategy="char"
            )
        if not documents:
            _chroma_delete_by_path(collection, rel_norm)
            stats["indexed"] += 1
            continue
        _chroma_delete_by_path(collection, rel_norm)
        ids = [f"{rel_norm}#{i}" for i in range(len(documents))]
        metadatas = []
        for i, extra in enumerate(metas_extra):
            row = {
                "path": rel_norm,
                "commit": commit,
                "chunk": i,
                "embedding_provider": provider,
                "model": model,
                "embedding_dimensions": dimensions,
                "content_sha256": digest,
                "index_schema_version": schema_ver,
                "chunk_strategy": eff_strategy,
                "chunk_chars": 0 if eff_strategy != "char" else chunk_chars,
                "chunk_overlap": 0 if eff_strategy != "char" else overlap,
                "structured_max_chars": structured_max if eff_strategy != "char" else 0,
                "git_line_meta_version": GIT_LINE_META_VERSION,
            }
            for k, v in extra.items():
                if isinstance(v, bool):
                    row[k] = v
                elif isinstance(v, int):
                    row[k] = v
                elif v is not None and v != "":
                    row[k] = str(v)
            metadatas.append(row)
        embeddings = embed_batch(genai_client, model, documents, provider=provider)
        _chroma_add_batched(
            collection,
            ids=ids,
            embeddings=embeddings,
            documents=documents,
            metadatas=metadatas,
        )
        stats["chunks"] += len(documents)
        stats["indexed"] += 1
    return stats


def run_embed_job(commit: str, paths: list[str], removed_paths: list[str]) -> dict:
    collection = _collection()
    genai_client = build_embedding_client()
    deleted = delete_paths(collection, removed_paths)
    up = upsert_paths(collection, genai_client, paths, commit, skip_unchanged=False)
    touched = list(set(paths) | set(removed_paths))
    try:
        stale = mark_memories_stale_for_paths(paths=touched, commit_sha=commit)
    except Exception as exc:
        log.warning("memory stale marking failed for commit=%s: %s", commit, exc)
        stale = {"error": "stale_marking_failed", "message": str(exc)}
    return {"commit": commit, "removed": deleted, **up, "stale_memories": stale}


def collect_backfill_relative_paths() -> list[str]:
    """All indexable files under ``RAG_ALLOWED_PATH_PREFIXES`` (respects exclude segments)."""
    root = _workspace_root()
    max_bytes = int(os.getenv("RAG_BACKFILL_MAX_FILE_BYTES", str(5 * 1024 * 1024)))
    seen: set[str] = set()

    for p in _allowed_prefixes():
        p = p.strip().replace("\\", "/").lstrip("/")
        if not p:
            continue
        if not p.endswith("/"):
            rel = p
            if not _should_index_path(rel):
                continue
            full = (root / rel).resolve()
            try:
                full.relative_to(root)
            except ValueError:
                continue
            if not full.is_file():
                continue
            try:
                if full.stat().st_size > max_bytes:
                    continue
            except OSError:
                continue
            seen.add(rel)
            continue

        base = (root / p.rstrip("/")).resolve()
        try:
            base.relative_to(root)
        except ValueError:
            continue
        if not base.is_dir():
            continue
        for path in base.rglob("*"):
            if not path.is_file():
                continue
            try:
                rel = path.relative_to(root).as_posix()
            except ValueError:
                continue
            if rel in seen or not _should_index_path(rel):
                continue
            try:
                if path.stat().st_size > max_bytes:
                    continue
            except OSError:
                continue
            seen.add(rel)

    return sorted(seen)
