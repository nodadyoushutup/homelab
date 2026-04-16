#!/usr/bin/env python3
"""Repo-local ast-grep MCP server.

Adapted from the upstream ast-grep MCP server:
https://github.com/ast-grep/ast-grep-mcp
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path
from typing import Any, Literal

import yaml
from mcp.server.fastmcp import FastMCP
from pydantic import Field

DEFAULT_CONFIG_PATH = "/opt/ast-grep-config/sgconfig.yml"
DEFAULT_PROJECT_ROOT = os.environ.get("AST_GREP_DEFAULT_PROJECT_ROOT", "")
ALLOWED_ROOTS = [
    Path(root).resolve()
    for root in os.environ.get("AST_GREP_ALLOWED_ROOTS", DEFAULT_PROJECT_ROOT).split(":")
    if root.strip()
]

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

CONFIG_PATH = DEFAULT_CONFIG_PATH

mcp = FastMCP(
    "ast-grep",
    stateless_http=True,
    json_response=True,
    streamable_http_path="/mcp",
)

DumpFormat = Literal["pattern", "cst", "ast"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="ast-grep MCP server for the homelab repo",
    )
    parser.add_argument(
        "--config",
        default=os.environ.get("AST_GREP_CONFIG", DEFAULT_CONFIG_PATH),
        help="Path to sgconfig.yml used for language globs and custom parsers.",
    )
    parser.add_argument(
        "--transport",
        choices=["stdio", "streamable-http"],
        default="stdio",
        help="Transport to serve.",
    )
    parser.add_argument(
        "--host",
        default=os.environ.get("AST_GREP_HOST", "127.0.0.1"),
        help="Host for streamable-http transport.",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("AST_GREP_PORT", "8096")),
        help="Port for streamable-http transport.",
    )
    parser.add_argument(
        "--path",
        default=os.environ.get("MCP_HTTP_PATH", "/mcp"),
        help="HTTP path for streamable-http transport.",
    )
    return parser.parse_args()


def ensure_config(path: str) -> str:
    if not path:
        return ""
    if not os.path.exists(path):
        raise SystemExit(f"Config file does not exist: {path}")
    return path


def load_custom_languages() -> list[str]:
    if not CONFIG_PATH:
        return []
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as handle:
            data = yaml.safe_load(handle) or {}
    except OSError:
        return []
    custom_languages = data.get("customLanguages") or {}
    return sorted(custom_languages.keys())


def get_supported_languages() -> list[str]:
    return sorted(set(BUILTIN_LANGUAGES + load_custom_languages()))


def resolve_project_folder(project_folder: str | None) -> str:
    candidate = (project_folder or DEFAULT_PROJECT_ROOT).strip()
    if not candidate:
        raise ValueError("project_folder is required when AST_GREP_DEFAULT_PROJECT_ROOT is not set.")
    folder = Path(candidate).resolve()
    if not folder.is_absolute():
        raise ValueError("project_folder must be an absolute path.")
    if not folder.exists():
        raise ValueError(f"project_folder does not exist: {folder}")
    if ALLOWED_ROOTS and not any(folder == root or root in folder.parents for root in ALLOWED_ROOTS):
        allowed = ", ".join(str(root) for root in ALLOWED_ROOTS)
        raise ValueError(f"project_folder must stay within the configured allowed roots: {allowed}")
    return str(folder)


def run_command(args: list[str], input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            input=input_text,
            text=True,
            check=False,
        )
    except FileNotFoundError as exc:
        raise RuntimeError(f"Command not found: {args[0]}") from exc
    if result.returncode == 0:
        return result
    if result.returncode == 1:
        stdout_stripped = result.stdout.strip()
        if stdout_stripped in ("", "[]") or stdout_stripped.startswith("["):
            return result
        if "--json" not in args and stdout_stripped == "":
            return result
    stderr = result.stderr.strip() or "(no error output)"
    raise RuntimeError(f"Command {' '.join(args)} failed with exit code {result.returncode}: {stderr}")


def run_ast_grep(command: str, args: list[str], input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    full_args = ["ast-grep", command]
    if CONFIG_PATH:
        full_args.extend(["--config", CONFIG_PATH])
    full_args.extend(args)
    return run_command(full_args, input_text=input_text)


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


@mcp.tool()
def server_info() -> dict[str, Any]:
    """Return server defaults, path restrictions, and supported languages."""
    return {
        "default_project_root": DEFAULT_PROJECT_ROOT,
        "allowed_roots": [str(root) for root in ALLOWED_ROOTS],
        "config_path": CONFIG_PATH,
        "supported_languages": get_supported_languages(),
    }


@mcp.tool()
def dump_syntax_tree(
    code: str = Field(description="Code snippet to inspect."),
    language: str = Field(description="Language alias understood by ast-grep."),
    format: DumpFormat = Field(default="cst", description="One of: pattern, cst, ast."),
) -> str:
    """Dump ast-grep syntax output for a code snippet or pattern."""
    result = run_ast_grep(
        "run",
        ["--pattern", code, "--lang", language, f"--debug-query={format}"],
    )
    return result.stderr.strip()


@mcp.tool()
def test_match_code_rule(
    code: str = Field(description="Code snippet to test."),
    yaml: str = Field(
        description="Inline ast-grep YAML rule with id, language, and rule fields.",
    ),
) -> list[dict[str, Any]]:
    """Test an ast-grep YAML rule against a code snippet."""
    result = run_ast_grep(
        "scan",
        ["--inline-rules", yaml, "--json", "--stdin"],
        input_text=code,
    )
    matches = json.loads(result.stdout.strip() or "[]")
    if not matches:
        raise ValueError("No matches found for the provided code and rule.")
    return matches


@mcp.tool()
def find_code(
    pattern: str = Field(description="ast-grep pattern to search for."),
    project_folder: str = Field(
        default="",
        description="Absolute project path. Leave empty to use the configured default repo path.",
    ),
    language: str = Field(
        default="",
        description="Optional language alias. Leave empty for ast-grep auto-detection.",
    ),
    max_results: int = Field(default=0, description="Maximum matches to return. 0 means unlimited."),
    output_format: str = Field(default="text", description="Either text or json."),
) -> str | list[dict[str, Any]]:
    """Search for code with an ast-grep pattern."""
    if output_format not in {"text", "json"}:
        raise ValueError("output_format must be either 'text' or 'json'.")
    target_root = resolve_project_folder(project_folder)
    args = ["--pattern", pattern]
    if language:
        args.extend(["--lang", language])
    result = run_ast_grep("run", args + ["--json", target_root])
    matches = json.loads(result.stdout.strip() or "[]")
    total_matches = len(matches)
    if max_results and total_matches > max_results:
        matches = matches[:max_results]
    if output_format == "json":
        return matches
    if not matches:
        return "No matches found"
    header = f"Found {len(matches)} matches"
    if max_results and total_matches > max_results:
        header += f" (showing first {max_results} of {total_matches})"
    return header + ":\n\n" + format_matches_as_text(matches)


@mcp.tool()
def find_code_by_rule(
    yaml: str = Field(
        description="Inline ast-grep YAML rule with id, language, and rule fields.",
    ),
    project_folder: str = Field(
        default="",
        description="Absolute project path. Leave empty to use the configured default repo path.",
    ),
    max_results: int = Field(default=0, description="Maximum matches to return. 0 means unlimited."),
    output_format: str = Field(default="text", description="Either text or json."),
) -> str | list[dict[str, Any]]:
    """Search for code with an ast-grep YAML rule."""
    if output_format not in {"text", "json"}:
        raise ValueError("output_format must be either 'text' or 'json'.")
    target_root = resolve_project_folder(project_folder)
    result = run_ast_grep("scan", ["--inline-rules", yaml, "--json", target_root])
    matches = json.loads(result.stdout.strip() or "[]")
    total_matches = len(matches)
    if max_results and total_matches > max_results:
        matches = matches[:max_results]
    if output_format == "json":
        return matches
    if not matches:
        return "No matches found"
    header = f"Found {len(matches)} matches"
    if max_results and total_matches > max_results:
        header += f" (showing first {max_results} of {total_matches})"
    return header + ":\n\n" + format_matches_as_text(matches)


def main() -> None:
    global CONFIG_PATH

    args = parse_args()
    CONFIG_PATH = ensure_config(args.config)

    if args.transport == "streamable-http":
        mcp.settings.host = args.host
        mcp.settings.port = args.port
        mcp.settings.streamable_http_path = args.path
        mcp.run(transport="streamable-http")
        return

    mcp.run()


if __name__ == "__main__":
    main()
