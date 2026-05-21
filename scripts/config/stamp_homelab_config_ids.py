#!/usr/bin/env python3
"""Ensure first-line homelab-config tags on site-local config under CONFIG_DIR.

Tag format:
  # homelab-config: <config-id>

Ids are relative to CONFIG_DIR (no leading slash), derived from each file path:
  terraform/swarm/grafana/app.tfvars  -> terraform/swarm/grafana/app
  minio.backend.hcl                   -> minio.backend
  docker/langgraph.env                -> docker/langgraph

Skips: README.md, *.example, init.json, grafana.ini, known_hosts, .gitkeep
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

TAG_PREFIX = "# homelab-config:"

SKIP_NAMES = frozenset({"README.md", "init.json", "grafana.ini", "known_hosts", ".gitkeep"})


def config_id_for_file(config_dir: Path, path: Path) -> str | None:
    rel = path.relative_to(config_dir).as_posix()
    name = path.name

    if name in SKIP_NAMES or name.endswith(".example"):
        return None

    if name == "minio.backend.hcl":
        return "minio.backend"

    if name.endswith(".tfvars"):
        return rel[: -len(".tfvars")]

    if path.parent.name == "docker" and name.endswith(".env"):
        return f"docker/{path.stem}"

    if name.endswith(".hcl"):
        return rel[: -len(".hcl")]

    return None


def tag_line(config_id: str) -> str:
    return f"{TAG_PREFIX} {config_id}"


def stamp_file(path: Path, config_id: str, *, dry_run: bool) -> str:
    expected = tag_line(config_id)
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)

    if lines and lines[0].rstrip("\r\n") == expected:
        return "ok"

    if lines and lines[0].lstrip().startswith(TAG_PREFIX):
        new_lines = [expected + "\n", *lines[1:]]
        action = "update"
    else:
        new_lines = [expected + "\n", *lines]
        action = "prepend"

    if not dry_run:
        path.write_text("".join(new_lines), encoding="utf-8")
    return action


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config-dir",
        type=Path,
        default=Path(__file__).resolve().parents[2] / ".config",
        help="CONFIG_DIR root (default: <repo>/.config)",
    )
    parser.add_argument("--check", action="store_true", help="Report files missing or wrong tags")
    parser.add_argument("--dry-run", action="store_true", help="Print actions without writing")
    args = parser.parse_args()

    config_dir = args.config_dir.resolve()
    if not config_dir.is_dir():
        print(f"[ERR] CONFIG_DIR not found: {config_dir}", file=sys.stderr)
        return 1

    files: list[Path] = []
    for path in config_dir.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix in {".tfvars", ".hcl"} or (
            path.parent.name == "docker" and path.suffix == ".env"
        ):
            files.append(path.resolve())
    files = sorted(set(files))

    missing = 0
    changed = 0
    for path in files:
        config_id = config_id_for_file(config_dir, path)
        if not config_id:
            continue
        expected = tag_line(config_id)
        first = path.read_text(encoding="utf-8").splitlines()[0] if path.stat().st_size else ""
        if first.rstrip("\r") == expected:
            continue
        if args.check:
            print(f"[MISSING] {path.relative_to(config_dir)} -> {expected}")
            missing += 1
            continue
        action = stamp_file(path, config_id, dry_run=args.dry_run)
        rel = path.relative_to(config_dir)
        print(f"[{action.upper()}] {rel} -> {config_id}")
        changed += 1

    if args.check:
        if missing:
            print(f"[ERR] {missing} file(s) need homelab-config tags", file=sys.stderr)
            return 1
        print(f"[OK] All tagged under {config_dir}")
        return 0

    print(f"[OK] Stamped {changed} file(s) under {config_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
