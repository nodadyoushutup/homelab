"""Streamable-HTTP MCP server that merges tools from filesystem, git, and ast-grep stdio servers."""

from __future__ import annotations

import argparse
import logging
import os
from collections.abc import AsyncIterator
from contextlib import AsyncExitStack, asynccontextmanager
from typing import Any

import mcp.types as types
import uvicorn
from mcp.client.session import ClientSession
from mcp.client.stdio import StdioServerParameters, stdio_client
from mcp.server import Server
from mcp.server.fastmcp.server import StreamableHTTPASGIApp
from mcp.server.streamable_http_manager import StreamableHTTPSessionManager
from starlette.applications import Starlette
from starlette.routing import Route

logger = logging.getLogger(__name__)

AST_GREP_PROJECT_TOOLS = frozenset({"find_code", "find_code_by_rule"})


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
    __slots__ = ("filesystem", "git", "ast_grep", "tool_owner")

    def __init__(
        self,
        filesystem: ClientSession,
        git: ClientSession,
        ast_grep: ClientSession,
        tool_owner: dict[str, ClientSession],
    ) -> None:
        self.filesystem = filesystem
        self.git = git
        self.ast_grep = ast_grep
        self.tool_owner = tool_owner


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


async def _open_child_sessions(
    stack: AsyncExitStack,
    workspace_root: str,
    ast_grep_config: str,
    ast_grep_default_root: str,
    ast_grep_allowed_roots: str,
) -> Subsessions:
    fs_streams = await stack.enter_async_context(
        stdio_client(
            StdioServerParameters(
                command="mcp-server-filesystem",
                args=[workspace_root],
            )
        )
    )
    fs_read, fs_write = fs_streams
    fs_session = ClientSession(fs_read, fs_write)
    await fs_session.initialize()

    git_streams = await stack.enter_async_context(
        stdio_client(
            StdioServerParameters(
                command="mcp-server-git",
                args=["--repository", workspace_root],
            )
        )
    )
    git_read, git_write = git_streams
    git_session = ClientSession(git_read, git_write)
    await git_session.initialize()

    ag_env = {
        **os.environ,
        "AST_GREP_DEFAULT_PROJECT_ROOT": ast_grep_default_root,
        "AST_GREP_ALLOWED_ROOTS": ast_grep_allowed_roots,
        "AST_GREP_CONFIG": ast_grep_config,
    }
    ag_streams = await stack.enter_async_context(
        stdio_client(
            StdioServerParameters(
                command=os.environ.get("MCP_CODE_AST_GREP_PYTHON", "python3"),
                args=[os.environ["MCP_CODE_AST_GREP_SERVER_PATH"], "--transport", "stdio"],
                env=ag_env,
            )
        )
    )
    ag_read, ag_write = ag_streams
    ag_session = ClientSession(ag_read, ag_write)
    await ag_session.initialize()

    fs_tools = await _list_tools_all(fs_session)
    git_tools = await _list_tools_all(git_session)
    ag_tools = await _list_tools_all(ag_session)

    names_seen: set[str] = set()
    tool_owner: dict[str, ClientSession] = {}
    for label, tools, sess in (
        ("filesystem", fs_tools, fs_session),
        ("git", git_tools, git_session),
        ("ast_grep", ag_tools, ag_session),
    ):
        for t in tools:
            if t.name in names_seen:
                raise RuntimeError(
                    f"Duplicate MCP tool name {t.name!r} from {label}; resolve in upstream servers."
                )
            names_seen.add(t.name)
            tool_owner[t.name] = sess

    return Subsessions(
        filesystem=fs_session,
        git=git_session,
        ast_grep=ag_session,
        tool_owner=tool_owner,
    )


def build_server(
    workspace_root: str,
    ast_grep_config: str,
    ast_grep_default_root: str,
    ast_grep_allowed_roots: str,
) -> Server:
    subs_cell: dict[str, Subsessions | None] = {"s": None}

    @asynccontextmanager
    async def composite_lifespan(_srv: Server) -> AsyncIterator[dict[str, Any]]:
        async with AsyncExitStack() as stack:
            subs = await _open_child_sessions(
                stack,
                workspace_root=workspace_root,
                ast_grep_config=ast_grep_config,
                ast_grep_default_root=ast_grep_default_root,
                ast_grep_allowed_roots=ast_grep_allowed_roots,
            )
            subs_cell["s"] = subs
            try:
                yield {"subsessions": subs}
            finally:
                subs_cell["s"] = None

    srv = Server(
        "mcp-code",
        version="0.1.0",
        instructions=(
            "Combined homelab code MCP: Model Context Protocol tools from "
            "@modelcontextprotocol/server-filesystem (repo workspace), mcp-server-git "
            "(same repository root), and the homelab ast-grep server scoped to that "
            "same workspace."
        ),
        lifespan=composite_lifespan,
    )

    @srv.list_tools()
    async def _list_tools() -> types.ListToolsResult:
        subs = subs_cell["s"]
        if subs is None:
            raise RuntimeError("Child MCP sessions are not initialized.")
        tools: list[types.Tool] = []
        for session in (subs.filesystem, subs.git, subs.ast_grep):
            tools.extend(await _list_tools_all(session))
        return types.ListToolsResult(tools=tools)

    @srv.call_tool(validate_input=False)
    async def _call_tool(name: str, arguments: dict[str, Any]) -> types.CallToolResult:
        subs = subs_cell["s"]
        if subs is None:
            raise RuntimeError("Child MCP sessions are not initialized.")
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
    p.add_argument(
        "--ast-grep-config",
        default=os.environ.get("AST_GREP_CONFIG", "/opt/ast-grep-config/sgconfig.yml"),
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

    ast_server = os.environ.get("MCP_CODE_AST_GREP_SERVER_PATH", "")
    if not ast_server or not os.path.isfile(ast_server):
        raise SystemExit("MCP_CODE_AST_GREP_SERVER_PATH must point at the ast-grep server script.")

    ast_default = os.environ.get("AST_GREP_DEFAULT_PROJECT_ROOT", workspace)
    ast_allowed = os.environ.get("AST_GREP_ALLOWED_ROOTS", workspace)

    app_server = build_server(
        workspace_root=workspace,
        ast_grep_config=args.ast_grep_config,
        ast_grep_default_root=ast_default,
        ast_grep_allowed_roots=ast_allowed,
    )

    session_manager = StreamableHTTPSessionManager(
        app=app_server,
        event_store=None,
        json_response=True,
        stateless=True,
        security_settings=None,
        retry_interval=None,
    )
    streamable_http_app = StreamableHTTPASGIApp(session_manager)
    @asynccontextmanager
    async def _lifespan(_app: Starlette) -> AsyncIterator[None]:
        async with session_manager.run():
            yield

    starlette = Starlette(
        debug=False,
        routes=[Route(args.http_path, endpoint=streamable_http_app)],
        lifespan=_lifespan,
    )

    uvicorn.run(
        starlette,
        host=args.host,
        port=args.port,
        log_level=os.environ.get("UVICORN_LOG_LEVEL", "info").lower(),
    )
