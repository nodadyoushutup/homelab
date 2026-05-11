"""Streamable-HTTP MCP server that merges filesystem, git, and ast-grep tools.

Default upstream transport is **stdio**: this process spawns the official Node/git
servers and the ast-grep Python server as subprocesses and holds three long-lived
ClientSession instances (each entered as an async context manager). Tool calls route
to the session that owns each tool name.

Optional ``MCP_CODE_UPSTREAM_TRANSPORT=http`` connects to loopback Streamable HTTP URLs
(legacy ``mcp-proxy``), which is useful for experiments but known-brittle with some
proxy versions.

The outer listener **binds immediately**; upstream warmup runs in a background task so
Compose healthchecks see port 8100 without waiting for merged upstreams.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
from collections.abc import AsyncIterator
from contextlib import AsyncExitStack, asynccontextmanager
from pathlib import Path
from typing import Any

import httpx
import mcp.types as types
import uvicorn
from mcp.client.session import ClientSession
from mcp.client.stdio import StdioServerParameters, stdio_client
from mcp.client.streamable_http import streamable_http_client
from mcp.server import Server
from mcp.server.fastmcp.server import StreamableHTTPASGIApp
from mcp.server.streamable_http_manager import StreamableHTTPSessionManager
from starlette.applications import Starlette
from starlette.routing import Route

logger = logging.getLogger(__name__)

AST_GREP_PROJECT_TOOLS = frozenset({"find_code", "find_code_by_rule"})

_INVENTORY_PATH = Path(__file__).resolve().parent / "upstream_tools_inventory.json"


def _load_tool_inventory() -> dict[str, Any] | None:
    try:
        raw = _INVENTORY_PATH.read_text(encoding="utf-8")
    except OSError:
        logger.warning("mcp-code: missing tool inventory at %s", _INVENTORY_PATH)
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        logger.warning("mcp-code: invalid JSON in %s: %s", _INVENTORY_PATH, exc)
        return None


def _instructions_from_inventory(inv: dict[str, Any]) -> str:
    counts = inv.get("counts") or {}
    total = int(counts.get("total", 31))
    names: list[str] = list(inv.get("all_tool_names_sorted") or [])
    name_block = ", ".join(names) if names else "(see tools/list)"
    return (
        "mcp-code is one HTTP MCP that merges three upstream MCP servers (filesystem, git, "
        "ast-grep) into a single tools/list and routes each call_tool to the owning session. "
        f"There are {total} tools with unique names; use tools/list for argument schemas. "
        "Routing is automatic by tool name. "
        "Ast-grep tools find_code and find_code_by_rule accept project_folder; it defaults to "
        "the workspace root when omitted. "
        f"Tool names ({len(names)}): {name_block}."
    )


def _child_process_env() -> dict[str, str]:
    """Full environment for Node/Python MCP children (npm global and venv paths)."""
    return {k: v for k, v in os.environ.items() if isinstance(v, str)}


def _stdio_upstream_params(workspace_root: str) -> tuple[StdioServerParameters, ...]:
    ws = os.path.abspath(workspace_root)
    inherited = _child_process_env()
    fs_bin = os.environ.get(
        "MCP_CODE_FILESYSTEM_SERVER_BIN",
        "/opt/npm-global/bin/mcp-server-filesystem",
    ).strip()
    git_bin = os.environ.get(
        "MCP_CODE_GIT_SERVER_BIN",
        "/opt/mcp-code-venv/bin/mcp-server-git",
    ).strip()
    py = os.environ.get(
        "MCP_CODE_AST_GREP_PYTHON",
        "/opt/mcp-code-venv/bin/python",
    ).strip()
    ag_script = os.environ.get(
        "MCP_CODE_AST_GREP_SERVER_PATH",
        "/opt/mcp-code/ast-grep-server.py",
    ).strip()
    fs = StdioServerParameters(command=fs_bin, args=[ws], env=inherited)
    git = StdioServerParameters(command=git_bin, args=["--repository", ws], env=inherited)
    ag = StdioServerParameters(
        command=py,
        args=[ag_script, "--transport", "stdio"],
        env=inherited,
    )
    return (fs, git, ag)


def _default_ast_grep_project_folder(
    tool_name: str, arguments: dict[str, Any], workspace_root: str
) -> dict[str, Any]:
    if tool_name not in AST_GREP_PROJECT_TOOLS:
        return arguments
    merged = dict(arguments)
    if (merged.get("project_folder") or "").strip():
        return merged
    merged["project_folder"] = workspace_root
    return merged


class Subsessions:
    __slots__ = ("filesystem", "git", "ast_grep", "tool_owner", "merged_tools")

    def __init__(
        self,
        filesystem: ClientSession,
        git: ClientSession,
        ast_grep: ClientSession,
        tool_owner: dict[str, ClientSession],
        merged_tools: list[types.Tool],
    ) -> None:
        self.filesystem = filesystem
        self.git = git
        self.ast_grep = ast_grep
        self.tool_owner = tool_owner
        self.merged_tools = merged_tools


async def _list_tools_all(session: ClientSession) -> list[types.Tool]:
    out: list[types.Tool] = []
    cursor: str | None = None
    while True:
        params = types.PaginatedRequestParams(cursor=cursor) if cursor else None
        result = await session.list_tools(params=params)
        out.extend(result.tools)
        cursor = result.nextCursor
        if not cursor:
            break
    return out


def _local_proxy_streamable_urls() -> tuple[str, str, str]:
    fs = os.environ.get("MCP_CODE_FILESYSTEM_PROXY_URL", "http://127.0.0.1:18101/mcp").strip()
    git = os.environ.get("MCP_CODE_GIT_PROXY_URL", "http://127.0.0.1:18102/mcp").strip()
    ag = os.environ.get("MCP_CODE_AST_GREP_PROXY_URL", "http://127.0.0.1:18103/mcp").strip()
    return fs, git, ag


async def _connect_upstream_via_stdio(
    params: StdioServerParameters,
    label: str,
) -> tuple[AsyncExitStack, ClientSession, list[types.Tool]]:
    stack = AsyncExitStack()
    await stack.__aenter__()
    try:
        logger.info(
            "mcp-code: stdio connect %s -> %s %s",
            label,
            params.command,
            " ".join(params.args),
        )
        transport_cm = stdio_client(params)
        read_s, write_s = await stack.enter_async_context(transport_cm)
        session = ClientSession(read_s, write_s)
        await stack.enter_async_context(session)
        await session.initialize()
        tools = await _list_tools_all(session)
        logger.info("mcp-code: upstream %s ready (%d tools)", label, len(tools))
        return stack, session, tools
    except BaseException:
        await stack.aclose()
        raise


async def _connect_upstream_via_streamable_http(
    url: str,
    label: str,
) -> tuple[AsyncExitStack, ClientSession, list[types.Tool]]:
    stack = AsyncExitStack()
    await stack.__aenter__()
    try:
        logger.info("mcp-code: streamable-http connect %s -> %s", label, url)
        timeout = httpx.Timeout(
            connect=60.0,
            read=float(os.environ.get("MCP_CODE_UPSTREAM_READ_TIMEOUT_SEC", "600")),
            write=120.0,
            pool=30.0,
        )
        client = httpx.AsyncClient(timeout=timeout)
        await stack.enter_async_context(client)
        transport_cm = streamable_http_client(
            url, http_client=client, terminate_on_close=False
        )
        read_s, write_s, _ = await stack.enter_async_context(transport_cm)
        session = ClientSession(read_s, write_s)
        await stack.enter_async_context(session)
        await session.initialize()
        tools = await _list_tools_all(session)
        logger.info("mcp-code: upstream %s ready (%d tools)", label, len(tools))
        return stack, session, tools
    except BaseException:
        await stack.aclose()
        raise


async def _open_upstream_sessions_parallel(
    workspace_root: str,
) -> tuple[Subsessions, list[AsyncExitStack]]:
    mode = os.environ.get("MCP_CODE_UPSTREAM_TRANSPORT", "stdio").strip().lower()
    use_http = mode in ("http", "streamable", "streamable_http")
    # Default sequential: parallel clients occasionally wedge on tools/list or subprocess spawn.
    parallel = os.environ.get("MCP_CODE_UPSTREAM_PARALLEL", "").strip().lower() in (
        "1",
        "true",
        "yes",
    )
    if use_http:
        fs_url, git_url, ag_url = _local_proxy_streamable_urls()
        if parallel:
            fs_task = asyncio.create_task(
                _connect_upstream_via_streamable_http(fs_url, "filesystem")
            )
            git_task = asyncio.create_task(
                _connect_upstream_via_streamable_http(git_url, "git")
            )
            ag_task = asyncio.create_task(
                _connect_upstream_via_streamable_http(ag_url, "ast-grep")
            )
            results = await asyncio.gather(fs_task, git_task, ag_task, return_exceptions=True)
            errors = [r for r in results if isinstance(r, BaseException)]
            if errors:
                for r in results:
                    if isinstance(r, tuple) and r and isinstance(r[0], AsyncExitStack):
                        await r[0].aclose()
                if len(errors) == 1:
                    raise errors[0]
                raise ExceptionGroup("mcp-code upstream connect failed", errors)
            fs_result, git_result, ag_result = results  # type: ignore[assignment]
        else:
            fs_result = await _connect_upstream_via_streamable_http(fs_url, "filesystem")
            git_result = await _connect_upstream_via_streamable_http(git_url, "git")
            ag_result = await _connect_upstream_via_streamable_http(ag_url, "ast-grep")
    else:
        fs_p, git_p, ag_p = _stdio_upstream_params(workspace_root)
        if parallel:
            fs_task = asyncio.create_task(_connect_upstream_via_stdio(fs_p, "filesystem"))
            git_task = asyncio.create_task(_connect_upstream_via_stdio(git_p, "git"))
            ag_task = asyncio.create_task(_connect_upstream_via_stdio(ag_p, "ast-grep"))
            results = await asyncio.gather(fs_task, git_task, ag_task, return_exceptions=True)
            errors = [r for r in results if isinstance(r, BaseException)]
            if errors:
                for r in results:
                    if isinstance(r, tuple) and r and isinstance(r[0], AsyncExitStack):
                        await r[0].aclose()
                if len(errors) == 1:
                    raise errors[0]
                raise ExceptionGroup("mcp-code upstream connect failed", errors)
            fs_result, git_result, ag_result = results  # type: ignore[assignment]
        else:
            fs_result = await _connect_upstream_via_stdio(fs_p, "filesystem")
            git_result = await _connect_upstream_via_stdio(git_p, "git")
            ag_result = await _connect_upstream_via_stdio(ag_p, "ast-grep")
    _fs_stack, fs_session, fs_tools = fs_result
    _git_stack, git_session, git_tools = git_result
    _ag_stack, ag_session, ag_tools = ag_result
    stacks = [_fs_stack, _git_stack, _ag_stack]

    names_seen: set[str] = set()
    tool_owner: dict[str, ClientSession] = {}
    merged_tools: list[types.Tool] = []
    for label, tools, sess in (
        ("filesystem", fs_tools, fs_session),
        ("git", git_tools, git_session),
        ("ast_grep", ag_tools, ag_session),
    ):
        for t in tools:
            if t.name in names_seen:
                await asyncio.gather(*[s.aclose() for s in stacks])
                raise RuntimeError(
                    f"Duplicate MCP tool name {t.name!r} from {label}; resolve in upstream servers."
                )
            names_seen.add(t.name)
            tool_owner[t.name] = sess
            merged_tools.append(t)

    expected_names: frozenset[str] | None = None
    inv = _load_tool_inventory()
    if inv:
        raw_expected = inv.get("all_tool_names_sorted")
        if isinstance(raw_expected, list):
            expected_names = frozenset(str(x) for x in raw_expected)
    got_names = {t.name for t in merged_tools}
    if expected_names is not None and got_names != expected_names:
        only_got = sorted(got_names - expected_names)
        only_exp = sorted(expected_names - got_names)
        logger.error(
            "mcp-code: merged tool set differs from upstream_tools_inventory.json "
            "(got %d, expected %d). only_in_upstream=%s only_in_runtime=%s",
            len(got_names),
            len(expected_names),
            only_exp,
            only_got,
        )
    elif expected_names is not None:
        logger.info(
            "mcp-code: merged tools match inventory (%d tools)", len(expected_names)
        )

    subs = Subsessions(
        filesystem=fs_session,
        git=git_session,
        ast_grep=ag_session,
        tool_owner=tool_owner,
        merged_tools=merged_tools,
    )
    return subs, stacks


def build_server(
    workspace_root: str,
    *,
    subs_cell: dict[str, Any],
    lifecycle: dict[str, Any],
    instructions: str,
) -> Server:
    @asynccontextmanager
    async def composite_lifespan(_srv: Server) -> AsyncIterator[dict[str, Any]]:
        yield {}

    srv = Server(
        "mcp-code",
        version="0.3.0",
        instructions=instructions,
        lifespan=composite_lifespan,
    )

    @srv.list_tools()
    async def _list_tools() -> types.ListToolsResult:
        await lifecycle["upstream_ready"].wait()
        exc = lifecycle.get("warmup_exc")
        if exc is not None:
            raise RuntimeError("mcp-code upstream warmup failed") from exc
        subs = subs_cell.get("s")
        if subs is None:
            raise RuntimeError("mcp-code upstream sessions missing after warmup.")
        return types.ListToolsResult(tools=subs.merged_tools)

    @srv.call_tool(validate_input=False)
    async def _call_tool(name: str, arguments: dict[str, Any]) -> types.CallToolResult:
        await lifecycle["upstream_ready"].wait()
        exc = lifecycle.get("warmup_exc")
        if exc is not None:
            return types.CallToolResult(
                content=[types.TextContent(type="text", text=f"Upstream warmup failed: {exc}")],
                isError=True,
            )
        subs = subs_cell.get("s")
        if subs is None:
            return types.CallToolResult(
                content=[types.TextContent(type="text", text="mcp-code upstream sessions not ready.")],
                isError=True,
            )
        owner = subs.tool_owner.get(name)
        if owner is None:
            return types.CallToolResult(
                content=[types.TextContent(type="text", text=f"Unknown tool: {name}")],
                isError=True,
            )
        args = arguments or {}
        if owner is subs.ast_grep:
            args = _default_ast_grep_project_folder(name, args, workspace_root)
        return await owner.call_tool(name, args)

    return srv


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="mcp-code aggregate MCP server")
    p.add_argument("--host", default=os.environ.get("MCP_CODE_HOST", "0.0.0.0"))
    p.add_argument("--port", type=int, default=int(os.environ.get("MCP_CODE_PORT", "8100")))
    p.add_argument("--http-path", default=os.environ.get("MCP_HTTP_PATH", "/mcp"))
    p.add_argument(
        "--workspace-root",
        default=os.environ.get("MCP_CODE_WORKSPACE_ROOT", "/mnt/eapp/code/homelab"),
    )
    return p.parse_args()


def main() -> None:
    logging.basicConfig(level=os.environ.get("MCP_CODE_LOG_LEVEL", "INFO"))
    args = parse_args()
    workspace = args.workspace_root
    if not os.path.isdir(workspace):
        raise SystemExit(f"MCP_CODE_WORKSPACE_ROOT is not a directory: {workspace}")
    if not os.access(workspace, os.W_OK):
        raise SystemExit(f"MCP_CODE_WORKSPACE_ROOT is not writable: {workspace}")

    inv = _load_tool_inventory()
    if inv:
        instructions = _instructions_from_inventory(inv)
    else:
        instructions = (
            "Combined homelab code MCP: filesystem, git, and ast-grep tools merged from "
            "three stdio MCP upstreams (default). Use tools/list for all tool schemas."
        )

    subs_cell: dict[str, Any] = {"s": None}
    lifecycle: dict[str, Any] = {
        "upstream_ready": asyncio.Event(),
        "warmup_exc": None,
    }
    app_server = build_server(
        workspace_root=workspace,
        subs_cell=subs_cell,
        lifecycle=lifecycle,
        instructions=instructions,
    )

    session_manager = StreamableHTTPSessionManager(
        app=app_server,
        event_store=None,
        json_response=False,
        stateless=False,
        security_settings=None,
        retry_interval=None,
    )
    streamable_http_app = StreamableHTTPASGIApp(session_manager)
    warmup_timeout = float(os.environ.get("MCP_CODE_WARMUP_TIMEOUT_SEC", "900"))

    @asynccontextmanager
    async def starlette_lifespan(_app: Starlette) -> AsyncIterator[None]:
        stop_warmup = asyncio.Event()

        async def upstream_supervisor() -> None:
            stacks_to_close: list[AsyncExitStack] = []
            try:
                transport = os.environ.get("MCP_CODE_UPSTREAM_TRANSPORT", "stdio").strip().lower()
                logger.info(
                    "mcp-code background warmup: upstream transport=%r (merge fs, git, ast-grep)",
                    transport,
                )
                async with asyncio.timeout(warmup_timeout):
                    subs, stacks_to_close = await _open_upstream_sessions_parallel(workspace)
                subs_cell["s"] = subs
                logger.info("mcp-code warmup complete (%d tools)", len(subs.merged_tools))
            except BaseException as exc:
                lifecycle["warmup_exc"] = exc
                logger.exception("mcp-code upstream warmup failed")
            finally:
                lifecycle["upstream_ready"].set()
                await stop_warmup.wait()
                subs_cell["s"] = None
                for st in reversed(stacks_to_close):
                    await st.aclose()

        supervisor_task = asyncio.create_task(upstream_supervisor())
        try:
            async with session_manager.run():
                yield
        finally:
            stop_warmup.set()
            await supervisor_task

    starlette = Starlette(
        debug=False,
        routes=[Route(args.http_path, endpoint=streamable_http_app)],
        lifespan=starlette_lifespan,
    )

    uvicorn.run(
        starlette,
        host=args.host,
        port=args.port,
        log_level=os.environ.get("UVICORN_LOG_LEVEL", "info").lower(),
    )
