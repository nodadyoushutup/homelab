"""ast-grep MCP tools implemented natively (sg CLI), matching ast-grep-bundled/server.py."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Literal

import mcp.types as types
import yaml
from mcp.types import TextContent, Tool

DumpFormat = Literal["pattern", "cst", "ast"]

BUILTIN_LANGUAGES = [
    "bash",
    "c",
    "cpp",
    "csharp",
    "css",
    "elixir",
    "go",
    "haskell",
    "hcl",
    "html",
    "java",
    "javascript",
    "json",
    "kotlin",
    "lua",
    "nix",
    "php",
    "python",
    "ruby",
    "rust",
    "scala",
    "solidity",
    "swift",
    "tsx",
    "typescript",
    "yaml",
]

SG_BIN = os.environ.get("AST_GREP_CLI", "sg")


def _schema(props: dict[str, Any], required: list[str]) -> dict[str, Any]:
    return {"type": "object", "properties": props, "required": required}


AST_TOOLS: list[Tool] = [
    Tool(
        name="server_info",
        description="Return server defaults, path restrictions, and supported languages.",
        inputSchema=_schema({}, []),
    ),
    Tool(
        name="dump_syntax_tree",
        description="Dump ast-grep syntax output for a code snippet or pattern.",
        inputSchema=_schema(
            {
                "code": {"type": "string"},
                "language": {"type": "string"},
                "format": {"type": "string", "enum": ["pattern", "cst", "ast"], "default": "cst"},
            },
            ["code", "language"],
        ),
    ),
    Tool(
        name="test_match_code_rule",
        description="Test an ast-grep YAML rule against a code snippet.",
        inputSchema=_schema(
            {"code": {"type": "string"}, "yaml": {"type": "string"}},
            ["code", "yaml"],
        ),
    ),
    Tool(
        name="find_code",
        description="Search for code with an ast-grep pattern.",
        inputSchema=_schema(
            {
                "pattern": {"type": "string"},
                "project_folder": {"type": "string", "default": ""},
                "language": {"type": "string", "default": ""},
                "max_results": {"type": "integer", "default": 0},
                "output_format": {"type": "string", "enum": ["text", "json"], "default": "text"},
            },
            ["pattern"],
        ),
    ),
    Tool(
        name="find_code_by_rule",
        description="Search for code with an ast-grep YAML rule.",
        inputSchema=_schema(
            {
                "yaml": {"type": "string"},
                "project_folder": {"type": "string", "default": ""},
                "max_results": {"type": "integer", "default": 0},
                "output_format": {"type": "string", "enum": ["text", "json"], "default": "text"},
            },
            ["yaml"],
        ),
    ),
]


def load_custom_languages(config_path: str) -> list[str]:
    if not config_path or not os.path.exists(config_path):
        return []
    try:
        with open(config_path, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except OSError:
        return []
    return sorted((data.get("customLanguages") or {}).keys())


def get_supported_languages(config_path: str) -> list[str]:
    return sorted(set(BUILTIN_LANGUAGES + load_custom_languages(config_path)))


def resolve_project_folder(
    project_folder: str,
    *,
    default_root: str,
    allowed_roots: list[Path],
) -> str:
    candidate = (project_folder or default_root).strip()
    if not candidate:
        raise ValueError("project_folder is required when default root is not set.")
    folder = Path(candidate).resolve()
    if not folder.is_absolute():
        raise ValueError("project_folder must be an absolute path.")
    if not folder.exists():
        raise ValueError(f"project_folder does not exist: {folder}")
    if allowed_roots and not any(folder == root or root in folder.parents for root in allowed_roots):
        allowed = ", ".join(str(root) for root in allowed_roots)
        raise ValueError(f"project_folder must stay within allowed roots: {allowed}")
    return str(folder)


def run_command(args: list[str], input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            args,
            capture_output=True,
            input=input_text,
            text=True,
            check=False,
        )
    except FileNotFoundError as exc:
        raise RuntimeError(f"Command not found: {args[0]}") from exc


def run_sg(command: str, args: list[str], config_path: str, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    full = [SG_BIN, command]
    if config_path:
        full.extend(["--config", config_path])
    full.extend(args)
    result = run_command(full, input_text=input_text)
    if result.returncode == 0:
        return result
    if result.returncode == 1:
        out = result.stdout.strip()
        if out in ("", "[]") or out.startswith("["):
            return result
        if "--json" not in args and out == "":
            return result
    err = result.stderr.strip() or "(no error output)"
    raise RuntimeError(f"{' '.join(full)} failed ({result.returncode}): {err}")


def format_matches_as_text(matches: list[dict[str, Any]]) -> str:
    blocks: list[str] = []
    for match in matches:
        file_path = match.get("file", "")
        start_line = match.get("range", {}).get("start", {}).get("line", 0) + 1
        end_line = match.get("range", {}).get("end", {}).get("line", 0) + 1
        match_text = match.get("text", "").rstrip()
        header = f"{file_path}:{start_line}" if start_line == end_line else f"{file_path}:{start_line}-{end_line}"
        blocks.append(f"{header}\n{match_text}")
    return "\n\n".join(blocks)


def _text_result(text: str) -> types.CallToolResult:
    return types.CallToolResult(content=[TextContent(type="text", text=text)])


def _json_result(data: Any) -> types.CallToolResult:
    return _text_result(json.dumps(data, indent=2))


async def call_ast_tool(
    name: str,
    arguments: dict[str, Any],
    *,
    workspace: Path,
    config_path: str,
) -> types.CallToolResult | None:
    if name not in {t.name for t in AST_TOOLS}:
        return None

    default_root = str(workspace.resolve())
    allowed = [workspace.resolve()]

    match name:
        case "server_info":
            effective = default_root
            err = ""
            try:
                effective = resolve_project_folder("", default_root=default_root, allowed_roots=allowed)
            except ValueError as e:
                err = str(e)
            return _json_result(
                {
                    "default_project_root": default_root,
                    "allowed_roots": [str(r) for r in allowed],
                    "config_path": config_path,
                    "effective_project_root": effective,
                    "workspace_root_error": err,
                    "supported_languages": get_supported_languages(config_path),
                }
            )

        case "dump_syntax_tree":
            code = arguments["code"]
            language = arguments["language"]
            fmt: DumpFormat = arguments.get("format", "cst")  # type: ignore[assignment]
            with tempfile.NamedTemporaryFile("w", suffix=f".{language}", delete=False) as handle:
                temp_path = handle.name
            try:
                result = run_sg(
                    "run",
                    ["--pattern", code, "--lang", language, f"--debug-query={fmt}", temp_path],
                    config_path,
                )
                return _text_result(result.stderr.strip())
            finally:
                try:
                    os.unlink(temp_path)
                except FileNotFoundError:
                    pass

        case "test_match_code_rule":
            code = arguments["code"]
            yml = arguments["yaml"]
            result = run_sg(
                "scan",
                ["--inline-rules", yml, "--json", "--stdin"],
                config_path,
                input_text=code,
            )
            matches = json.loads(result.stdout.strip() or "[]")
            if not matches:
                raise ValueError("No matches found for the provided code and rule.")
            return _json_result(matches)

        case "find_code":
            pattern = arguments["pattern"]
            target_root = resolve_project_folder(
                arguments.get("project_folder") or "",
                default_root=default_root,
                allowed_roots=allowed,
            )
            lang = (arguments.get("language") or "").strip()
            max_results = int(arguments.get("max_results") or 0)
            output_format = arguments.get("output_format", "text")
            args = ["--pattern", pattern]
            if lang:
                args.extend(["--lang", lang])
            result = run_sg("run", args + ["--json", target_root], config_path)
            matches = json.loads(result.stdout.strip() or "[]")
            total = len(matches)
            if max_results and total > max_results:
                matches = matches[:max_results]
            if output_format == "json":
                return _json_result(matches)
            if not matches:
                return _text_result("No matches found")
            header = f"Found {len(matches)} matches"
            if max_results and total > max_results:
                header += f" (showing first {max_results} of {total})"
            return _text_result(header + ":\n\n" + format_matches_as_text(matches))

        case "find_code_by_rule":
            yml = arguments["yaml"]
            target_root = resolve_project_folder(
                arguments.get("project_folder") or "",
                default_root=default_root,
                allowed_roots=allowed,
            )
            max_results = int(arguments.get("max_results") or 0)
            output_format = arguments.get("output_format", "text")
            result = run_sg("scan", ["--inline-rules", yml, "--json", target_root], config_path)
            matches = json.loads(result.stdout.strip() or "[]")
            total = len(matches)
            if max_results and total > max_results:
                matches = matches[:max_results]
            if output_format == "json":
                return _json_result(matches)
            if not matches:
                return _text_result("No matches found")
            header = f"Found {len(matches)} matches"
            if max_results and total > max_results:
                header += f" (showing first {max_results} of {total})"
            return _text_result(header + ":\n\n" + format_matches_as_text(matches))

        case _:
            return None
