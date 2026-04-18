from __future__ import annotations

import base64
import contextlib
import difflib
import fnmatch
import mimetypes
import os
import shutil
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import parse_qs
from typing import Any

from mcp.server.fastmcp import Context, FastMCP
from mcp.server.transport_security import TransportSecuritySettings
from pydantic import Field
from starlette.applications import Starlette
from starlette.responses import JSONResponse, PlainTextResponse
from starlette.routing import Mount, Route
import uvicorn


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    value = int(raw)
    if value <= 0:
        raise ValueError(f"{name} must be a positive integer")
    return value


def _split_csv(raw: str) -> list[str]:
    return [value.strip() for value in raw.split(",") if value.strip()]


def _iso_timestamp(timestamp: float) -> str:
    return datetime.fromtimestamp(timestamp, tz=UTC).isoformat()


def _parse_workspace_map(raw: str) -> dict[str, Path]:
    mapping: dict[str, Path] = {}
    for item in _split_csv(raw):
        if "=" not in item:
            raise ValueError(
                "MCP_FILESYSTEM_WORKSPACE_MAP entries must use name=/absolute/path"
            )
        name, path = item.split("=", 1)
        workspace_name = name.strip()
        workspace_path = Path(path.strip()).resolve()
        if not workspace_name:
            raise ValueError("workspace map names must not be empty")
        if not workspace_path.is_absolute():
            raise ValueError("workspace map paths must be absolute")
        mapping[workspace_name] = workspace_path
    return mapping


def _normalize_access_mode(raw: str) -> str:
    candidate = raw.strip().lower()
    if not candidate:
        return "read-only"
    normalized = {
        "ro": "read-only",
        "readonly": "read-only",
        "read-only": "read-only",
        "read": "read-only",
        "rw": "read-write",
        "readwrite": "read-write",
        "read-write": "read-write",
        "write": "read-write",
    }.get(candidate)
    if normalized is None:
        raise ValueError(
            "access mode must be one of read-only, read-write, ro, rw, read, or write"
        )
    return normalized


@dataclass(slots=True)
class Settings:
    host: str
    port: int
    http_path: str
    allowed_workspace_roots: list[Path]
    default_workspace_root: str
    workspace_map: dict[str, Path]
    default_workspace_name: str
    workspace_root_header: str
    workspace_root_query_param: str
    workspace_name_header: str
    workspace_name_query_param: str
    access_header: str
    access_query_param: str
    default_access_mode: str
    allowed_hosts: list[str]
    allowed_origins: list[str]


