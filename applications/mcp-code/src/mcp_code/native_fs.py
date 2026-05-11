"""Filesystem MCP tools implemented in Python (parity with @modelcontextprotocol/server-filesystem)."""

from __future__ import annotations

import base64
import json
import mimetypes
import os
import shutil
from datetime import datetime
from difflib import unified_diff
from fnmatch import fnmatch
from pathlib import Path
from typing import Any

import mcp.types as types
from mcp.types import TextContent, Tool

_MEDIA_EXT = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".webp": "image/webp",
    ".bmp": "image/bmp",
    ".svg": "image/svg+xml",
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
    ".ogg": "audio/ogg",
    ".flac": "audio/flac",
}


def _fmt_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024:
            return f"{n:.1f}{unit}" if unit != "B" else f"{n}B"
        n /= 1024
    return f"{n:.1f}PB"


def validate_workspace_path(workspace: Path, user_path: str) -> Path:
    w = workspace.resolve()
    p = Path(user_path).expanduser()
    if not p.is_absolute():
        p = (w / p).resolve()
    else:
        p = p.resolve()
    try:
        p.relative_to(w)
    except ValueError as exc:
        raise ValueError(f"Path outside allowed workspace: {user_path}") from exc
    return p


def _text_result(text: str) -> types.CallToolResult:
    return types.CallToolResult(content=[TextContent(type="text", text=text)])


def _schema(
    properties: dict[str, Any],
    required: list[str] | None = None,
    *,
    allow_empty: bool = False,
) -> dict[str, Any]:
    s: dict[str, Any] = {"type": "object", "properties": properties}
    if required:
        s["required"] = required
    elif not allow_empty:
        s["required"] = list(properties.keys())
    return s


FS_TOOLS: list[Tool] = [
    Tool(
        name="read_file",
        description="Read the complete contents of a file as text. DEPRECATED: Use read_text_file instead.",
        inputSchema=_schema(
            {
                "path": {"type": "string"},
                "tail": {"type": "integer", "description": "If set, return only last N lines"},
                "head": {"type": "integer", "description": "If set, return only first N lines"},
            },
            ["path"],
        ),
    ),
    Tool(
        name="read_text_file",
        description="Read file contents as text; optional head/tail line limits.",
        inputSchema=_schema(
            {
                "path": {"type": "string"},
                "tail": {"type": "integer"},
                "head": {"type": "integer"},
            },
            ["path"],
        ),
    ),
    Tool(
        name="read_media_file",
        description="Read image or audio file; returns base64 + MIME.",
        inputSchema=_schema({"path": {"type": "string"}}, ["path"]),
    ),
    Tool(
        name="read_multiple_files",
        description="Read multiple files; errors are reported inline per path.",
        inputSchema=_schema(
            {
                "paths": {
                    "type": "array",
                    "items": {"type": "string"},
                    "minItems": 1,
                }
            },
            ["paths"],
        ),
    ),
    Tool(
        name="write_file",
        description="Create or overwrite a file with text content.",
        inputSchema=_schema({"path": {"type": "string"}, "content": {"type": "string"}}, ["path", "content"]),
    ),
    Tool(
        name="edit_file",
        description="Apply exact text replacements; optional dry-run diff.",
        inputSchema=_schema(
            {
                "path": {"type": "string"},
                "edits": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "oldText": {"type": "string"},
                            "newText": {"type": "string"},
                        },
                        "required": ["oldText", "newText"],
                    },
                },
                "dryRun": {"type": "boolean", "default": False},
            },
            ["path", "edits"],
        ),
    ),
    Tool(
        name="create_directory",
        description="Create directory (and parents).",
        inputSchema=_schema({"path": {"type": "string"}}, ["path"]),
    ),
    Tool(
        name="list_directory",
        description="List directory with [FILE]/[DIR] prefixes.",
        inputSchema=_schema({"path": {"type": "string"}}, ["path"]),
    ),
    Tool(
        name="list_directory_with_sizes",
        description="List directory with sizes; sortBy name or size.",
        inputSchema=_schema(
            {
                "path": {"type": "string"},
                "sortBy": {"type": "string", "enum": ["name", "size"], "default": "name"},
            },
            ["path"],
        ),
    ),
    Tool(
        name="directory_tree",
        description="Recursive JSON tree of files and directories.",
        inputSchema=_schema(
            {
                "path": {"type": "string"},
                "excludePatterns": {"type": "array", "items": {"type": "string"}, "default": []},
            },
            ["path"],
        ),
    ),
    Tool(
        name="move_file",
        description="Move or rename within workspace.",
        inputSchema=_schema(
            {"source": {"type": "string"}, "destination": {"type": "string"}},
            ["source", "destination"],
        ),
    ),
    Tool(
        name="search_files",
        description="Glob search under path (e.g. **/*.py).",
        inputSchema=_schema(
            {
                "path": {"type": "string"},
                "pattern": {"type": "string"},
                "excludePatterns": {"type": "array", "items": {"type": "string"}, "default": []},
            },
            ["path", "pattern"],
        ),
    ),
    Tool(
        name="get_file_info",
        description="Metadata (size, mtime, mode, type) for a path.",
        inputSchema=_schema({"path": {"type": "string"}}, ["path"]),
    ),
    Tool(
        name="list_allowed_directories",
        description="Lists allowed workspace roots.",
        inputSchema=_schema({}, [], allow_empty=True),
    ),
]


