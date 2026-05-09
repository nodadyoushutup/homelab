from __future__ import annotations

import argparse
import hmac
import json
import logging
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any
from typing import Sequence

from mcp.server.fastmcp import FastMCP
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.types import ASGIApp
from starlette.types import Receive
from starlette.types import Scope
from starlette.types import Send
import uvicorn

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

log = logging.getLogger(__name__)

MCP_API_KEY_ENV = "MCP_RAG_API_KEY"
ENGINE_BASE_ENV = "RAG_ENGINE_BASE_URL"
ENGINE_KEY_ENV = "RAG_ENGINE_API_KEY"
DEFAULT_MCP_API_KEY_HEADER = "x-api-key"
STREAMABLE_HTTP_PATH = "/mcp"
ENGINE_QUERY_PATH = "/v1/query"
ENGINE_MEMORY_SAVE_PATH = "/v1/memory/save"
ENGINE_MEMORY_RECALL_PATH = "/v1/memory/recall"
ENGINE_MEMORY_FORGET_PATH = "/v1/memory/forget"
DEFAULT_REQUEST_TIMEOUT_SEC = 120.0

VALID_MEMORY_KINDS = ("episodic", "declarative")
VALID_MEMORY_RECALL_KINDS = ("auto", "episodic", "declarative")
VALID_MEMORY_SOURCES = ("failure_resolution", "user_assertion")
VALID_MEMORY_SCOPES = ("workflow", "policy", "schedule", "env", "other")
MEMORY_KIND_SOURCE_MATRIX = {
    "episodic": "failure_resolution",
    "declarative": "user_assertion",
}
MEMORY_RECALL_K_MAX_CLIENT_CAP = 3


def _normalize_path(path: str) -> str:
    value = (path or "").strip() or "/"
    if not value.startswith("/"):
        value = f"/{value}"
    if len(value) > 1:
        value = value.rstrip("/")
    return value


def _is_streamable_http_request(path: str, streamable_http_path: str) -> bool:
    normalized_path = _normalize_path(path)
    normalized_streamable_path = _normalize_path(streamable_http_path)
    if normalized_path == normalized_streamable_path:
        return True
    return normalized_path.startswith(f"{normalized_streamable_path}/")


def _mcp_api_key_value() -> str:
    return (os.getenv(MCP_API_KEY_ENV) or "").strip()


def _api_key_header_name() -> str:
    return DEFAULT_MCP_API_KEY_HEADER


def _scope_header_value(scope: Scope, header_name: str) -> str | None:
    target = header_name.lower().encode("latin-1")
    for raw_key, raw_value in scope.get("headers", []):
        if raw_key.lower() == target:
            return raw_value.decode("latin-1")
    return None


class MCPAPIKeyAuthMiddleware:
    def __init__(
        self,
        app: ASGIApp,
        *,
        header_name: str,
        api_key: str,
        streamable_http_path: str,
    ) -> None:
        self.app = app
        self.header_name = header_name
        self.api_key = api_key
        self.streamable_http_path = streamable_http_path

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope.get("type") != "http":
            await self.app(scope, receive, send)
            return

        path = scope.get("path", "/")
        if not _is_streamable_http_request(path, self.streamable_http_path):
            await self.app(scope, receive, send)
            return

        provided = _scope_header_value(scope, self.header_name) or ""
        if hmac.compare_digest(provided, self.api_key):
            await self.app(scope, receive, send)
            return

        body = b'{"error":"Unauthorized","message":"Invalid API key."}'
        await send(
            {
                "type": "http.response.start",
                "status": 401,
                "headers": [
                    (b"content-type", b"application/json"),
                    (b"content-length", str(len(body)).encode("ascii")),
                ],
            }
        )
        await send({"type": "http.response.body", "body": body})


def _engine_base_url() -> str:
    raw = (os.getenv(ENGINE_BASE_ENV) or "").strip().rstrip("/")
    if not raw:
        raise RuntimeError(
            f"Missing {ENGINE_BASE_ENV}. Example: http://rag-engine:8080 (Compose) or "
            "http://127.0.0.1:9015 (host to published rag-engine port)."
        )
    return raw


def _engine_api_key() -> str:
    return (os.getenv(ENGINE_KEY_ENV) or "").strip()


