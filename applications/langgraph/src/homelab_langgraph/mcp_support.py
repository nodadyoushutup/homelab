from __future__ import annotations

import asyncio
import json
import threading
from copy import deepcopy
from pathlib import Path
from typing import Any

from langchain_core.tools import StructuredTool


DEFAULT_REPO_SEARCH_EXCLUDES = (
    "**/.git/**",
    "**/.pnpm-store/**",
    "**/node_modules/**",
    "**/.next/**",
    "**/dist/**",
    "**/build/**",
    "**/coverage/**",
    "**/.terraform/**",
    "**/__pycache__/**",
    "**/.venv/**",
    "**/venv/**",
)

FILESYSTEM_TOOL_NAMES = {
    "read_file",
    "read_text_file",
    "read_media_file",
    "read_multiple_files",
    "write_file",
    "edit_file",
    "create_directory",
    "list_directory",
    "list_directory_with_sizes",
    "directory_tree",
    "move_file",
    "search_files",
    "get_file_info",
    "list_allowed_directories",
}


def _run_coro(coro):
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        return asyncio.run(coro)

    result: Any = None
    error: BaseException | None = None

    def _runner() -> None:
        nonlocal result, error
        try:
            result = asyncio.run(coro)
        except BaseException as exc:  # pragma: no cover - defensive startup wrapper
            error = exc

    thread = threading.Thread(target=_runner, daemon=True)
    thread.start()
    thread.join()

    if error is not None:
        raise error
    return result


def _normalize_server_config(raw_servers: dict[str, dict[str, Any]]) -> dict[str, dict[str, Any]]:
    normalized: dict[str, dict[str, Any]] = {}
    for server_name, server_config in raw_servers.items():
        transport = server_config.get("transport") or server_config.get("type")
        if not transport:
            continue

        if transport in {"http", "streamable_http", "sse"}:
            url = server_config.get("url")
            if not url:
                continue
            normalized[server_name] = {
                "transport": "http" if transport != "sse" else "sse",
                "url": url,
            }
            if server_config.get("headers"):
                normalized[server_name]["headers"] = server_config["headers"]
        elif transport == "stdio":
            command = server_config.get("command")
            if not command:
                continue
            normalized[server_name] = {
                "transport": "stdio",
                "command": command,
                "args": server_config.get("args", []),
            }
            if server_config.get("env"):
                normalized[server_name]["env"] = server_config["env"]
    return normalized


def load_mcp_tools(config_path: Path) -> list[Any]:
    """Load MCP tools from a local JSON config if one is present."""
    if not config_path.exists():
        return []

    config = json.loads(config_path.read_text())
    raw_servers = config.get("mcpServers", {})
    normalized_servers = _normalize_server_config(raw_servers)
    if not normalized_servers:
        return []

    from langchain_mcp_adapters.client import MultiServerMCPClient

    async def _load_tools():
        client = MultiServerMCPClient(normalized_servers)
        return await client.get_tools()

    return _run_coro(_load_tools())


def _normalize_repo_path(path: str | None, repo_root: Path) -> str:
    repo_root = repo_root.resolve()
    if path is None:
        return str(repo_root)

    raw_path = path.strip()
    if not raw_path or raw_path == ".":
        return str(repo_root)

    if Path(raw_path).is_absolute():
        candidate = Path(raw_path).resolve()
    else:
        if raw_path == repo_root.name:
            candidate = repo_root
        elif raw_path.startswith(f"{repo_root.name}/"):
            candidate = (repo_root.parent / raw_path).resolve()
        else:
            candidate = (repo_root / raw_path).resolve()

    if candidate == repo_root or repo_root in candidate.parents:
        return str(candidate)

    if candidate in repo_root.parents:
        return str(repo_root)

    raise ValueError(
        f"Path '{path}' resolves outside the repository root '{repo_root}'. "
        "Use '.' or a repo-relative path."
    )


def _merge_excludes(extra_patterns: list[str] | None) -> list[str]:
    merged: list[str] = []
    for pattern in [*DEFAULT_REPO_SEARCH_EXCLUDES, *(extra_patterns or [])]:
        if pattern not in merged:
            merged.append(pattern)
    return merged


def _content_to_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        text_parts: list[str] = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                text = item.get("text")
                if isinstance(text, str):
                    text_parts.append(text)
        if text_parts:
            return "\n\n".join(text_parts)
    return json.dumps(content, indent=2, default=str)