def load_settings() -> Settings:
    default_allowed_hosts = [
        "127.0.0.1",
        "127.0.0.1:*",
        "localhost",
        "localhost:*",
        "[::1]",
        "[::1]:*",
        "mcp.filesystem.nodadyoushutup.com",
        "mcp.filesystem.nodadyoushutup.com:*",
    ]
    default_allowed_origins = [
        "http://127.0.0.1",
        "http://127.0.0.1:*",
        "http://localhost",
        "http://localhost:*",
        "http://[::1]",
        "http://[::1]:*",
        "https://mcp.filesystem.nodadyoushutup.com",
    ]
    allowed_roots_raw = os.getenv("MCP_FILESYSTEM_ALLOWED_WORKSPACE_ROOTS", "/mnt/eapp/code")
    workspace_map_raw = os.getenv(
        "MCP_FILESYSTEM_WORKSPACE_MAP",
        "homelab=/mnt/eapp/code/homelab",
    )
    return Settings(
        host=os.getenv("MCP_FILESYSTEM_HOST", "0.0.0.0"),
        port=_env_int("MCP_FILESYSTEM_PORT", 8098),
        http_path=os.getenv("MCP_FILESYSTEM_HTTP_PATH", "/mcp"),
        allowed_workspace_roots=[
            Path(root).resolve() for root in allowed_roots_raw.split(":") if root.strip()
        ],
        default_workspace_root=os.getenv("MCP_FILESYSTEM_DEFAULT_WORKSPACE_ROOT", "").strip(),
        workspace_map=_parse_workspace_map(workspace_map_raw),
        default_workspace_name=os.getenv("MCP_FILESYSTEM_DEFAULT_WORKSPACE_NAME", "").strip(),
        workspace_root_header=os.getenv(
            "MCP_FILESYSTEM_WORKSPACE_ROOT_HEADER", "x-workspace-root"
        ).strip(),
        workspace_root_query_param=os.getenv(
            "MCP_FILESYSTEM_WORKSPACE_ROOT_QUERY_PARAM", "workspace_root"
        ).strip(),
        workspace_name_header=os.getenv(
            "MCP_FILESYSTEM_WORKSPACE_NAME_HEADER", "x-workspace-name"
        ).strip(),
        workspace_name_query_param=os.getenv(
            "MCP_FILESYSTEM_WORKSPACE_NAME_QUERY_PARAM", "workspace_name"
        ).strip(),
        access_header=os.getenv("MCP_FILESYSTEM_ACCESS_HEADER", "x-mcp-filesystem-access").strip(),
        access_query_param=os.getenv("MCP_FILESYSTEM_ACCESS_QUERY_PARAM", "access_mode").strip(),
        default_access_mode=_normalize_access_mode(
            os.getenv("MCP_FILESYSTEM_DEFAULT_ACCESS_MODE", "read-only")
        ),
        allowed_hosts=_split_csv(
            os.getenv("MCP_FILESYSTEM_ALLOWED_HOSTS", ",".join(default_allowed_hosts))
        ),
        allowed_origins=_split_csv(
            os.getenv("MCP_FILESYSTEM_ALLOWED_ORIGINS", ",".join(default_allowed_origins))
        ),
    )


SETTINGS = load_settings()


def _transport_security() -> TransportSecuritySettings:
    return TransportSecuritySettings(
        enable_dns_rebinding_protection=True,
        allowed_hosts=SETTINGS.allowed_hosts,
        allowed_origins=SETTINGS.allowed_origins,
    )


READ_ONLY_MCP = FastMCP(
    "filesystem",
    host=SETTINGS.host,
    stateless_http=True,
    json_response=True,
    streamable_http_path="/",
    transport_security=_transport_security(),
)

READ_WRITE_MCP = FastMCP(
    "filesystem",
    host=SETTINGS.host,
    stateless_http=True,
    json_response=True,
    streamable_http_path="/",
    transport_security=_transport_security(),
)


def _request_from_context(context: Context | None) -> Any | None:
    if context is None:
        return None
    return context.request_context.request


def _header_or_query(context: Context | None, header_name: str, query_name: str) -> str:
    request = _request_from_context(context)
    if request is None:
        return ""
    header_value = request.headers.get(header_name, "").strip()
    if header_value:
        return header_value
    return request.query_params.get(query_name, "").strip()


def _resolve_workspace_root(context: Context | None) -> Path:
    explicit_root = _header_or_query(
        context,
        SETTINGS.workspace_root_header,
        SETTINGS.workspace_root_query_param,
    )
    if explicit_root:
        candidate = Path(explicit_root).resolve()
    else:
        workspace_name = (
            _header_or_query(
                context,
                SETTINGS.workspace_name_header,
                SETTINGS.workspace_name_query_param,
            )
            or SETTINGS.default_workspace_name
        ).strip()
        if workspace_name:
            if workspace_name not in SETTINGS.workspace_map:
                known_names = ", ".join(sorted(SETTINGS.workspace_map))
                raise ValueError(
                    f"unknown workspace_name '{workspace_name}'. Known workspaces: {known_names}"
                )
            candidate = SETTINGS.workspace_map[workspace_name]
        elif SETTINGS.default_workspace_root:
            candidate = Path(SETTINGS.default_workspace_root).resolve()
        else:
            raise ValueError(
                "workspace selection is required via x-workspace-root or x-workspace-name"
            )

    if not candidate.is_absolute():
        raise ValueError("workspace root must be an absolute path")
    if not candidate.exists():
        raise ValueError(f"workspace root does not exist: {candidate}")
    if SETTINGS.allowed_workspace_roots and not any(
        candidate == root or root in candidate.parents
        for root in SETTINGS.allowed_workspace_roots
    ):
        allowed = ", ".join(str(root) for root in SETTINGS.allowed_workspace_roots)
        raise ValueError(f"workspace root must stay within the configured allowed roots: {allowed}")
    return candidate


