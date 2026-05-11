from __future__ import annotations

import asyncio
import json
import os
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

AST_GREP_TOOL_NAMES = {
    "server_info",
    "dump_syntax_tree",
    "test_match_code_rule",
    "find_code",
    "find_code_by_rule",
}

AST_GREP_SEARCH_TOOL_NAMES = {
    "find_code",
    "find_code_by_rule",
}

DEFAULT_AST_GREP_MAX_RESULTS = 25
MAX_AST_GREP_MAX_RESULTS = 50

JIRA_JSON_STRING_FIELDS_BY_TOOL = {
    "jira_create_issue": {"additional_fields"},
    "jira_update_issue": {"fields", "additional_fields", "attachments"},
    "jira_transition_issue": {"fields"},
    "jira_create_issue_link": {"comment_visibility"},
}

JIRA_OMIT_ARGS_BY_TOOL = {
    # The current Atlassian transition path rejects plain-text transition comments.
    # Use jira_add_comment separately when a note is needed.
    "jira_transition_issue": {"comment"},
}

JIRA_OMIT_FALSE_BOOL_ARGS_BY_TOOL = {
    # The Atlassian connector routes jira_add_comment through the JSM endpoint
    # when `public` is present, even when the issue is a normal Jira issue.
    # Omit `public=false` unless the caller explicitly needs JSM behavior.
    "jira_add_comment": {"public"},
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
            url_env = server_config.get("url_from_env")
            if isinstance(url_env, str) and url_env.strip():
                from_env = os.getenv(url_env.strip(), "").strip()
                if from_env:
                    url = from_env
            if not url:
                continue
            normalized[server_name] = {
                "transport": "http" if transport != "sse" else "sse",
                "url": url,
            }
            headers: dict[str, str] = {}
            raw_headers = server_config.get("headers")
            if isinstance(raw_headers, dict):
                headers = {
                    str(name): ""
                    if value is None
                    else value
                    if isinstance(value, str)
                    else str(value)
                    for name, value in raw_headers.items()
                }
            inject_env = server_config.get("x_api_key_from_env")
            if isinstance(inject_env, str) and inject_env.strip():
                secret = os.getenv(inject_env.strip(), "").strip()
                if secret:
                    headers.setdefault("x-api-key", secret)
            if headers:
                normalized[server_name]["headers"] = headers
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


def _required_tool_args(args_schema: Any) -> set[str]:
    if args_schema is None:
        return set()

    if isinstance(args_schema, dict):
        return set(args_schema.get("required", []))

    model_json_schema = getattr(args_schema, "model_json_schema", None)
    if callable(model_json_schema):
        return set(model_json_schema().get("required", []))

    return set()


def _recoverable_tool_error(tool_name: str, exc: Exception) -> list[dict[str, str]]:
    payload = {
        "ok": False,
        "tool": tool_name,
        "error_type": exc.__class__.__name__,
        "error": str(exc),
        "recoverable": True,
        "instruction": (
            "Treat this as a failed tool observation, not a fatal agent failure. "
            "Adjust the tool arguments, call another relevant tool, ask for missing "
            "information, or report the blocker."
        ),
    }
    return _text_blocks(json.dumps(payload, indent=2, default=str))


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

    attempts = max(1, int(os.getenv("HOMELAB_MCP_BOOTSTRAP_RETRIES", "3")))
    delay_sec = float(os.getenv("HOMELAB_MCP_BOOTSTRAP_RETRY_DELAY_SEC", "2"))

    async def _load_tools():
        last_exc: BaseException | None = None
        for attempt in range(attempts):
            try:
                client = MultiServerMCPClient(normalized_servers)
                return await client.get_tools()
            except BaseException as exc:
                last_exc = exc
                if attempt + 1 >= attempts:
                    break
                await asyncio.sleep(delay_sec)
        assert last_exc is not None
        raise last_exc

    return _run_coro(_load_tools())


_mcp_toolset_lock = asyncio.Lock()
_mcp_toolset_cache: dict[tuple[str, str, str], list[Any]] = {}


def build_normalized_servers_for_session(config_path: Path) -> dict[str, Any]:
    """Resolve MCP server dict from ``mcp.json``, applying optional mcp-code URL override."""
    if not config_path.exists():
        return {}
    config = json.loads(config_path.read_text())
    raw_servers = config.get("mcpServers", {})
    normalized = _normalize_server_config(raw_servers)
    if not normalized:
        return {}

    from framework.mcp_workspace_context import effective_mcp_code_url

    override = effective_mcp_code_url()
    if override and "mcp-code" in normalized:
        normalized = deepcopy(normalized)
        normalized["mcp-code"] = {**normalized["mcp-code"], "url": override}
    return normalized


async def _cached_wrapped_toolset(
    *,
    servers: dict[str, Any],
    repo: Path,
    wrap_profile: str,
) -> list[Any]:
    key_servers = json.dumps(servers, sort_keys=True, default=str)
    key = (key_servers, str(repo.resolve()), wrap_profile)
    async with _mcp_toolset_lock:
        hit = _mcp_toolset_cache.get(key)
        if hit is not None:
            return hit

        from langchain_mcp_adapters.client import MultiServerMCPClient

        client = MultiServerMCPClient(servers)
        raw = await client.get_tools()
        if wrap_profile in {"code", "tech_lead"}:
            wrapped: list[Any] = list(
                wrap_ast_grep_tools(wrap_filesystem_tools(raw, repo), repo)
            )
        else:
            wrapped = list(raw)
        _mcp_toolset_cache[key] = wrapped
        return wrapped


def load_workspace_routed_mcp_tools(
    config_path: Path,
    *,
    wrap_profile: str,
    static_repo: Path,
) -> list[Any]:
    """Load MCP tools; resolve mcp-code URL and repo root on each invocation (parallel lanes)."""
    if not config_path.exists():
        return []

    templates = load_mcp_tools(config_path)
    if not templates:
        return []

    def _make_proxy(template_tool: Any) -> Any:
        async def _route(**kwargs: Any) -> Any:
            try:
                from framework.mcp_workspace_context import effective_code_repository_root

                servers = build_normalized_servers_for_session(config_path)
                if not servers:
                    return _recoverable_tool_error(
                        template_tool.name,
                        RuntimeError("No MCP servers resolved from mcp.json."),
                    )
                repo = effective_code_repository_root(static_repo)
                toolset = await _cached_wrapped_toolset(
                    servers=servers,
                    repo=repo,
                    wrap_profile=wrap_profile,
                )
                inner = next((t for t in toolset if t.name == template_tool.name), None)
                if inner is None:
                    return _recoverable_tool_error(
                        template_tool.name,
                        RuntimeError(
                            f"MCP tool {template_tool.name!r} missing for this session URL or profile."
                        ),
                    )
                return await inner.ainvoke(kwargs)
            except Exception as exc:
                return _recoverable_tool_error(template_tool.name, exc)

        return StructuredTool(
            name=template_tool.name,
            description=template_tool.description or "",
            args_schema=template_tool.args_schema,
            coroutine=_route,
            response_format="content",
        )

    return [_make_proxy(t) for t in templates]


def wrap_blank_optional_args(
    raw_tools: list[Any],
    *,
    json_string_fields_by_tool: dict[str, set[str]] | None = None,
    omit_args_by_tool: dict[str, set[str]] | None = None,
    omit_false_bool_args_by_tool: dict[str, set[str]] | None = None,
) -> list[Any]:
    """Drop blank optional string args and normalize JSON-string inputs when needed."""
    wrapped_tools: list[Any] = []
    json_string_fields_by_tool = json_string_fields_by_tool or {}
    omit_args_by_tool = omit_args_by_tool or {}
    omit_false_bool_args_by_tool = omit_false_bool_args_by_tool or {}

    for raw_tool in raw_tools:
        required_args = _required_tool_args(getattr(raw_tool, "args_schema", None))
        json_string_fields = json_string_fields_by_tool.get(raw_tool.name, set())
        omitted_args = omit_args_by_tool.get(raw_tool.name, set())
        omitted_false_bool_args = omit_false_bool_args_by_tool.get(raw_tool.name, set())

        async def call_sanitized_tool(
            _raw_tool=raw_tool,
            _required_args=required_args,
            _json_string_fields=json_string_fields,
            _omitted_args=omitted_args,
            _omitted_false_bool_args=omitted_false_bool_args,
            **kwargs: Any,
        ) -> Any:
            sanitized_args: dict[str, Any] = {}
            for key, value in kwargs.items():
                if key in _omitted_args:
                    continue

                if key in _omitted_false_bool_args and value is False:
                    continue

                if isinstance(value, str):
                    if not value.strip() and key not in _required_args:
                        continue
                    sanitized_args[key] = value
                    continue

                if key in _json_string_fields and isinstance(value, (dict, list)):
                    sanitized_args[key] = json.dumps(value)
                    continue

                sanitized_args[key] = value

            try:
                return await _raw_tool.ainvoke(sanitized_args)
            except Exception as exc:
                return _recoverable_tool_error(_raw_tool.name, exc)

        wrapped_tools.append(
            StructuredTool(
                name=raw_tool.name,
                description=raw_tool.description or "",
                args_schema=raw_tool.args_schema,
                coroutine=call_sanitized_tool,
                response_format="content",
            )
        )

    return wrapped_tools


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


def _is_broad_recursive_pattern(pattern: str) -> bool:
    normalized = pattern.strip()
    if not normalized:
        return True
    return normalized.startswith("**/") or "/" not in normalized


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
            try:
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
                    normalized_search_path = Path(tool_args["path"]).resolve()
                    if normalized_search_path == repo_root and _is_broad_recursive_pattern(
                        str(tool_args.get("pattern", ""))
                    ):
                        raise ValueError(
                            "Broad recursive searches from the repository root are disabled "
                            "because the upstream filesystem server walks the entire tree and "
                            "is too slow over NFS. First call `list_directory` on "
                            f"`{repo_root}`, then run `search_files` on a narrower subdirectory "
                            "such as `applications`, `docs`, `kubernetes`, `terraform`, or `scripts`."
                        )
                    tool_args["excludePatterns"] = _merge_excludes(
                        tool_args.get("excludePatterns")
                    )

                return await _raw_tool.ainvoke(tool_args)
            except Exception as exc:
                return _recoverable_tool_error(_raw_tool.name, exc)

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
            path: str,
            excludePatterns: list[str] | None = None,
        ) -> Any:
            try:
                normalized_path = _normalize_repo_path(path, repo_root)
                if Path(normalized_path).resolve() == repo_root:
                    raise ValueError(
                        "search_repository_files requires a narrowed repo-relative directory, not "
                        "the repository root. First inspect `/mnt/eapp/code/homelab` with "
                        "`list_directory`, then search a specific subtree."
                    )
            except Exception as exc:
                return _recoverable_tool_error("search_repository_files", exc)

            merged_excludes = _merge_excludes(excludePatterns)
            sections: list[str] = []

            for pattern in patterns:
                try:
                    result = await search_tool.ainvoke(
                        {
                            "path": normalized_path,
                            "pattern": pattern,
                            "excludePatterns": merged_excludes,
                        }
                    )
                except Exception as exc:
                    sections.append(
                        f"{pattern}\n{_content_to_text(_recoverable_tool_error(search_tool.name, exc))}"
                    )
                    continue
                sections.append(f"{pattern}\n{_content_to_text(result)}")

            return _text_blocks("\n\n".join(sections))

        wrapped_tools.append(
            StructuredTool(
                name="search_repository_files",
                description=(
                    "Search one or more glob patterns within a narrowed subdirectory of the "
                    f"current repository root `{repo_root}` using built-in recursive excludes. "
                    "Do not use this from the repo root; first narrow the search with "
                    "`list_directory`."
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
                            "description": "Required repo-relative directory to search from. Must be narrower than the repo root, such as `applications`, `docs`, `kubernetes`, `terraform`, or `scripts`.",
                        },
                        "excludePatterns": {
                            "type": "array",
                            "items": {"type": "string"},
                            "default": [],
                            "description": "Additional glob excludes merged with the built-in default excludes.",
                        },
                    },
                    "required": ["patterns", "path"],
                },
                coroutine=search_repository_files,
                response_format="content",
            )
        )

    return wrapped_tools


