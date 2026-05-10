#!/usr/bin/env python3
"""POST /v1/backfill on rag-engine (same flags as ``python -m rag_engine.backfill``)."""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description="Trigger rag-engine backfill over HTTP.")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--max-files", type=int, default=0, metavar="N")
    p.add_argument("--commit", default="")
    p.add_argument("--json-summary", action="store_true")
    p.add_argument("--yes", "-y", action="store_true", help="Maps to confirm=true (required for mutating API runs).")
    p.add_argument("--force", action="store_true")
    p.add_argument("--prune-orphans", action="store_true")
    p.add_argument("--prune-orphans-only", action="store_true")
    p.add_argument("--prune-dry-run", action="store_true")
    args = p.parse_args(argv)

    base = (os.getenv("RAG_ENGINE_BASE_URL") or "").strip().rstrip("/")
    if not base:
        print("[ERR] RAG_ENGINE_BASE_URL is unset", file=sys.stderr)
        return 2

    body = {
        "dry_run": args.dry_run,
        "max_files": args.max_files,
        "commit": args.commit,
        "json_summary": args.json_summary,
        "confirm": args.yes,
        "force": args.force,
        "prune_orphans": args.prune_orphans,
        "prune_orphans_only": args.prune_orphans_only,
        "prune_dry_run": args.prune_dry_run,
    }
    data = json.dumps(body, separators=(",", ":")).encode("utf-8")

    url = f"{base}/v1/backfill"
    req = urllib.request.Request(url, data=data, method="POST", headers={"Content-Type": "application/json"})
    key = (os.getenv("RAG_ENGINE_API_KEY") or "").strip()
    if key:
        req.add_header("x-api-key", key)

    timeout = 86400.0
    raw_t = (os.getenv("RAG_BACKFILL_HTTP_TIMEOUT_SEC") or "").strip()
    if raw_t:
        try:
            timeout = float(raw_t)
        except ValueError:
            pass

    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace") if exc.fp else ""
        try:
            parsed = json.loads(raw) if raw else {}
            print(json.dumps(parsed, indent=2))
            code = int(parsed.get("exit_code", 1))
            return min(max(code, 0), 255)
        except json.JSONDecodeError:
            print(raw or str(exc), file=sys.stderr)
            return 1
    except urllib.error.URLError as exc:
        print(f"[ERR] {exc.reason}", file=sys.stderr)
        return 1

    try:
        out = json.loads(raw)
    except json.JSONDecodeError:
        print(raw)
        return 1

    print(json.dumps(out, indent=2))
    code = int(out.get("exit_code", 0))
    return min(max(code, 0), 255)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