def _read_text_slice(content: str, head: int | None, tail: int | None) -> str:
    if head and tail:
        raise ValueError("Cannot specify both head and tail")
    lines = content.splitlines(keepends=True)
    if tail:
        lines = lines[-tail:]
    elif head:
        lines = lines[:head]
    return "".join(lines)


def _should_exclude(relpath: str, patterns: list[str]) -> bool:
    for pat in patterns:
        if "*" in pat or "?" in pat or "[" in pat:
            if fnmatch(relpath, pat) or fnmatch(relpath, f"**/{pat}") or fnmatch(relpath, f"**/{pat}/**"):
                return True
        else:
            if pat in relpath or relpath.startswith(pat + os.sep) or relpath == pat:
                return True
    return False


async def call_fs_tool(
    name: str, arguments: dict[str, Any], *, workspace: Path
) -> types.CallToolResult | None:
    if name not in {t.name for t in FS_TOOLS}:
        return None

    match name:
        case "read_file" | "read_text_file":
            p = validate_workspace_path(workspace, arguments["path"])
            if not p.is_file():
                raise ValueError(f"Not a file: {p}")
            text = p.read_text(encoding="utf-8", errors="replace")
            text = _read_text_slice(text, arguments.get("head"), arguments.get("tail"))
            return _text_result(text)

        case "read_media_file":
            p = validate_workspace_path(workspace, arguments["path"])
            if not p.is_file():
                raise ValueError(f"Not a file: {p}")
            ext = p.suffix.lower()
            mime = _MEDIA_EXT.get(ext) or (mimetypes.guess_type(str(p))[0] or "application/octet-stream")
            raw = p.read_bytes()
            b64 = base64.standard_b64encode(raw).decode("ascii")
            kind: str = (
                "image"
                if mime.startswith("image/")
                else "audio"
                if mime.startswith("audio/")
                else "blob"
            )
            item = {"type": kind, "data": b64, "mimeType": mime}
            return _text_result(json.dumps({"content": [item]}))

        case "read_multiple_files":
            parts: list[str] = []
            for fp in arguments["paths"]:
                try:
                    p = validate_workspace_path(workspace, fp)
                    if not p.is_file():
                        parts.append(f"{fp}: Error - not a file")
                        continue
                    content = p.read_text(encoding="utf-8", errors="replace")
                    parts.append(f"{fp}:\n{content}\n")
                except Exception as e:
                    parts.append(f"{fp}: Error - {e}")
            return _text_result("\n---\n".join(parts))

        case "write_file":
            p = validate_workspace_path(workspace, arguments["path"])
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(arguments["content"], encoding="utf-8")
            return _text_result(f"Successfully wrote to {arguments['path']}")

        case "edit_file":
            p = validate_workspace_path(workspace, arguments["path"])
            if not p.is_file():
                raise ValueError(f"Not a file: {p}")
            original = p.read_text(encoding="utf-8", errors="replace")
            text = original
            edits = arguments["edits"]
            dry = bool(arguments.get("dryRun", False))
            for ed in edits:
                old, new = ed["oldText"], ed["newText"]
                if old not in text:
                    raise ValueError(f"oldText not found in file (unique match required): {old[:80]!r}...")
                text = text.replace(old, new, 1)
            diff_lines = list(
                unified_diff(
                    original.splitlines(keepends=True),
                    text.splitlines(keepends=True),
                    fromfile="a/" + p.name,
                    tofile="b/" + p.name,
                )
            )
            diff_text = "".join(diff_lines) or "(no changes)"
            if dry:
                return _text_result(f"Dry run diff:\n{diff_text}")
            p.write_text(text, encoding="utf-8")
            return _text_result(f"Applied edits.\n{diff_text}")

        case "create_directory":
            p = validate_workspace_path(workspace, arguments["path"])
            p.mkdir(parents=True, exist_ok=True)
            return _text_result(f"Successfully created directory {arguments['path']}")

        case "list_directory":
            p = validate_workspace_path(workspace, arguments["path"])
            if not p.is_dir():
                raise ValueError(f"Not a directory: {p}")
            lines = [
                f"{'[DIR]' if x.is_dir() else '[FILE]'} {x.name}"
                for x in sorted(p.iterdir(), key=lambda x: x.name.lower())
            ]
            return _text_result("\n".join(lines))

        case "list_directory_with_sizes":
            p = validate_workspace_path(workspace, arguments["path"])
            if not p.is_dir():
                raise ValueError(f"Not a directory: {p}")
            sort_by = arguments.get("sortBy", "name")
            entries: list[tuple[str, bool, int]] = []
            for x in p.iterdir():
                try:
                    st = x.stat()
                    sz = 0 if x.is_dir() else st.st_size
                except OSError:
                    sz = 0
                entries.append((x.name, x.is_dir(), sz))
            if sort_by == "size":
                entries.sort(key=lambda e: (-e[2], e[0].lower()))
            else:
                entries.sort(key=lambda e: e[0].lower())
            rows = [
                f"{'[DIR]' if d else '[FILE]'} {name.ljust(30)} {'' if d else _fmt_size(sz).rjust(10)}"
                for name, d, sz in entries
            ]
            files = sum(1 for _, d, _ in entries if not d)
            dirs = sum(1 for _, d, _ in entries if d)
            total_sz = sum(sz for _, d, sz in entries if not d)
            summary = ["", f"Total: {files} files, {dirs} directories", f"Combined size: {_fmt_size(total_sz)}"]
            return _text_result("\n".join(rows + summary))

        case "directory_tree":
            root = validate_workspace_path(workspace, arguments["path"])
            if not root.is_dir():
                raise ValueError(f"Not a directory: {root}")
            excludes = list(arguments.get("excludePatterns") or [])

            def build(cur: Path) -> list[dict[str, Any]]:
                out: list[dict[str, Any]] = []
                for entry in sorted(cur.iterdir(), key=lambda x: x.name.lower()):
                    rel = str(entry.relative_to(root))
                    if _should_exclude(rel, excludes):
                        continue
                    if entry.is_dir():
                        out.append(
                            {
                                "name": entry.name,
                                "type": "directory",
                                "children": build(entry),
                            }
                        )
                    else:
                        out.append({"name": entry.name, "type": "file"})
                return out

            tree = build(root)
            return _text_result(json.dumps(tree, indent=2))

        case "move_file":
            src = validate_workspace_path(workspace, arguments["source"])
            dst = validate_workspace_path(workspace, arguments["destination"])
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(src), str(dst))
            return _text_result(f"Successfully moved {arguments['source']} to {arguments['destination']}")

        case "search_files":
            base = validate_workspace_path(workspace, arguments["path"])
            if not base.is_dir():
                raise ValueError(f"Not a directory: {base}")
            pattern = arguments["pattern"]
            excludes = list(arguments.get("excludePatterns") or [])
            hits: list[str] = []
            if "**" in pattern:
                iterator = base.glob(pattern)
            else:
                iterator = base.rglob(pattern)
            for path in iterator:
                try:
                    rel = str(path.relative_to(workspace.resolve()))
                except ValueError:
                    rel = str(path)
                if _should_exclude(rel, excludes):
                    continue
                hits.append(str(path))
            return _text_result("\n".join(sorted(set(hits))) if hits else "No matches found")

        case "get_file_info":
            p = validate_workspace_path(workspace, arguments["path"])
            st = p.stat()
            info = {
                "path": str(p),
                "size": st.st_size,
                "isDirectory": p.is_dir(),
                "isFile": p.is_file(),
                "mtime": datetime.fromtimestamp(st.st_mtime).isoformat(),
                "mode": oct(st.st_mode),
            }
            return _text_result("\n".join(f"{k}: {v}" for k, v in info.items()))

        case "list_allowed_directories":
            return _text_result(f"Allowed directories:\n{workspace.resolve()}")

        case _:
            return None
