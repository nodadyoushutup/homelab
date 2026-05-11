"""Single-process mcp-code: filesystem + git + ast-grep tools without mcp-proxy or stdio merges."""

from __future__ import annotations

import argparse
import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

import mcp.types as types
import uvicorn
from mcp.server import Server
from mcp.server.fastmcp.server import StreamableHTTPASGIApp
from mcp.server.streamable_http_manager import StreamableHTTPSessionManager
from mcp.types import TextContent
from starlette.applications import Starlette
from starlette.routing import Route

from mcp_code.native_astgrep import AST_TOOLS, call_ast_tool
from mcp_code.native_fs import FS_TOOLS, call_fs_tool
from mcp_code.native_git import GIT_TOOLS, call_git_tool

logger = logging.getLogger(__name__)


def _merge_tools() -> list[types.Tool]:
    merged = [*FS_TOOLS, *GIT_TOOLS, *AST_TOOLS]
    seen: set[str] = set()
    for t in merged:
        if t.name in seen:
            raise RuntimeError(f"Duplicate native tool name: {t.name}")
        seen.add(t.name)
    return merged


def build_native_server(
    workspace: Path,
    *,
    config_path: str,
) -> Server:
    all_tools = _merge_tools()
    logger.info(
        "mcp-code native: %d tools (fs=%d git=%d ast=%d) workspace=%s config=%s",
        len(all_tools),
        len(FS_TOOLS),
        len(GIT_TOOLS),
        len(AST_TOOLS),
        workspace,
        config_path or "(none)",
    )

    srv = Server(
        "mcp-code",
        version="0.2.0",
        instructions=(
            "Homelab native mcp-code: filesystem, git, and ast-grep tools in one process "
            "(no stdio merge). Workspace is the allowed root for all three."
        ),
    )

    @srv.list_tools()
    async def _list_tools() -> types.ListToolsResult:
        return types.ListToolsResult(tools=all_tools)

    @srv.call_tool(validate_input=False)
    async def _call_tool(name: str, arguments: dict[str, Any]) -> types.CallToolResult:
        args = arguments or {}
        try:
            out = await call_fs_tool(name, args, workspace=workspace)
            if out is not None:
                return out
            out = await call_git_tool(name, args, allowed_repository=workspace)
            if out is not None:
                return out
            out = await call_ast_tool(name, args, workspace=workspace, config_path=config_path)
            if out is not None:
                return out
        except Exception as exc:
            logger.exception("native tool error %s", name)
            return types.CallToolResult(
                content=[TextContent(type="text", text=str(exc))],
                isError=True,
            )
        return types.CallToolResult(
            content=[TextContent(type="text", text=f"Unknown tool: {name}")],
            isError=True,
        )

    return srv


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="mcp-code native aggregate MCP server")
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
    workspace = Path(args.workspace_root)
    if not workspace.is_dir():
        raise SystemExit(f"MCP_CODE_WORKSPACE_ROOT is not a directory: {workspace}")
    if not os.access(workspace, os.W_OK):
        raise SystemExit(f"MCP_CODE_WORKSPACE_ROOT is not writable: {workspace}")

    cfg = args.ast_grep_config
    if cfg and not os.path.isfile(cfg):
        logger.warning("AST_GREP_CONFIG missing (%s); ast-grep custom languages may be limited", cfg)

    app_server = build_native_server(
        workspace.resolve(),
        config_path=cfg if os.path.isfile(cfg) else "",
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

    @asynccontextmanager
    async def lifespan(_app: Starlette):
        async with session_manager.run():
            yield

    starlette = Starlette(
        debug=False,
        routes=[Route(args.http_path, endpoint=streamable_http_app)],
        lifespan=lifespan,
    )

    uvicorn.run(
        starlette,
        host=args.host,
        port=args.port,
        log_level=os.environ.get("UVICORN_LOG_LEVEL", "info").lower(),
    )