def _resolve_access_mode(context: Context | None) -> str:
    requested = _header_or_query(
        context,
        SETTINGS.access_header,
        SETTINGS.access_query_param,
    )
    return _normalize_access_mode(requested or SETTINGS.default_access_mode)


def _resolve_path(workspace_root: Path, raw_path: str) -> Path:
    candidate = raw_path.strip()
    if not candidate:
        raise ValueError("path must not be empty")
    requested = Path(candidate)
    resolved = requested.resolve() if requested.is_absolute() else (workspace_root / requested).resolve()
    if resolved != workspace_root and workspace_root not in resolved.parents:
        raise ValueError("path must stay within the selected workspace root")
    return resolved


def _relative_path(workspace_root: Path, target: Path) -> str:
    try:
        return target.relative_to(workspace_root).as_posix() or "."
    except ValueError:
        return str(target)


def _ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def _file_info(path: Path) -> dict[str, Any]:
    stats = path.stat()
    return {
        "path": str(path),
        "type": "directory" if path.is_dir() else "file",
        "size": stats.st_size,
        "created_at": _iso_timestamp(stats.st_ctime),
        "modified_at": _iso_timestamp(stats.st_mtime),
        "accessed_at": _iso_timestamp(stats.st_atime),
        "mode": oct(stats.st_mode & 0o777),
        "is_symlink": path.is_symlink(),
    }


def _tree(path: Path) -> dict[str, Any]:
    node: dict[str, Any] = {
        "name": path.name or str(path),
        "path": str(path),
        "type": "directory" if path.is_dir() else "file",
    }
    if path.is_dir():
        node["children"] = [_tree(child) for child in sorted(path.iterdir(), key=lambda entry: entry.name)]
    return node


def _filtered_matches(base: Path, pattern: str, exclude_patterns: list[str]) -> list[str]:
    matches: list[str] = []
    for candidate in base.glob(pattern):
        resolved = candidate.resolve()
        relative = _relative_path(base, resolved)
        if any(fnmatch.fnmatch(relative, exclude) for exclude in exclude_patterns):
            continue
        matches.append(str(resolved))
    return sorted(set(matches))


def _require_write_access(context: Context | None) -> None:
    if _resolve_access_mode(context) != "read-write":
        raise ValueError("write operations require x-mcp-filesystem-access: read-write")