def _scoped_ast_grep_description(description: str, repo_root: Path, *, search: bool = False) -> str:
    scoped = (
        f"{description} This runtime scopes ast-grep code search to the repository root "
        f"`{repo_root}`. Use `.` or repo-relative paths for `project_folder`."
    )
    if search:
        scoped += (
            f" Search responses default to `max_results={DEFAULT_AST_GREP_MAX_RESULTS}` "
            f"and are capped at `max_results={MAX_AST_GREP_MAX_RESULTS}` to preserve "
            "agent context. Use filesystem tools only after ast-grep identifies the "
            "specific files that need inspection."
        )
    return scoped


def _bounded_ast_grep_max_results(value: Any) -> int:
    try:
        requested = int(value)
    except (TypeError, ValueError):
        requested = 0

    if requested <= 0:
        return DEFAULT_AST_GREP_MAX_RESULTS
    return min(requested, MAX_AST_GREP_MAX_RESULTS)


def wrap_ast_grep_tools(raw_tools: list[Any], repo_root: Path) -> list[Any]:
    """Constrain ast-grep MCP searches to the repo and cap returned matches."""
    repo_root = repo_root.resolve()
    wrapped_tools: list[Any] = []

    for raw_tool in raw_tools:
        if raw_tool.name not in AST_GREP_TOOL_NAMES:
            wrapped_tools.append(raw_tool)
            continue

        async def call_scoped_ast_grep(_raw_tool=raw_tool, **kwargs: Any) -> Any:
            try:
                tool_args = deepcopy(kwargs)

                if _raw_tool.name in AST_GREP_SEARCH_TOOL_NAMES:
                    tool_args["project_folder"] = _normalize_repo_path(
                        tool_args.get("project_folder"),
                        repo_root,
                    )
                    tool_args["max_results"] = _bounded_ast_grep_max_results(
                        tool_args.get("max_results")
                    )
                    output_format = tool_args.get("output_format")
                    if output_format is None or not str(output_format).strip():
                        tool_args["output_format"] = "text"

                return await _raw_tool.ainvoke(tool_args)
            except Exception as exc:
                return _recoverable_tool_error(_raw_tool.name, exc)

        wrapped_tools.append(
            StructuredTool(
                name=raw_tool.name,
                description=_scoped_ast_grep_description(
                    raw_tool.description or "",
                    repo_root,
                    search=raw_tool.name in AST_GREP_SEARCH_TOOL_NAMES,
                ),
                args_schema=raw_tool.args_schema,
                coroutine=call_scoped_ast_grep,
                response_format="content",
            )
        )

    return wrapped_tools
