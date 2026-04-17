#!/usr/bin/env python3
"""Sync Langflow external MCP servers from the repo-local Codex config.

This keeps Langflow's Settings > MCP Servers registry aligned with the
workspace-managed HTTP MCP endpoints defined in `.codex/config.toml`.

The sync intentionally:
- includes only `mcp_*` HTTP servers from the Codex config
- skips the `langflow` project MCP endpoint
- upserts missing or changed servers
- leaves unrelated Langflow-only MCP servers in place
"""

from __future__ import annotations

import argparse
import json
import sys
import tomllib
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


DEFAULT_LANGFLOW_URL = "https://langflow.nodadyoushutup.com"
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG_PATH = REPO_ROOT / ".codex" / "config.toml"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync Langflow MCP server registrations from .codex/config.toml."
    )
    parser.add_argument(
        "--base-url",
        default=DEFAULT_LANGFLOW_URL,
        help=f"Langflow base URL (default: {DEFAULT_LANGFLOW_URL})",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG_PATH,
        help=f"Path to the repo-local Codex config (default: {DEFAULT_CONFIG_PATH})",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply changes instead of printing the planned sync actions.",
    )
    return parser.parse_args()


def load_desired_servers(config_path: Path) -> dict[str, dict[str, Any]]:
    with config_path.open("rb") as handle:
        raw = tomllib.load(handle)

    desired: dict[str, dict[str, Any]] = {}
    servers = raw.get("mcp_servers", {})
    for name, entry in servers.items():
        if name == "langflow" or not name.startswith("mcp_"):
            continue
        if not isinstance(entry, dict):
            continue

        url = entry.get("url")
        if not isinstance(url, str) or not url.strip():
            continue

        desired[name] = {"url": url.strip()}

    return desired


def http_json(
    method: str,
    url: str,
    token: str | None = None,
    payload: dict[str, Any] | None = None,
) -> Any:
    body = None
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"

    request = urllib.request.Request(url, data=body, method=method, headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        content = response.read().decode("utf-8")
        return json.loads(content) if content else None


def auto_login(base_url: str) -> str:
    data = http_json("GET", f"{base_url.rstrip('/')}/api/v1/auto_login")
    token = data.get("access_token")
    if not isinstance(token, str) or not token:
        raise RuntimeError("Langflow auto_login did not return an access token")
    return token


def list_langflow_servers(base_url: str, token: str) -> dict[str, dict[str, Any]]:
    data = http_json(
        "GET",
        f"{base_url.rstrip('/')}/api/v2/mcp/servers?action_count=false",
        token=token,
    )
    servers: dict[str, dict[str, Any]] = {}
    for entry in data:
        name = entry.get("name")
        if isinstance(name, str) and name:
            servers[name] = entry
    return servers


def get_langflow_server(base_url: str, token: str, name: str) -> dict[str, Any] | None:
    quoted_name = urllib.parse.quote(name, safe="")
    url = f"{base_url.rstrip('/')}/api/v2/mcp/servers/{quoted_name}"
    try:
        return http_json("GET", url, token=token)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return None
        raise


def main() -> int:
    args = parse_args()
    desired = load_desired_servers(args.config)
    if not desired:
        print(f"No eligible mcp_* HTTP servers found in {args.config}", file=sys.stderr)
        return 1

    token = auto_login(args.base_url)
    current = list_langflow_servers(args.base_url, token)

    planned_create: list[str] = []
    planned_update: list[str] = []
    unchanged: list[str] = []

    for name, expected in desired.items():
        existing = get_langflow_server(args.base_url, token, name)
        if existing is None:
            planned_create.append(name)
            if args.apply:
                http_json(
                    "POST",
                    f"{args.base_url.rstrip('/')}/api/v2/mcp/servers/{urllib.parse.quote(name, safe='')}",
                    token=token,
                    payload=expected,
                )
            continue

        existing_url = existing.get("url")
        if existing_url != expected["url"]:
            planned_update.append(name)
            if args.apply:
                http_json(
                    "PATCH",
                    f"{args.base_url.rstrip('/')}/api/v2/mcp/servers/{urllib.parse.quote(name, safe='')}",
                    token=token,
                    payload=expected,
                )
        else:
            unchanged.append(name)

    extras = sorted(name for name in current if name not in desired)

    mode_label = "Applied" if args.apply else "Planned"
    print(f"{mode_label} Langflow MCP sync against {args.base_url.rstrip('/')}")
    print(f"Desired repo-managed servers: {len(desired)}")
    print(f"Create: {', '.join(sorted(planned_create)) or '(none)'}")
    print(f"Update: {', '.join(sorted(planned_update)) or '(none)'}")
    print(f"Unchanged: {', '.join(sorted(unchanged)) or '(none)'}")
    print(f"Extra Langflow-only servers left untouched: {', '.join(extras) or '(none)'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