def _post_engine(*, path: str, body: dict[str, Any]) -> dict[str, Any]:
    base = _engine_base_url()
    url = f"{base}{path}"
    payload = json.dumps(body).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    key = _engine_api_key()
    if key:
        headers["x-api-key"] = key
    req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
    timeout = float(os.getenv("MCP_RAG_ENGINE_TIMEOUT_SEC") or DEFAULT_REQUEST_TIMEOUT_SEC)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw_text = resp.read().decode("utf-8", errors="replace")
            data = json.loads(raw_text)
    except urllib.error.HTTPError as exc:
        try:
            detail = exc.read().decode("utf-8", errors="replace")
        except Exception:
            detail = str(exc)
        if exc.code == 401:
            return {
                "error": "engine_unauthorized",
                "message": "RAG engine rejected the API key. Align RAG_ENGINE_API_KEY with the engine.",
                "detail": detail[:2000],
            }
        if exc.code == 400:
            return {
                "error": "engine_bad_request",
                "message": f"RAG engine returned 400 from {path} (invalid input).",
                "detail": detail[:2000],
            }
        return {
            "error": "engine_http_error",
            "message": f"RAG engine HTTP {exc.code} from {path}",
            "detail": detail[:2000],
        }
    except urllib.error.URLError as exc:
        return {
            "error": "engine_unreachable",
            "message": f"Could not reach RAG engine at {base}: {exc}",
        }
    except json.JSONDecodeError as exc:
        return {"error": "engine_invalid_json", "message": str(exc)}
    if isinstance(data, dict) and data.get("error"):
        return {
            "error": "engine_error",
            "message": str(data.get("error")),
            "results": data.get("results"),
        }
    return data if isinstance(data, dict) else {"raw": data}