def register_shared_tools(server: FastMCP) -> None:
    @server.tool()
    def server_info(ctx: Context | None = None) -> dict[str, Any]:
        """Return request scoping and policy details for this filesystem server."""
        requested_workspace_root = _header_or_query(
            ctx,
            SETTINGS.workspace_root_header,
            SETTINGS.workspace_root_query_param,
        )
        requested_workspace_name = _header_or_query(
            ctx,
            SETTINGS.workspace_name_header,
            SETTINGS.workspace_name_query_param,
        )
        requested_access_mode = _header_or_query(
            ctx,
            SETTINGS.access_header,
            SETTINGS.access_query_param,
        )
        resolved_workspace_root = ""
        workspace_error = ""
        try:
            resolved_workspace_root = str(_resolve_workspace_root(ctx))
        except ValueError as exc:
            workspace_error = str(exc)

        return {
            "allowed_workspace_roots": [str(root) for root in SETTINGS.allowed_workspace_roots],
            "workspace_names": {name: str(path) for name, path in SETTINGS.workspace_map.items()},
            "default_workspace_root": SETTINGS.default_workspace_root,
            "default_workspace_name": SETTINGS.default_workspace_name,
            "workspace_root_header": SETTINGS.workspace_root_header,
            "workspace_name_header": SETTINGS.workspace_name_header,
            "access_header": SETTINGS.access_header,
            "default_access_mode": SETTINGS.default_access_mode,
            "requested_workspace_root": requested_workspace_root,
            "requested_workspace_name": requested_workspace_name,
            "requested_access_mode": requested_access_mode,
            "resolved_workspace_root": resolved_workspace_root,
            "workspace_error": workspace_error,
        }

    @server.tool()
    def list_allowed_directories(ctx: Context | None = None) -> list[str]:
        """List the current workspace root selected for this request."""
        return [str(_resolve_workspace_root(ctx))]

    @server.tool()
    def read_text_file(
        path: str = Field(description="Path to the file to read."),
        head: int | None = Field(default=None, description="Return only the first N lines."),
        tail: int | None = Field(default=None, description="Return only the last N lines."),
        ctx: Context | None = None,
    ) -> str:
        """Read the complete contents of a file from the current workspace as text."""
        if head is not None and tail is not None:
            raise ValueError("head and tail cannot both be set")
        workspace_root = _resolve_workspace_root(ctx)
        target = _resolve_path(workspace_root, path)
        text = target.read_text(encoding="utf-8")
        lines = text.splitlines()
        if head is not None:
            return "\n".join(lines[:head])
        if tail is not None:
            return "\n".join(lines[-tail:])
        return text

    @server.tool()
    def read_multiple_files(
        paths: list[str] = Field(description="Paths to read from the current workspace."),
        ctx: Context | None = None,
    ) -> list[dict[str, Any]]:
        """Read multiple files without failing the whole request when one read fails."""
        workspace_root = _resolve_workspace_root(ctx)
        results: list[dict[str, Any]] = []
        for raw_path in paths:
            try:
                target = _resolve_path(workspace_root, raw_path)
                results.append({"path": str(target), "content": target.read_text(encoding="utf-8")})
            except Exception as exc:  # noqa: BLE001
                results.append({"path": raw_path, "error": str(exc)})
        return results

    @server.tool()
    def read_media_file(
        path: str = Field(description="Path to an image or audio file."),
        ctx: Context | None = None,
    ) -> dict[str, str]:
        """Read an image or audio file and return base64-encoded contents."""
        workspace_root = _resolve_workspace_root(ctx)
        target = _resolve_path(workspace_root, path)
        mime_type, _ = mimetypes.guess_type(str(target))
        return {
            "path": str(target),
            "mime_type": mime_type or "application/octet-stream",
            "data": base64.b64encode(target.read_bytes()).decode("ascii"),
        }

    @server.tool()
    def list_directory(
        path: str = Field(description="Directory path to list."),
        ctx: Context | None = None,
    ) -> str:
        """List files and directories with simple [FILE]/[DIR] prefixes."""
        workspace_root = _resolve_workspace_root(ctx)
        target = _resolve_path(workspace_root, path)
        if not target.is_dir():
            raise ValueError(f"path is not a directory: {target}")
        lines = []
        for entry in sorted(target.iterdir(), key=lambda item: item.name):
            prefix = "[DIR]" if entry.is_dir() else "[FILE]"
            lines.append(f"{prefix} {entry.name}")
        return "\n".join(lines)

    @server.tool()
    def list_directory_with_sizes(
        path: str = Field(description="Directory path to list."),
        sortBy: str = Field(default="name", description="Sort entries by name or size."),
        ctx: Context | None = None,
    ) -> str:
        """List files and directories with sizes for files and summary counts."""
        workspace_root = _resolve_workspace_root(ctx)
        target = _resolve_path(workspace_root, path)
        if not target.is_dir():
            raise ValueError(f"path is not a directory: {target}")
        entries = list(target.iterdir())
        if sortBy == "size":
            entries.sort(key=lambda item: (0 if item.is_file() else 1, item.stat().st_size, item.name))
        else:
            entries.sort(key=lambda item: item.name)
        files = 0
        directories = 0
        total_size = 0
        lines = []
        for entry in entries:
            if entry.is_dir():
                directories += 1
                lines.append(f"[DIR]  {entry.name}")
                continue
            size = entry.stat().st_size
            files += 1
            total_size += size
            lines.append(f"[FILE] {entry.name} ({size} bytes)")
        lines.append(f"Summary: {files} files, {directories} directories, {total_size} bytes")
        return "\n".join(lines)

    @server.tool()
    def directory_tree(
        path: str = Field(description="Starting directory."),
        excludePatterns: list[str] | None = Field(
            default=None,
            description="Glob patterns to exclude from the tree.",
        ),
        ctx: Context | None = None,
    ) -> dict[str, Any]:
        """Return a recursive JSON-style tree for the selected directory."""
        workspace_root = _resolve_workspace_root(ctx)
        target = _resolve_path(workspace_root, path)
        if not target.is_dir():
            raise ValueError(f"path is not a directory: {target}")
        exclude_patterns = excludePatterns or []

        def build(current: Path) -> dict[str, Any]:
            relative = _relative_path(target, current)
            if relative != "." and any(fnmatch.fnmatch(relative, pattern) for pattern in exclude_patterns):
                return {}
            node = {
                "name": current.name or str(current),
                "type": "directory" if current.is_dir() else "file",
            }
            if current.is_dir():
                children = [
                    build(child)
                    for child in sorted(current.iterdir(), key=lambda item: item.name)
                ]
                node["children"] = [child for child in children if child]
            return node

        return build(target)

    @server.tool()
    def get_file_info(
        path: str = Field(description="Path to inspect."),
        ctx: Context | None = None,
    ) -> dict[str, Any]:
        """Return metadata about a file or directory."""
        workspace_root = _resolve_workspace_root(ctx)
        target = _resolve_path(workspace_root, path)
        return _file_info(target)

    @server.tool()
    def search_files(
        path: str = Field(description="Starting directory for the search."),
        pattern: str = Field(description="Glob pattern relative to the starting directory."),
        excludePatterns: list[str] | None = Field(
            default=None,
            description="Glob patterns to exclude from the results.",
        ),
        ctx: Context | None = None,
    ) -> list[str]:
        """Search for files and directories matching a glob pattern."""
        workspace_root = _resolve_workspace_root(ctx)
        base = _resolve_path(workspace_root, path)
        if not base.is_dir():
            raise ValueError(f"path is not a directory: {base}")
        return _filtered_matches(base, pattern, excludePatterns or [])


