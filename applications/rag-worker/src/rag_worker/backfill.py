"""One-shot filesystem walk to populate Chroma (legacy / full index).

Run inside the rag-worker image (same env as the HTTP server), e.g.:

  ./scripts/rag/backfill.sh
  ./scripts/rag/backfill.sh --dry-run
  ./scripts/rag/backfill.sh --max-files 100
  ./scripts/rag/backfill.sh --yes   # skip interactive confirm (automation)
  ./scripts/rag/backfill.sh --yes --prune-orphans              # index then delete stale Chroma paths
  ./scripts/rag/backfill.sh --yes --prune-orphans-only          # only reconcile Chroma vs disk
  ./scripts/rag/backfill.sh --yes --prune-orphans-only --prune-dry-run

Requires ``chromadb`` service up and ``RAG_WORKSPACE_MOUNT`` matching the repo mount.
Interactive runs print index roots and file count, then ask ``Proceed? [Y/n]`` (default Y).
During indexing, Ctrl+C prompts for pause, stop (summary), or continue; a second Ctrl+C stops immediately.
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import subprocess
import sys
from typing import Any

from rag_worker.embed_google import build_genai_client
from rag_worker.path_rules import load_exclude_segments
from rag_worker.pipeline import (
    _allowed_prefixes,
    _collection,
    collect_backfill_relative_paths,
    prune_orphan_paths,
    upsert_paths,
)


def _configure_logging() -> None:
    level = (os.getenv("RAG_LOG_LEVEL") or "INFO").strip().upper()
    logging.basicConfig(
        level=getattr(logging, level, logging.INFO),
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stderr,
    )


def _print_prune_plan() -> None:
    out = sys.stderr
    print("", file=out)
    print("RAG orphan prune — Chroma paths not on disk under current rules:", file=out)
    print("  (same allowlist / excludes / max size as backfill.)", file=out)
    print("", file=out)


def _print_index_plan(paths_count: int) -> None:
    roots = _allowed_prefixes()
    segs = sorted(load_exclude_segments())
    max_b = os.getenv("RAG_BACKFILL_MAX_FILE_BYTES", "5242880")
    out = sys.stderr
    print("", file=out)
    print("RAG backfill — paths to index (RAG_ALLOWED_PATH_PREFIXES):", file=out)
    for r in roots:
        print(f"  • {r}", file=out)
    print("", file=out)
    print(
        f"Excluded directory segments ({len(segs)}): {', '.join(segs[:24])}"
        + (f", … (+{len(segs) - 24} more)" if len(segs) > 24 else ""),
        file=out,
    )
    print(f"Max file size: {max_b} bytes", file=out)
    print(f"Files matched (after rules, before --max-files cap): {paths_count}", file=out)
    print(
        "Unchanged files are skipped unless you pass --force (compares SHA-256, model, schema version, and chunk strategy/settings in Chroma).",
        file=out,
    )
    print("", file=out)


def _prompt_proceed_default_yes() -> bool:
    if not sys.stdin.isatty():
        return False
    while True:
        try:
            line = input("Proceed with indexing? [Y/n]: ").strip().lower()
        except EOFError:
            return False
        if not line:
            return True
        if line in ("y", "yes"):
            return True
        if line in ("n", "no"):
            return False
        print("Please answer y, n, or Enter for yes.", file=sys.stderr)


def _prompt_after_backfill_interrupt(completed: int, total: int, current_rel: str) -> str:
    """Return ``resume``, ``pause``, or ``stop``.

    A second Ctrl+C (or EOF) while waiting at the prompt stops immediately.
    """
    print("", file=sys.stderr)
    print(
        f"Interrupted — completed {completed}/{total} files; current: {current_rel}",
        file=sys.stderr,
    )
    if not sys.stdin.isatty():
        print("backfill: stdin is not a TTY; cannot prompt — exiting.", file=sys.stderr)
        return "stop"

    while True:
        try:
            line = input(
                "[p]ause (wait for Enter), [s]top and show summary, [c]ontinue — "
                "or press Ctrl+C again to stop immediately: "
            ).strip().lower()
        except KeyboardInterrupt:
            print("\nSecond interrupt — stopping.", file=sys.stderr)
            return "stop"
        except EOFError:
            print("Stopping.", file=sys.stderr)
            return "stop"

        if line in ("s", "stop", "q", "quit"):
            return "stop"
        if line in ("p", "pause"):
            return "pause"
        if line in ("c", "continue", "r", "resume", ""):
            return "resume"
        print("Please enter p, s, or c (or Ctrl+C to stop).", file=sys.stderr)


def _wait_pause_resume() -> bool:
    """Block until Enter. Return False if the user forces stop with Ctrl+C or EOF."""
    try:
        input("Paused — press Enter to resume, or Ctrl+C to stop: ")
    except KeyboardInterrupt:
        print("\nStopping.", file=sys.stderr)
        return False
    except EOFError:
        print("Stopping.", file=sys.stderr)
        return False
    return True


def _default_commit_label() -> str:
    env_label = (os.getenv("RAG_BACKFILL_COMMIT") or "").strip()
    if env_label:
        return env_label
    root = os.environ.get("RAG_WORKSPACE_MOUNT", "/workspace")
    try:
        out = subprocess.run(
            ["git", "-C", root, "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        if out.returncode == 0 and (out.stdout or "").strip():
            return (out.stdout or "").strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return "backfill"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Backfill RAG index from workspace tree.")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print file count and exit (no API calls).",
    )
    parser.add_argument(
        "--max-files",
        type=int,
        default=0,
        metavar="N",
        help="Index at most N files (0 = no limit).",
    )
    parser.add_argument(
        "--commit",
        default="",
        help="Chroma metadata commit label (default: git HEAD in workspace or 'backfill').",
    )
    parser.add_argument(
        "--json-summary",
        action="store_true",
        help="Print final stats as JSON to stdout (progress still on stderr).",
    )
    parser.add_argument(
        "--yes",
        "-y",
        action="store_true",
        help="Skip interactive confirmation (required when stdin is not a TTY).",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-embed every file even when content hash and chunk settings match Chroma.",
    )
    parser.add_argument(
        "--prune-orphans",
        action="store_true",
        help="After indexing, delete Chroma rows for paths that no longer exist on disk under current rules.",
    )
    parser.add_argument(
        "--prune-orphans-only",
        action="store_true",
        help="Skip indexing; only run orphan prune (same path rules as backfill).",
    )
    parser.add_argument(
        "--prune-dry-run",
        action="store_true",
        help="With orphan prune: list counts and sample paths only; no deletes.",
    )
    args = parser.parse_args(argv)
    _configure_logging()
    log = logging.getLogger("rag_worker.backfill")

    if args.prune_orphans_only and args.prune_orphans:
        log.warning("backfill: --prune-orphans-only wins over --prune-orphans")

    prune_dry = bool(args.prune_dry_run) or (bool(args.dry_run) and bool(args.prune_orphans_only))

    if args.prune_orphans_only:
        _print_prune_plan()
        if not prune_dry and not args.yes:
            if not sys.stdin.isatty():
                print(
                    "backfill: stdin is not a TTY; use --yes to confirm orphan prune without a prompt.",
                    file=sys.stderr,
                )
                return 2
            line = input("Proceed with orphan prune? [Y/n]: ").strip().lower()
            if line in ("n", "no"):
                print("backfill: cancelled.", file=sys.stderr)
                return 0
        collection = _collection()
        pr = prune_orphan_paths(collection, dry_run=prune_dry)
        if args.json_summary:
            print(json.dumps({"prune": pr}))
        else:
            log.info("orphan prune: %s", json.dumps(pr, indent=2))
        return 0

    paths = collect_backfill_relative_paths()
    if args.max_files > 0:
        paths = paths[: args.max_files]

    log.info("backfill: %s files to consider (max_bytes=%s)", len(paths), os.getenv("RAG_BACKFILL_MAX_FILE_BYTES", "5242880"))

    if args.dry_run:
        _print_index_plan(len(paths))
        print(len(paths))
        return 0

    if not paths:
        log.warning("backfill: no paths matched; check RAG_ALLOWED_PATH_PREFIXES and mounts")
        if not args.prune_orphans:
            return 0
        log.info("backfill: continuing with --prune-orphans only (no files to index)")
        _print_index_plan(0)
        _print_prune_plan()
        if not args.prune_dry_run and not args.yes:
            if not sys.stdin.isatty():
                print(
                    "backfill: stdin is not a TTY; use --yes to confirm orphan prune without a prompt.",
                    file=sys.stderr,
                )
                return 2
            line = input("Proceed with orphan prune? [Y/n]: ").strip().lower()
            if line in ("n", "no"):
                print("backfill: cancelled.", file=sys.stderr)
                return 0
        collection = _collection()
        pr = prune_orphan_paths(collection, dry_run=bool(args.prune_dry_run))
        summary = {
            "commit": (args.commit or "").strip() or _default_commit_label(),
            "files_seen": 0,
            "files_completed": 0,
            "indexed": 0,
            "chunks": 0,
            "skipped": 0,
            "unchanged": 0,
            "errors": [],
            "user_stopped": False,
            "prune": pr,
        }
        if args.json_summary:
            print(json.dumps(summary))
        else:
            log.info("orphan prune: %s", json.dumps(pr, indent=2))
            log.info("backfill done: %s", json.dumps(summary, indent=2))
        return 0

    _print_index_plan(len(paths))
    if not args.yes:
        if not sys.stdin.isatty():
            print(
                "backfill: stdin is not a TTY; use --yes to confirm indexing without a prompt.",
                file=sys.stderr,
            )
            return 2
        if not _prompt_proceed_default_yes():
            print("backfill: cancelled.", file=sys.stderr)
            return 0

    commit = (args.commit or "").strip() or _default_commit_label()
    collection = _collection()
    genai_client = build_genai_client()

    from tqdm import tqdm

    skip_unchanged = not args.force
    totals: dict[str, Any] = {"indexed": 0, "chunks": 0, "skipped": 0, "unchanged": 0, "errors": []}
    user_stopped = False
    with tqdm(total=len(paths), unit="file", desc="RAG backfill", file=sys.stderr) as bar:
        i = 0
        while i < len(paths):
            rel = paths[i]
            bar.set_postfix(last=(rel[-48:] if len(rel) > 48 else rel), refresh=False)
            try:
                one = upsert_paths(
                    collection,
                    genai_client,
                    [rel],
                    commit,
                    skip_unchanged=skip_unchanged,
                )
                totals["indexed"] += int(one["indexed"])
                totals["chunks"] += int(one["chunks"])
                totals["skipped"] += int(one["skipped"])
                totals["unchanged"] += int(one.get("unchanged", 0))
                totals["errors"].extend(one["errors"])
                i += 1
                bar.update(1)
            except KeyboardInterrupt:
                bar.clear()
                choice = _prompt_after_backfill_interrupt(i, len(paths), rel)
                if choice == "stop":
                    user_stopped = True
                    break
                if choice == "pause" and not _wait_pause_resume():
                    user_stopped = True
                    break
                # resume: retry the same file (safe if interrupt happened mid-upsert)
                continue

    summary: dict[str, Any] = {
        "commit": commit,
        "files_seen": len(paths),
        "files_completed": i,
        "indexed": totals["indexed"],
        "chunks": totals["chunks"],
        "skipped": totals["skipped"],
        "unchanged": totals["unchanged"],
        "errors": totals["errors"],
        "user_stopped": user_stopped,
    }
    if args.prune_orphans and not user_stopped:
        _print_prune_plan()
        pr = prune_orphan_paths(collection, dry_run=bool(args.prune_dry_run))
        summary["prune"] = pr
        if not args.json_summary:
            log.info("orphan prune: %s", json.dumps(pr, indent=2))
    elif args.prune_orphans and user_stopped:
        log.warning("backfill: skipping --prune-orphans because indexing was stopped early")

    if args.json_summary:
        print(json.dumps(summary))
    else:
        log.info("backfill done: %s", json.dumps(summary, indent=2))
    if user_stopped:
        return 130
    if totals["errors"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