def _normalize_optional_str(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def _normalize_cited_paths_for_wire(value: Any) -> list[str] | None:
    if value is None:
        return None
    if isinstance(value, str):
        items = value.split(",")
    elif isinstance(value, (list, tuple)):
        items = [str(v) for v in value if v is not None and not isinstance(v, bool)]
    else:
        return None
    cleaned: list[str] = []
    seen: set[str] = set()
    for raw in items:
        norm = raw.strip()
        if not norm or norm in seen:
            continue
        cleaned.append(norm)
        seen.add(norm)
    return cleaned


def create_mcp() -> FastMCP:
    streamable_http_path = _normalize_path(STREAMABLE_HTTP_PATH)
    api_key_header = _api_key_header_name()
    mcp = FastMCP(
        name="mcp-rag",
        instructions=(
            "Thin MCP for the repository RAG index AND long-term agent memory. Calls the "
            "rag-engine HTTP API so all reads/writes use the same embedding model as ingest "
            "(not raw Chroma).\n\n"
            "Tools:\n"
            "- rag_search: semantic search over INDEXED REPO CODE/DOCS. Use for orientation "
            "(where code or docs likely live, workflow context) before narrowing with filesystem "
            "or ast-grep. Concrete anchors win: path fragments, class/method names, exact error "
            "text, Odoo technical model names (e.g. purchase.order). `where` uses Chroma metadata "
            "keys documented in docs/workflows/development/rag-agent-mcp-integration-roadmap.md "
            "(path, xml_model, language, chunk_strategy). The metadata key `model` is the "
            "EMBEDDING model id — do not confuse with Odoo `ir.model`; use `xml_model` to filter "
            "Odoo XML records.\n"
            "- memory_recall: retrieve previously-saved long-term memories (failure→solution "
            "pairs and user-asserted facts). Use BEFORE deep failure diagnosis or at the start "
            "of a topical task. NOT a substitute for rag_search; memories are HINTS to verify, "
            "not authoritative.\n"
            "- memory_save: persist a memory through ONE of two strict gates — Gate 1 "
            "(source=\"failure_resolution\") only after a failure was observed and resolved on "
            "the current task; Gate 2 (source=\"user_assertion\") only when the user explicitly "
            "said \"remember\" / \"save this\" / \"note for later\". Do NOT use to cache "
            "rag_search answers, summarize conversation, or store secrets.\n"
            "- memory_forget: delete by id; only when the user asks to forget. Recall first to "
            "confirm.\n\n"
            "See docs/workflows/development/rag-agent-mcp-integration-roadmap.md (memory rows) "
            "and the MCP tool descriptions above for the write gates."
        ),
        host=os.getenv("HOST", "0.0.0.0"),
        port=int(os.getenv("PORT", "8080")),
        log_level=os.getenv("MCP_RAG_LOG_LEVEL", os.getenv("LOG_LEVEL", "INFO")).upper(),
        streamable_http_path=streamable_http_path,
        stateless_http=True,
    )

    @mcp.tool()
    def rag_search(
        query: str,
        n_results: int = 20,
        where: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Semantic search over the indexed repository via rag-engine (Gemini embeddings + Chroma).

        Use specific anchors (paths, symbols, Odoo model names like purchase.order, error strings).
        Use `where` only when narrowing by known metadata (see rag-agent-mcp-integration-roadmap).
        Issue multiple tool calls for unrelated sub-questions (workflow vs code location).
        """
        q = (query or "").strip()
        if not q:
            return {"error": "query_empty", "message": "query must be non-empty"}
        try:
            n = int(n_results)
        except (TypeError, ValueError):
            return {"error": "n_results_invalid", "message": "n_results must be an integer"}
        if n < 1:
            return {"error": "n_results_invalid", "message": "n_results must be >= 1"}
        body: dict[str, Any] = {"query": q, "n_results": n}
        if where is not None:
            body["where"] = where
        return _post_engine(path=ENGINE_QUERY_PATH, body=body)

    @mcp.tool()
    def memory_recall(
        query: str,
        k: int = 3,
        kind: str = "auto",
        include_expired: bool = False,
        where: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Retrieve up to `k` long-term memories semantically similar to `query`.

        Use BEFORE deep failure diagnosis (kind="episodic" with the failure signature)
        or at the start of a task with a clear topic (kind="declarative" or "auto").
        Do NOT use as a substitute for rag_search — this only returns previously-saved
        memories, not repository code or docs. Returned hits are HINTS to verify, not
        authoritative; check `cited_paths` and `stale_since_commit` before acting.

        Args:
            query: free-text question or failure signature; required.
            k: requested hits; capped to 3 client-side and again server-side.
            kind: "auto" (blend both, default), "episodic", or "declarative".
            include_expired: if true, also returns memories whose expires_at is past.
            where: optional Chroma metadata filter (e.g. {"failure_class": "mcp_call"}).
        """
        q = (query or "").strip()
        if not q:
            return {"error": "query_empty", "message": "query must be non-empty"}
        if kind not in VALID_MEMORY_RECALL_KINDS:
            return {
                "error": "kind_invalid",
                "message": f"kind must be one of {VALID_MEMORY_RECALL_KINDS}",
            }
        try:
            requested_k = int(k)
        except (TypeError, ValueError):
            return {"error": "k_invalid", "message": "k must be an integer"}
        if requested_k < 1:
            return {"error": "k_invalid", "message": "k must be >= 1"}
        capped_k = min(requested_k, MEMORY_RECALL_K_MAX_CLIENT_CAP)
        body: dict[str, Any] = {
            "query": q,
            "k": capped_k,
            "kind": kind,
            "include_expired": bool(include_expired),
        }
        if where is not None:
            if not isinstance(where, dict):
                return {"error": "where_invalid", "message": "where must be a JSON object"}
            body["where"] = where
        return _post_engine(path=ENGINE_MEMORY_RECALL_PATH, body=body)

    @mcp.tool()
    def memory_save(
        kind: str,
        source: str,
        title: str,
        body: str,
        cited_paths: list[str] | None = None,
        failure_class: str | None = None,
        failure_signature: str | None = None,
        topic: str | None = None,
        scope: str | None = None,
        expires_at: str | None = None,
        author: str | None = None,
        commit: str | None = None,
    ) -> dict[str, Any]:
        """Persist a long-term memory through ONE of two strict promotion gates.

        GATE 1 — failure-resolution (episodic):
            kind="episodic", source="failure_resolution".
            ONLY call after a failure was observed AND resolved on the CURRENT task.
            Required: non-empty failure_class, AND (at least one cited_paths entry
            OR a non-empty failure_signature).

        GATE 2 — user-assertion (declarative):
            kind="declarative", source="user_assertion".
            ONLY call when the user explicitly said "remember", "save this", "note
            for later", or equivalent. Honor `expires_at` if the user named a date
            or window.

        Do NOT call to cache rag_search answers, summarize conversation, or record
        successful tool calls. Do NOT store secrets, tokens, or PII. Dedup-on-write
        is automatic at the engine; near-duplicates merge instead of inserting.

        Returns: {id, kind, embedded, dedup: {action: created|merged, matched_id?}}.
        """
        if kind not in VALID_MEMORY_KINDS:
            return {"error": "kind_invalid", "message": f"kind must be one of {VALID_MEMORY_KINDS}"}
        if source not in VALID_MEMORY_SOURCES:
            return {
                "error": "source_invalid",
                "message": f"source must be one of {VALID_MEMORY_SOURCES}",
            }
        expected_source = MEMORY_KIND_SOURCE_MATRIX[kind]
        if source != expected_source:
            return {
                "error": "kind_source_mismatch",
                "message": f"kind={kind!r} requires source={expected_source!r}",
            }
        title_clean = (title or "").strip()
        body_clean = (body or "").strip()
        if not title_clean:
            return {"error": "title_empty", "message": "title must be non-empty"}
        if not body_clean:
            return {"error": "body_empty", "message": "body must be non-empty"}
        scope_clean = _normalize_optional_str(scope)
        if scope_clean and scope_clean not in VALID_MEMORY_SCOPES:
            return {
                "error": "scope_invalid",
                "message": f"scope must be one of {VALID_MEMORY_SCOPES} when set",
            }
        cited_list = _normalize_cited_paths_for_wire(cited_paths)
        if cited_paths is not None and cited_list is None:
            return {
                "error": "cited_paths_invalid",
                "message": "cited_paths must be a list of strings or a comma-separated string",
            }
        failure_class_clean = _normalize_optional_str(failure_class)
        failure_signature_clean = _normalize_optional_str(failure_signature)
        if kind == "episodic":
            if not failure_class_clean:
                return {
                    "error": "failure_class_required",
                    "message": "episodic memories require failure_class (gate 1)",
                }
            if not (cited_list or failure_signature_clean):
                return {
                    "error": "evidence_required",
                    "message": "episodic memories require at least one cited_paths entry or a non-empty failure_signature (gate 1)",
                }
        wire: dict[str, Any] = {
            "kind": kind,
            "source": source,
            "title": title_clean,
            "body": body_clean,
        }
        if cited_list is not None:
            wire["cited_paths"] = cited_list
        if failure_class_clean:
            wire["failure_class"] = failure_class_clean
        if failure_signature_clean:
            wire["failure_signature"] = failure_signature_clean
        topic_clean = _normalize_optional_str(topic)
        if topic_clean:
            wire["topic"] = topic_clean
        if scope_clean:
            wire["scope"] = scope_clean
        expires_at_clean = _normalize_optional_str(expires_at)
        if expires_at_clean:
            wire["expires_at"] = expires_at_clean
        author_clean = _normalize_optional_str(author)
        if author_clean:
            wire["author"] = author_clean
        commit_clean = _normalize_optional_str(commit)
        if commit_clean:
            wire["commit"] = commit_clean
        return _post_engine(path=ENGINE_MEMORY_SAVE_PATH, body=wire)

    @mcp.tool()
    def memory_forget(
        id: str | None = None,
        ids: list[str] | None = None,
        dry_run: bool = False,
    ) -> dict[str, Any]:
        """Delete one or more memories by id.

        Call ONLY when the user asks to forget a specific memory. Run memory_recall
        first to confirm which row(s) will be deleted; pass the returned ids here.

        Args:
            id: single memory id (mutually exclusive with `ids`).
            ids: list of memory ids.
            dry_run: if true, returns counts without deleting.
        """
        single = (id or "").strip() if isinstance(id, str) else ""
        listed: list[str] = []
        if ids:
            if not isinstance(ids, (list, tuple)):
                return {"error": "ids_invalid", "message": "ids must be a list of strings"}
            for raw in ids:
                if not isinstance(raw, str):
                    return {"error": "ids_invalid", "message": "ids must be a list of strings"}
                trimmed = raw.strip()
                if trimmed:
                    listed.append(trimmed)
        if single and listed:
            return {
                "error": "id_and_ids_exclusive",
                "message": "pass either `id` or `ids`, not both",
            }
        if not single and not listed:
            return {
                "error": "missing_target",
                "message": "either `id` or `ids` is required",
            }
        wire: dict[str, Any] = {"dry_run": bool(dry_run)}
        if single:
            wire["id"] = single
        else:
            wire["ids"] = listed
        return _post_engine(path=ENGINE_MEMORY_FORGET_PATH, body=wire)

    @mcp.custom_route("/healthz", methods=["GET"])
    async def healthz(_: Request) -> JSONResponse:
        return JSONResponse(
            {
                "status": "ok",
                "check": "liveness",
                "server": "mcp-rag",
                "streamable_http_path": streamable_http_path,
                "api_key_header": api_key_header,
                "api_key_auth_enabled": bool(_mcp_api_key_value()),
                "engine_base_configured": bool((os.getenv(ENGINE_BASE_ENV) or "").strip()),
            }
        )

    return mcp


def _healthcheck_url() -> str:
    host = (os.getenv("MCP_RAG_HEALTHCHECK_HOST") or "127.0.0.1").strip() or "127.0.0.1"
    port = int(os.getenv("PORT", "8080"))
    path = (os.getenv("MCP_RAG_HEALTHCHECK_PATH") or "/healthz").strip() or "/healthz"
    if not path.startswith("/"):
        path = f"/{path}"
    return f"http://{host}:{port}{path}"


def run_healthcheck(
    *,
    url: str | None = None,
    timeout_seconds: float | None = None,
) -> int:
    target_url = url or _healthcheck_url()
    timeout = timeout_seconds
    if timeout is None:
        timeout = float(os.getenv("MCP_RAG_HEALTHCHECK_TIMEOUT", "5"))

    try:
        with urllib.request.urlopen(target_url, timeout=timeout) as response:
            status = getattr(response, "status", 200)
            if 200 <= status < 400:
                return 0
            print(
                f"Healthcheck failed for {target_url}: HTTP status {status}",
                file=sys.stderr,
            )
            return 1
    except (urllib.error.URLError, TimeoutError) as exc:
        print(f"Healthcheck failed for {target_url}: {exc}", file=sys.stderr)
        return 1


def run_server() -> None:
    mcp = create_mcp()
    app: Starlette = mcp.streamable_http_app()
    mcp_key = _mcp_api_key_value()
    if mcp_key:
        app.add_middleware(
            MCPAPIKeyAuthMiddleware,
            header_name=_api_key_header_name(),
            api_key=mcp_key,
            streamable_http_path=mcp.settings.streamable_http_path,
        )
    else:
        log.warning(
            "%s is empty; MCP /mcp endpoint accepts unauthenticated requests",
            MCP_API_KEY_ENV,
        )

    config = uvicorn.Config(
        app,
        host=mcp.settings.host,
        port=mcp.settings.port,
        log_level=mcp.settings.log_level.lower(),
    )
    server = uvicorn.Server(config)
    server.run()


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="mcp-rag")
    subparsers = parser.add_subparsers(dest="command")

    subparsers.add_parser("serve", help="Run the RAG MCP server.")

    healthcheck_parser = subparsers.add_parser(
        "healthcheck", help="Check if the local MCP health endpoint responds."
    )
    healthcheck_parser.add_argument(
        "--url",
        help="Explicit healthcheck URL. Defaults to http://127.0.0.1:${PORT}/healthz.",
    )
    healthcheck_parser.add_argument(
        "--timeout",
        type=float,
        help="Request timeout in seconds. Defaults to MCP_RAG_HEALTHCHECK_TIMEOUT or 5.",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    logging.basicConfig(
        level=os.getenv("MCP_RAG_LOG_LEVEL", os.getenv("LOG_LEVEL", "INFO")).upper(),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.command in {None, "serve"}:
        run_server()
        return 0

    if args.command == "healthcheck":
        return run_healthcheck(url=args.url, timeout_seconds=args.timeout)

    parser.error(f"Unsupported command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