def register_write_tools(server: FastMCP) -> None:
    @server.tool()
    def create_directory(
        path: str = Field(description="Directory path to create."),
        ctx: Context | None = None,
    ) -> dict[str, str]:
        """Create a directory and any missing parents within the selected workspace."""
        _require_write_access(ctx)
        workspace_root = _resolve_workspace_root(ctx)
        target = _resolve_path(workspace_root, path)
        target.mkdir(parents=True, exist_ok=True)
        return {"status": "created", "path": str(target)}

    @server.tool()
    def write_file(
        path: str = Field(description="File path to create or replace."),
        content: str = Field(description="Complete replacement file contents."),
        ctx: Context | None = None,
    ) -> dict[str, Any]:
        """Write a full text file within the selected workspace."""
        _require_write_access(ctx)
        workspace_root = _resolve_workspace_root(ctx)
        target = _resolve_path(workspace_root, path)
        _ensure_parent(target)
        target.write_text(content, encoding="utf-8")
        return {"status": "written", "path": str(target), "bytes": len(content.encode("utf-8"))}

    @server.tool()
    def edit_file(
        path: str = Field(description="File path to edit."),
        edits: list[dict[str, str]] = Field(
            description="Edit operations with oldText and newText fields.",
        ),
        dryRun: bool = Field(
            default=False,
            description="Preview the changes without writing them to disk.",
        ),
        ctx: Context | None = None,
    ) -> dict[str, Any]:
        """Apply ordered exact-text replacements and return a unified diff."""
        _require_write_access(ctx)
        workspace_root = _resolve_workspace_root(ctx)
        target = _resolve_path(workspace_root, path)
        original = target.read_text(encoding="utf-8")
        updated = original
        replacements: list[dict[str, Any]] = []
        for edit in edits:
            old_text = edit.get("oldText", "")
            new_text = edit.get("newText", "")
            if not old_text:
                raise ValueError("each edit must include oldText")
            if old_text not in updated:
                raise ValueError(f"oldText not found in {target}: {old_text!r}")
            updated = updated.replace(old_text, new_text, 1)
            replacements.append({"oldText": old_text, "newText": new_text})

        diff = "".join(
            difflib.unified_diff(
                original.splitlines(keepends=True),
                updated.splitlines(keepends=True),
                fromfile=str(target),
                tofile=str(target),
            )
        )
        if not dryRun and updated != original:
            target.write_text(updated, encoding="utf-8")
        return {
            "status": "preview" if dryRun else "applied",
            "path": str(target),
            "changed": updated != original,
            "diff": diff,
            "edits": replacements,
        }

    @server.tool()
    def move_file(
        source: str = Field(description="Source path to move."),
        destination: str = Field(description="Destination path."),
        ctx: Context | None = None,
    ) -> dict[str, str]:
        """Move or rename a file or directory within the selected workspace."""
        _require_write_access(ctx)
        workspace_root = _resolve_workspace_root(ctx)
        source_path = _resolve_path(workspace_root, source)
        destination_path = _resolve_path(workspace_root, destination)
        if destination_path.exists():
            raise ValueError(f"destination already exists: {destination_path}")
        _ensure_parent(destination_path)
        shutil.move(str(source_path), str(destination_path))
        return {"status": "moved", "source": str(source_path), "destination": str(destination_path)}