def _text_blocks(text: str) -> list[dict[str, str]]:
    return [{"type": "text", "text": text}]


def _scoped_tool_description(description: str, repo_root: Path, *, search: bool = False) -> str:
    scoped = (
        f"{description} This runtime scopes filesystem access to the repository root "
        f"`{repo_root}`. Use `.` or repo-relative paths."
    )
    if search:
        excludes = ", ".join(DEFAULT_REPO_SEARCH_EXCLUDES)
        scoped += f" Default recursive search excludes: {excludes}."
    return scoped


def wrap_filesystem_tools(raw_tools: list[Any], repo_root: Path) -> list[Any]:
    """Constrain filesystem MCP tools to a repository root and add safer search helpers."""
    repo_root = repo_root.resolve()
    wrapped_tools: list[Any] = []
    tool_by_name = {tool.name: tool for tool in raw_tools}

    for raw_tool in raw_tools:
        if raw_tool.name not in FILESYSTEM_TOOL_NAMES:
            wrapped_tools.append(raw_tool)
            continue

        if raw_tool.name == "list_allowed_directories":
            async def list_allowed_directories() -> Any:
                return _text_blocks(f"Allowed directories:\n{repo_root}")

            wrapped_tools.append(
                StructuredTool(
                    name=raw_tool.name,
                    description=(
                        "Return the repository root available to this runtime. "
                        f"The current repo root is `{repo_root}`."
                    ),
                    args_schema=raw_tool.args_schema,
                    coroutine=list_allowed_directories,
                    response_format="content",
                )
            )
            continue

        async def call_scoped_tool(_raw_tool=raw_tool, **kwargs: Any) -> Any:
            tool_args = deepcopy(kwargs)

            if "path" in tool_args:
                tool_args["path"] = _normalize_repo_path(tool_args["path"], repo_root)
            if "paths" in tool_args:
                tool_args["paths"] = [
                    _normalize_repo_path(path, repo_root) for path in tool_args["paths"]
                ]
            if "source" in tool_args:
                tool_args["source"] = _normalize_repo_path(tool_args["source"], repo_root)
            if "destination" in tool_args:
                tool_args["destination"] = _normalize_repo_path(
                    tool_args["destination"], repo_root
                )
            if _raw_tool.name == "search_files":
                tool_args["excludePatterns"] = _merge_excludes(
                    tool_args.get("excludePatterns")
                )

            return await _raw_tool.ainvoke(tool_args)

        wrapped_tools.append(
            StructuredTool(
                name=raw_tool.name,
                description=_scoped_tool_description(
                    raw_tool.description or "",
                    repo_root,
                    search=raw_tool.name == "search_files",
                ),
                args_schema=raw_tool.args_schema,
                coroutine=call_scoped_tool,
                response_format="content",
            )
        )

    search_tool = tool_by_name.get("search_files")
    if search_tool is not None:

        async def search_repository_files(
            patterns: list[str],
            path: str = ".",
            excludePatterns: list[str] | None = None,
        ) -> Any:
            normalized_path = _normalize_repo_path(path, repo_root)
            merged_excludes = _merge_excludes(excludePatterns)
            sections: list[str] = []

            for pattern in patterns:
                result = await search_tool.ainvoke(
                    {
                        "path": normalized_path,
                        "pattern": pattern,
                        "excludePatterns": merged_excludes,
                    }
                )
                sections.append(f"{pattern}\n{_content_to_text(result)}")

            return _text_blocks("\n\n".join(sections))

        wrapped_tools.append(
            StructuredTool(
                name="search_repository_files",
                description=(
                    "Search one or more glob patterns within the current repository root "
                    f"`{repo_root}` using built-in recursive excludes. Prefer this over "
                    "issuing multiple broad `search_files` calls."
                ),
                args_schema={
                    "type": "object",
                    "properties": {
                        "patterns": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "Glob patterns to search within the repository.",
                        },
                        "path": {
                            "type": "string",
                            "default": ".",
                            "description": "Repo-relative directory to search from. Use '.' for the repo root.",
                        },
                        "excludePatterns": {
                            "type": "array",
                            "items": {"type": "string"},
                            "default": [],
                            "description": "Additional glob excludes merged with the built-in default excludes.",
                        },
                    },
                    "required": ["patterns"],
                },
                coroutine=search_repository_files,
                response_format="content",
            )
        )

    return wrapped_tools
