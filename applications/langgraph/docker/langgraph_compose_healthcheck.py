#!/usr/bin/env python3
"""Docker Compose healthcheck for langgraph dev.

Verifies Postgres/core-api (/ok?check_db=1), that the default graph assistant
exists, that the graph (and MCP clients) can be imported (/assistants/.../schemas),
and that thread search works (same path as Agent Chat thread list).
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("LANGGRAPH_HEALTHCHECK_URL", "http://127.0.0.1:2024")
GRAPH_ID = os.environ.get("LANGGRAPH_HEALTHCHECK_GRAPH_ID", "agent")
TIMEOUT = int(os.environ.get("LANGGRAPH_HEALTHCHECK_TIMEOUT", "30"))


def _request(method: str, path: str, body: dict | None = None) -> bytes:
    url = f"{BASE}{path}"
    data = json.dumps(body).encode() if body is not None else None
    headers: dict[str, str] = {}
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        detail = e.read()[:800]
        raise RuntimeError(f"{method} {path} -> HTTP {e.code}: {detail!r}") from e


def main() -> int:
    try:
        _request("GET", "/ok?check_db=1")
        raw = _request("POST", "/assistants/search", {"graph_id": GRAPH_ID, "limit": 1})
        assistants = json.loads(raw.decode())
        if not assistants:
            print(
                f"no assistant for graph_id={GRAPH_ID!r} yet",
                file=sys.stderr,
            )
            return 1
        aid = assistants[0].get("assistant_id")
        if not aid:
            print(f"assistant missing id: {assistants[0]!r}", file=sys.stderr)
            return 1
        _request("GET", f"/assistants/{aid}/schemas")
        _request("POST", "/threads/search", {"limit": 1})
    except Exception as e:
        print(e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