register_shared_tools(READ_ONLY_MCP)
register_shared_tools(READ_WRITE_MCP)
register_write_tools(READ_WRITE_MCP)


class HeaderScopedMCPApp:
    def __init__(self, read_only_app: Any, read_write_app: Any) -> None:
        self.read_only_app = read_only_app
        self.read_write_app = read_write_app

    async def __call__(self, scope: dict[str, Any], receive: Any, send: Any) -> None:
        if scope["type"] != "http":
            await self.read_only_app(scope, receive, send)
            return
        headers = {
            key.decode("latin-1").lower(): value.decode("latin-1")
            for key, value in scope.get("headers", [])
        }
        query_params = parse_qs(scope.get("query_string", b"").decode("utf-8"))
        raw_access_mode = headers.get(
            SETTINGS.access_header.lower(),
            query_params.get(SETTINGS.access_query_param, [""])[0],
        )
        try:
            access_mode = _normalize_access_mode(raw_access_mode or SETTINGS.default_access_mode)
        except ValueError as exc:
            response = JSONResponse({"error": str(exc)}, status_code=400)
            await response(scope, receive, send)
            return
        selected = self.read_write_app if access_mode == "read-write" else self.read_only_app
        await selected(scope, receive, send)


async def healthz(_: Any) -> PlainTextResponse:
    return PlainTextResponse("ok")


def build_asgi_app() -> Starlette:
    scoped_app = HeaderScopedMCPApp(
        READ_ONLY_MCP.streamable_http_app(),
        READ_WRITE_MCP.streamable_http_app(),
    )

    @contextlib.asynccontextmanager
    async def lifespan(_: Starlette):
        async with contextlib.AsyncExitStack() as stack:
            await stack.enter_async_context(READ_ONLY_MCP.session_manager.run())
            await stack.enter_async_context(READ_WRITE_MCP.session_manager.run())
            yield

    return Starlette(
        routes=[
            Route("/healthz", healthz),
            Mount(SETTINGS.http_path, app=scoped_app),
        ],
        lifespan=lifespan,
    )


def main() -> None:
    app = build_asgi_app()
    uvicorn.run(app, host=SETTINGS.host, port=SETTINGS.port)


if __name__ == "__main__":
    main()
