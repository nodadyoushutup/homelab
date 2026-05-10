"""Wipe RAG vectors out of Chroma.

Run inside the rag-engine image (same env as the HTTP server), e.g.:

  ./scripts/rag/clear.sh                    # drop the configured collection
  ./scripts/rag/clear.sh --all-collections  # drop every collection on the server
  ./scripts/rag/clear.sh --dry-run          # show what would be deleted, do nothing
  ./scripts/rag/clear.sh --yes              # skip the interactive confirm

Targets the Chroma server defined by ``RAG_CHROMA_HOST`` / ``RAG_CHROMA_PORT``
and the collection named ``RAG_CHROMA_COLLECTION`` (default ``homelab``).
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from typing import Any

import chromadb


def _configure_logging() -> None:
    level = (os.getenv("RAG_LOG_LEVEL") or "INFO").strip().upper()
    logging.basicConfig(
        level=getattr(logging, level, logging.INFO),
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stderr,
    )


def _client() -> chromadb.api.client.Client:
    host = (os.getenv("RAG_CHROMA_HOST") or "chromadb").strip()
    port = int((os.getenv("RAG_CHROMA_PORT") or "8000").strip())
    return chromadb.HttpClient(host=host, port=port)


def _collection_name() -> str:
    return (os.getenv("RAG_CHROMA_COLLECTION") or "homelab").strip()


def _list_collection_names(client: chromadb.api.client.Client) -> list[str]:
    """Return collection names regardless of the chromadb client return shape."""
    out: list[str] = []
    for item in client.list_collections():
        name = getattr(item, "name", None)
        out.append(name if isinstance(name, str) else str(item))
    return sorted(out)


def _collection_count(client: chromadb.api.client.Client, name: str) -> int | None:
    try:
        return int(client.get_collection(name=name).count())
    except Exception:  # pragma: no cover - missing/other server errors
        return None


def _print_plan(targets: list[tuple[str, int | None]], host: str, port: int, all_mode: bool) -> None:
    out = sys.stderr
    print("", file=out)
    label = "ALL collections" if all_mode else "collection"
    print(f"RAG clear — Chroma at http://{host}:{port} ({label}):", file=out)
    if not targets:
        print("  (no collections found)", file=out)
    else:
        for name, count in targets:
            count_label = "?" if count is None else str(count)
            print(f"  • {name}  ({count_label} vectors)", file=out)
    print("", file=out)


def _prompt_proceed_default_no() -> bool:
    """Destructive op — default to NO so an accidental Enter does nothing."""
    if not sys.stdin.isatty():
        return False
    while True:
        try:
            line = input("Proceed with delete? [y/N]: ").strip().lower()
        except EOFError:
            return False
        if not line:
            return False
        if line in ("y", "yes"):
            return True
        if line in ("n", "no"):
            return False
        print("Please answer y, n, or Enter for no.", file=sys.stderr)


def _delete_collections(
    client: chromadb.api.client.Client,
    names: list[str],
) -> dict[str, Any]:
    log = logging.getLogger("rag_engine.clear")
    deleted: list[str] = []
    errors: list[str] = []
    for name in names:
        try:
            client.delete_collection(name=name)
            log.info("deleted collection: %s", name)
            deleted.append(name)
        except Exception as exc:  # pragma: no cover - server-side surface
            errors.append(f"{name}: {exc}")
            log.warning("delete failed: %s: %s", name, exc)
    return {"deleted": deleted, "errors": errors}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Clear the RAG Chroma collection(s).")
    parser.add_argument(
        "--all-collections",
        action="store_true",
        help="Delete every collection on the Chroma server (not just RAG_CHROMA_COLLECTION).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be deleted and exit. No changes.",
    )
    parser.add_argument(
        "--yes",
        "-y",
        action="store_true",
        help="Skip interactive confirmation (required when stdin is not a TTY).",
    )
    parser.add_argument(
        "--json-summary",
        action="store_true",
        help="Print final stats as JSON to stdout (progress still on stderr).",
    )
    args = parser.parse_args(argv)
    _configure_logging()
    log = logging.getLogger("rag_engine.clear")

    host = (os.getenv("RAG_CHROMA_HOST") or "chromadb").strip()
    port = int((os.getenv("RAG_CHROMA_PORT") or "8000").strip())
    client = _client()

    if args.all_collections:
        names = _list_collection_names(client)
    else:
        configured = _collection_name()
        existing = set(_list_collection_names(client))
        names = [configured] if configured in existing else []
        if not names:
            log.info("collection %r not present on %s:%s — nothing to delete", configured, host, port)

    targets = [(n, _collection_count(client, n)) for n in names]
    _print_plan(targets, host, port, args.all_collections)

    if args.dry_run:
        if args.json_summary:
            print(json.dumps({"dry_run": True, "targets": [n for n, _ in targets]}))
        return 0

    if not names:
        if args.json_summary:
            print(json.dumps({"deleted": [], "errors": []}))
        return 0

    if not args.yes:
        if not sys.stdin.isatty():
            print(
                "clear: stdin is not a TTY; use --yes to confirm deletion without a prompt.",
                file=sys.stderr,
            )
            return 2
        if not _prompt_proceed_default_no():
            print("clear: cancelled.", file=sys.stderr)
            return 0

    result = _delete_collections(client, names)
    summary = {
        "host": host,
        "port": port,
        "deleted": result["deleted"],
        "errors": result["errors"],
    }
    if args.json_summary:
        print(json.dumps(summary))
    else:
        log.info("clear done: %s", json.dumps(summary, indent=2))
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
