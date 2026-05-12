from __future__ import annotations

import hmac
import logging
import os

from starlette.applications import Starlette
from starlette.concurrency import run_in_threadpool
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Route

from embeddings import build_embedding_client, embedding_model
from memory import (
    forget_memory,
    list_stale_memories,
    recall_memory,
    save_memory,
    sweep_expired,
)
from ingest.backfill import options_from_api_body, run_backfill
from ingest.pipeline import chroma_repo_collection, prune_orphan_paths, run_embed_job
from retrieve.query import run_query

log = logging.getLogger(__name__)


def _configure_logging() -> None:
    level = (os.getenv("RAG_LOG_LEVEL") or "INFO").strip().upper()
    logging.basicConfig(
        level=getattr(logging, level, logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )


_configure_logging()

if not (os.getenv("RAG_ENGINE_API_KEY") or "").strip():
    log.warning("RAG_ENGINE_API_KEY is empty; POST /v1/embed-commit accepts unauthenticated requests")

_chroma_host = (os.getenv("RAG_CHROMA_HOST") or "chromadb").strip()
_chroma_port = (os.getenv("RAG_CHROMA_PORT") or "8000").strip()
log.info("Chroma HTTP target %s:%s (RAG_CHROMA_HOST / RAG_CHROMA_PORT)", _chroma_host, _chroma_port)
if _chroma_host == "chromadb":
    log.warning(
        "RAG_CHROMA_HOST=chromadb only resolves on the Swarm overlay; for Docker Compose rag-engine-dev "
        "(or any client not on that network), set RAG_CHROMA_HOST to the Swarm node's LAN IP and "
        "RAG_CHROMA_PORT to the published Chroma HTTP port."
    )


async def healthz(_: Request) -> JSONResponse:
    return JSONResponse({"status": "ok"})


async def rag_query(request: Request) -> JSONResponse:
    expected = (os.getenv("RAG_ENGINE_API_KEY") or "").strip()
    if expected:
        got = (request.headers.get("x-api-key") or "").strip()
        if not hmac.compare_digest(got, expected):
            return JSONResponse({"error": "Unauthorized"}, status_code=401)
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON"}, status_code=400)
    q = (body.get("query") or "").strip()
    if not q:
        return JSONResponse({"error": "query is required"}, status_code=400)
    try:
        n_results = int(body.get("n_results", 20))
    except (TypeError, ValueError):
        return JSONResponse({"error": "n_results must be an integer"}, status_code=400)
    where = body.get("where")
    if where is not None and not isinstance(where, dict):
        return JSONResponse({"error": "where must be a JSON object"}, status_code=400)
    model = embedding_model()

    def _sync():
        coll = chroma_repo_collection()
        client = build_embedding_client()
        return run_query(
            coll,
            client,
            query_text=q,
            n_results=n_results,
            embedding_model=model,
            where=where,
        )

    try:
        result = await run_in_threadpool(_sync)
    except Exception as exc:
        log.exception("query failed")
        return JSONResponse({"error": str(exc)}, status_code=500)
    if result.get("error"):
        return JSONResponse(result, status_code=400)
    return JSONResponse(result)


async def embed_commit(request: Request) -> JSONResponse:
    expected = (os.getenv("RAG_ENGINE_API_KEY") or "").strip()
    if expected:
        got = (request.headers.get("x-api-key") or "").strip()
        if not hmac.compare_digest(got, expected):
            return JSONResponse({"error": "Unauthorized"}, status_code=401)
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON"}, status_code=400)
    commit = (body.get("commit") or "").strip()
    paths = body.get("paths") or []
    removed_paths = body.get("removed_paths") or []
    if not commit:
        return JSONResponse({"error": "commit is required"}, status_code=400)
    if not isinstance(paths, list) or not isinstance(removed_paths, list):
        return JSONResponse({"error": "paths and removed_paths must be arrays"}, status_code=400)
    paths_s = [str(p) for p in paths]
    removed_s = [str(p) for p in removed_paths]
    try:
        result = run_embed_job(commit, paths_s, removed_s)
        return JSONResponse(result)
    except Exception as exc:
        log.exception("embed-commit failed")
        return JSONResponse({"error": str(exc)}, status_code=500)


async def backfill_route(request: Request) -> JSONResponse:
    """Run workspace backfill inside the service (same as ``python -m ingest.backfill``).

    Long-running: ensure reverse-proxy/read timeouts are high enough. JSON body mirrors CLI flags;
    use ``"confirm": true`` instead of ``--yes`` for mutating runs.
    """
    expected = (os.getenv("RAG_ENGINE_API_KEY") or "").strip()
    if expected:
        got = (request.headers.get("x-api-key") or "").strip()
        if not hmac.compare_digest(got, expected):
            return JSONResponse({"error": "Unauthorized"}, status_code=401)
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON"}, status_code=400)
    if not isinstance(body, dict):
        return JSONResponse({"error": "JSON body must be an object"}, status_code=400)

    opts, parse_err = options_from_api_body(body)
    if parse_err:
        return JSONResponse({"error": parse_err}, status_code=400)
    assert opts is not None

    def _run():
        return run_backfill(opts, interactive=False)

    try:
        code, payload = await run_in_threadpool(_run)
    except Exception as exc:
        log.exception("backfill failed")
        return JSONResponse({"error": str(exc)}, status_code=500)

    out = {"exit_code": code, **payload}
    if code == 2:
        return JSONResponse(out, status_code=400)
    return JSONResponse(out, status_code=200)


async def reconcile_orphans(request: Request) -> JSONResponse:
    expected = (os.getenv("RAG_ENGINE_API_KEY") or "").strip()
    if expected:
        got = (request.headers.get("x-api-key") or "").strip()
        if not hmac.compare_digest(got, expected):
            return JSONResponse({"error": "Unauthorized"}, status_code=401)
    try:
        body = await request.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        return JSONResponse({"error": "JSON body must be an object"}, status_code=400)
    dry_run = bool(body.get("dry_run", False))

    def _run():
        coll = chroma_repo_collection()
        return prune_orphan_paths(coll, dry_run=dry_run)

    try:
        result = await run_in_threadpool(_run)
        return JSONResponse(result)
    except Exception as exc:
        log.exception("reconcile-orphans failed")
        return JSONResponse({"error": str(exc)}, status_code=500)


def _check_api_key(request: Request) -> JSONResponse | None:
    expected = (os.getenv("RAG_ENGINE_API_KEY") or "").strip()
    if not expected:
        return None
    got = (request.headers.get("x-api-key") or "").strip()
    if not hmac.compare_digest(got, expected):
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    return None


async def _read_json_object(request: Request) -> tuple[dict | None, JSONResponse | None]:
    try:
        raw = await request.json()
    except Exception:
        return None, JSONResponse({"error": "Invalid JSON"}, status_code=400)
    if not isinstance(raw, dict):
        return None, JSONResponse({"error": "JSON body must be an object"}, status_code=400)
    return raw, None


async def memory_save_route(request: Request) -> JSONResponse:
    if (resp := _check_api_key(request)) is not None:
        return resp
    body, err = await _read_json_object(request)
    if err is not None:
        return err
    assert body is not None
    cited_paths_raw = body.get("cited_paths")
    if cited_paths_raw is not None and not isinstance(cited_paths_raw, (list, tuple, str)):
        return JSONResponse(
            {"error": "cited_paths must be a list of strings or a comma-separated string"},
            status_code=400,
        )

    def _sync():
        client = build_embedding_client()
        return save_memory(
            genai_client=client,
            kind=str(body.get("kind") or ""),
            source=str(body.get("source") or ""),
            title=str(body.get("title") or ""),
            body=str(body.get("body") or ""),
            cited_paths=body.get("cited_paths"),
            failure_class=str(body.get("failure_class") or ""),
            failure_signature=str(body.get("failure_signature") or ""),
            topic=str(body.get("topic") or ""),
            scope=str(body.get("scope") or ""),
            expires_at=str(body.get("expires_at") or ""),
            author=str(body.get("author") or ""),
            commit=str(body.get("commit") or ""),
        )

    try:
        result = await run_in_threadpool(_sync)
    except Exception as exc:
        log.exception("memory save failed")
        return JSONResponse({"error": str(exc)}, status_code=500)
    if isinstance(result, dict) and result.get("error"):
        return JSONResponse(result, status_code=400)
    return JSONResponse(result)


async def memory_recall_route(request: Request) -> JSONResponse:
    if (resp := _check_api_key(request)) is not None:
        return resp
    body, err = await _read_json_object(request)
    if err is not None:
        return err
    assert body is not None
    where = body.get("where")
    if where is not None and not isinstance(where, dict):
        return JSONResponse({"error": "where must be a JSON object"}, status_code=400)
    try:
        k = int(body.get("k", 3))
    except (TypeError, ValueError):
        return JSONResponse({"error": "k must be an integer"}, status_code=400)
    kind = str(body.get("kind") or "auto")
    include_expired = bool(body.get("include_expired", False))
    query_text = str(body.get("query") or "")

    def _sync():
        client = build_embedding_client()
        return recall_memory(
            genai_client=client,
            query_text=query_text,
            k=k,
            kind=kind,
            where=where,
            include_expired=include_expired,
        )

    try:
        result = await run_in_threadpool(_sync)
    except Exception as exc:
        log.exception("memory recall failed")
        return JSONResponse({"error": str(exc)}, status_code=500)
    if isinstance(result, dict) and result.get("error"):
        return JSONResponse(result, status_code=400)
    return JSONResponse(result)


async def memory_forget_route(request: Request) -> JSONResponse:
    if (resp := _check_api_key(request)) is not None:
        return resp
    body, err = await _read_json_object(request)
    if err is not None:
        return err
    assert body is not None
    raw_id = body.get("id")
    raw_ids = body.get("ids")
    where = body.get("where")
    if where is not None and not isinstance(where, dict):
        return JSONResponse({"error": "where must be a JSON object"}, status_code=400)
    ids: list[str] = []
    if isinstance(raw_id, str) and raw_id.strip():
        ids = [raw_id.strip()]
    elif isinstance(raw_ids, list):
        ids = [str(i).strip() for i in raw_ids if isinstance(i, str) and i.strip()]
    elif raw_id is not None or raw_ids is not None:
        return JSONResponse(
            {"error": "id must be a string and ids must be a list of strings"}, status_code=400
        )
    dry_run = bool(body.get("dry_run", False))

    def _sync():
        return forget_memory(ids=ids, where=where, dry_run=dry_run)

    try:
        result = await run_in_threadpool(_sync)
    except Exception as exc:
        log.exception("memory forget failed")
        return JSONResponse({"error": str(exc)}, status_code=500)
    if isinstance(result, dict) and result.get("error"):
        return JSONResponse(result, status_code=400)
    return JSONResponse(result)


async def memory_sweep_route(request: Request) -> JSONResponse:
    if (resp := _check_api_key(request)) is not None:
        return resp
    try:
        raw = await request.json()
    except Exception:
        raw = {}
    body = raw if isinstance(raw, dict) else {}
    dry_run = bool(body.get("dry_run", False))
    kinds_raw = body.get("kinds")
    kinds: list[str] | None
    if kinds_raw is None:
        kinds = None
    elif isinstance(kinds_raw, list):
        kinds = [str(k).strip() for k in kinds_raw if isinstance(k, str) and k.strip()]
    else:
        return JSONResponse({"error": "kinds must be a list of strings"}, status_code=400)

    def _sync():
        return sweep_expired(dry_run=dry_run, kinds=kinds)

    try:
        result = await run_in_threadpool(_sync)
    except Exception as exc:
        log.exception("memory sweep failed")
        return JSONResponse({"error": str(exc)}, status_code=500)
    if isinstance(result, dict) and result.get("error"):
        return JSONResponse(result, status_code=400)
    return JSONResponse(result)


async def memory_list_stale_route(request: Request) -> JSONResponse:
    if (resp := _check_api_key(request)) is not None:
        return resp
    try:
        raw = await request.json()
    except Exception:
        raw = {}
    body = raw if isinstance(raw, dict) else {}
    kinds_raw = body.get("kinds")
    kinds: list[str] | None
    if kinds_raw is None:
        kinds = None
    elif isinstance(kinds_raw, list):
        kinds = [str(k).strip() for k in kinds_raw if isinstance(k, str) and k.strip()]
    else:
        return JSONResponse({"error": "kinds must be a list of strings"}, status_code=400)
    limit_raw = body.get("limit")
    limit: int | None
    if limit_raw is None:
        limit = None
    else:
        try:
            limit = int(limit_raw)
        except (TypeError, ValueError):
            return JSONResponse({"error": "limit must be an integer"}, status_code=400)

    def _sync():
        return list_stale_memories(kinds=kinds, limit=limit)

    try:
        result = await run_in_threadpool(_sync)
    except Exception as exc:
        log.exception("memory list_stale failed")
        return JSONResponse({"error": str(exc)}, status_code=500)
    if isinstance(result, dict) and result.get("error"):
        return JSONResponse(result, status_code=400)
    return JSONResponse(result)


app = Starlette(
    routes=[
        Route("/healthz", endpoint=healthz, methods=["GET"]),
        Route("/v1/query", endpoint=rag_query, methods=["POST"]),
        Route("/v1/embed-commit", endpoint=embed_commit, methods=["POST"]),
        Route("/v1/backfill", endpoint=backfill_route, methods=["POST"]),
        Route("/v1/reconcile-orphans", endpoint=reconcile_orphans, methods=["POST"]),
        Route("/v1/memory/save", endpoint=memory_save_route, methods=["POST"]),
        Route("/v1/memory/recall", endpoint=memory_recall_route, methods=["POST"]),
        Route("/v1/memory/forget", endpoint=memory_forget_route, methods=["POST"]),
        Route("/v1/memory/sweep", endpoint=memory_sweep_route, methods=["POST"]),
        Route("/v1/memory/list_stale", endpoint=memory_list_stale_route, methods=["POST"]),
    ],
)
