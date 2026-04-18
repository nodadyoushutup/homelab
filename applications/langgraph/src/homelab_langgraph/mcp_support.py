from __future__ import annotations

import asyncio
import json
import threading
from pathlib import Path
from typing import Any


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
