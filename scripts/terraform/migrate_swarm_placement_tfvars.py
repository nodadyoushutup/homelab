#!/usr/bin/env python3
"""Rewrite placement_constraints / platform_architecture / node_constraint -> placement."""

from __future__ import annotations

import argparse
import ast
import re
import sys
from pathlib import Path

OLD_LINE_RE = re.compile(
    r"^\s*(?:placement_constraints|node_constraint|platform_architecture)\s*=.*\n",
    re.MULTILINE,
)


def _parse_list_literal(raw: str) -> list[str]:
    value = ast.literal_eval(raw.strip())
    if not isinstance(value, list):
        raise ValueError(f"expected list, got {type(value)}")
    return [str(item) for item in value]


def format_placement_block(constraints: list[str], arch: str = "aarch64", os_name: str = "linux") -> str:
    lines = ["placement = {"]
    if constraints:
        quoted = ", ".join(f'"{c}"' for c in constraints)
        lines.append(f"  constraints = [{quoted}]")
    lines.append("  platforms = [")
    lines.append("    {")
    lines.append(f'      os           = "{os_name}"')
    lines.append(f'      architecture = "{arch}"')
    lines.append("    },")
    lines.append("  ]")
    lines.append("}")
    return "\n".join(lines)


def migrate_tfvars_text(text: str) -> tuple[str, bool]:
    if "placement = {" in text and not OLD_LINE_RE.search(text):
        return text, False

    constraints: list[str] = []
    arch = "aarch64"

    m = re.search(r"placement_constraints\s*=\s*(\[[^\]]+\])", text)
    if m:
        constraints = _parse_list_literal(m.group(1))

    m_single = re.search(r'node_constraint\s*=\s*"([^"]+)"', text)
    if m_single:
        constraints = [m_single.group(1)]

    m_arch = re.search(r'platform_architecture\s*=\s*"([^"]+)"', text)
    if m_arch:
        arch = m_arch.group(1)

    had_old = bool(OLD_LINE_RE.search(text))
    if had_old:
        text = OLD_LINE_RE.sub("", text)

    if had_old or ("placement = {" not in text and constraints):
        block = format_placement_block(constraints, arch)
        text = text.rstrip() + "\n\n" + block + "\n"
        return text, True

    return text, False


def migrate_file(path: Path, dry_run: bool = False) -> bool:
    original = path.read_text(encoding="utf-8")
    updated, changed = migrate_tfvars_text(original)
    if not changed:
        return False
    if dry_run:
        print(f"[dry-run] would update {path}")
    else:
        path.write_text(updated, encoding="utf-8")
        print(f"[OK] {path}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", help="Tfvars files or directories to scan")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    files: list[Path] = []
    for raw in args.paths:
        path = Path(raw)
        if path.is_dir():
            files.extend(sorted(path.rglob("*.tfvars")))
        elif path.is_file():
            files.append(path)

    changed = 0
    for tfvars in files:
        if migrate_file(tfvars, dry_run=args.dry_run):
            changed += 1

    if changed == 0:
        print("No files needed migration.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
