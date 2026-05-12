#!/usr/bin/env python3
"""POST /v1/backfill on rag-engine (same flags as ``python -m ingest.backfill``)."""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request


def _prune_dry_for_confirm(args: argparse.Namespace) -> bool:
    """Match ``ingest.backfill`` prune_dry (safe preview; no server confirm required)."""
    return bool(args.prune_dry_run) or (bool(args.dry_run) and bool(args.prune_orphans_only))


def _http_backfill_needs_confirm(args: argparse.Namespace) -> bool:
    """Whether POST body must set confirm=true (server uses interactive=False)."""
    if args.dry_run:
        return False
    if args.prune_orphans_only:
        return not _prune_dry_for_confirm(args)
    return True


def _can_prompt_interactively() -> bool:
    """True if we can read y/n from the user's terminal.

    ``rag_backfill.sh`` runs this process in the background while tailing logs,
    so ``stdin`` is often not a TTY even in an interactive shell; ``/dev/tty``
    still reaches the controlling terminal.
    """
    if sys.stdin.isatty():
        return True
    try:
        with open("/dev/tty", "r"):
            pass
        return True
    except OSError:
        return False


def _read_interactive_line() -> str | None:
    """One line from stdin or ``/dev/tty``; None on EOF / no terminal."""
    if sys.stdin.isatty():
        try:
            return input()
        except EOFError:
            return None
    try:
        with open("/dev/tty", "r") as tty:
            return tty.readline()
    except OSError:
        return None


def _prompt_proceed_default_yes(prompt: str) -> bool:
    while True:
        print(prompt, end="", file=sys.stderr, flush=True)
        raw = _read_interactive_line()
        if raw is None:
            return False
        line = raw.strip().lower()
        if not line:
            return True
        if line in ("y", "yes"):
            return True
        if line in ("n", "no"):
            return False
        print("Please answer y, n, or Enter for yes.", file=sys.stderr)


def _resolve_confirm(args: argparse.Namespace) -> tuple[bool, int | None]:
    """Return (confirm_for_JSON_body, early_exit_code_or_None).

    When confirmation is required but no terminal is available and ``--yes`` was
    not passed, we POST with ``confirm: false`` so the server responds with
    ``confirm_required`` (same as before).
    """
    if not _http_backfill_needs_confirm(args):
        return False, None
    if args.yes:
        return True, None
    if not _can_prompt_interactively():
        return False, None
    if args.prune_orphans_only:
        prompt = "Proceed with orphan prune? [Y/n]: "
    else:
        prompt = "Proceed with indexing? [Y/n]: "
    if _prompt_proceed_default_yes(prompt):
        return True, None
    print("backfill: cancelled.", file=sys.stderr)
    return False, 0


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description="Trigger rag-engine backfill over HTTP.")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--max-files", type=int, default=0, metavar="N")
    p.add_argument("--commit", default="")
    p.add_argument("--json-summary", action="store_true")
    p.add_argument(
        "--yes",
        "-y",
        action="store_true",
        help="Skip y/n prompt; maps to confirm=true (required when no controlling terminal).",
    )
    p.add_argument("--force", action="store_true")
    p.add_argument("--prune-orphans", action="store_true")
    p.add_argument("--prune-orphans-only", action="store_true")
    p.add_argument("--prune-dry-run", action="store_true")
    args = p.parse_args(argv)

    confirm, early = _resolve_confirm(args)
    if early is not None:
        return early

    base = (os.getenv("RAG_ENGINE_BASE_URL") or "").strip().rstrip("/")
    if not base:
        print("[ERR] RAG_ENGINE_BASE_URL is unset", file=sys.stderr)
        return 2

    body = {
        "dry_run": args.dry_run,
        "max_files": args.max_files,
        "commit": args.commit,
        "json_summary": args.json_summary,
        "confirm": confirm,
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
        # KeyboardInterrupt during a blocking socket read surfaces as URLError
        # wrapping the original KeyboardInterrupt; exit quietly with 130 so the
        # caller sees a clean detach instead of a stack trace.
        if isinstance(getattr(exc, "reason", None), KeyboardInterrupt):
            return 130
        print(f"[ERR] {exc.reason}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130

    try:
        out = json.loads(raw)
    except json.JSONDecodeError:
        print(raw)
        return 1

    print(json.dumps(out, indent=2))
    code = int(out.get("exit_code", 0))
    return min(max(code, 0), 255)


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        raise SystemExit(130)
