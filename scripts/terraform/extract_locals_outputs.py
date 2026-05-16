#!/usr/bin/env python3
"""Move locals blocks to locals.tf and output blocks to outputs.tf in each Terraform module dir."""

from __future__ import annotations

import re
import sys
from pathlib import Path

TERRAFORM_ROOT = Path(__file__).resolve().parents[2] / "terraform"

LOCALS_START = re.compile(r"^(\s*)locals\s*\{", re.MULTILINE)
OUTPUT_START = re.compile(
    r'^(\s*)output\s+(?:"[^"]+"|\'[^\']+\')\s*\{', re.MULTILINE
)


def find_block_end(content: str, open_brace: int) -> int:
    """Return index after closing brace matching open_brace (0-based)."""
    depth = 0
    i = open_brace
    in_string = False
    string_char = ""
    escape = False
    in_line_comment = False
    in_block_comment = False

    while i < len(content):
        c = content[i]
        nxt = content[i + 1] if i + 1 < len(content) else ""

        if in_line_comment:
            if c == "\n":
                in_line_comment = False
            i += 1
            continue

        if in_block_comment:
            if c == "*" and nxt == "/":
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue

        if in_string:
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == string_char:
                in_string = False
            i += 1
            continue

        if c == "#":
            in_line_comment = True
            i += 1
            continue
        if c == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if c == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue

        if c in ('"', "'"):
            in_string = True
            string_char = c
            i += 1
            continue

        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1

    raise ValueError(f"Unbalanced braces at position {open_brace}")


def extract_blocks(content: str, pattern: re.Pattern) -> tuple[str, list[str]]:
    """Remove matching blocks from content; return (new_content, extracted_blocks)."""
    extracted: list[str] = []
    while True:
        m = pattern.search(content)
        if not m:
            break
        open_brace = content.index("{", m.start())
        end = find_block_end(content, open_brace)
        block = content[m.start() : end]
        extracted.append(block.rstrip() + "\n")
        before = content[: m.start()]
        after = content[end:]
        content = before + after
    content = re.sub(r"\n{3,}", "\n\n", content)
    return content.rstrip() + ("\n" if content.strip() else ""), extracted


def module_dirs(root: Path) -> list[Path]:
    dirs: set[Path] = set()
    for tf in root.rglob("*.tf"):
        dirs.add(tf.parent)
    return sorted(dirs)


def process_module(module_dir: Path, dry_run: bool = False) -> dict[str, int]:
    stats = {"locals_blocks": 0, "output_blocks": 0, "files_changed": 0}
    tf_files = sorted(
        f
        for f in module_dir.glob("*.tf")
        if f.name not in ("locals.tf", "outputs.tf")
    )
    if not tf_files:
        return stats

    all_locals: list[str] = []
    all_outputs: list[str] = []
    file_updates: dict[Path, str] = {}

    for tf_path in tf_files:
        original = tf_path.read_text(encoding="utf-8")
        content, locals_blocks = extract_blocks(original, LOCALS_START)
        content, output_blocks = extract_blocks(content, OUTPUT_START)
        all_locals.extend(locals_blocks)
        all_outputs.extend(output_blocks)
        if content != original:
            file_updates[tf_path] = content
            stats["files_changed"] += 1

    stats["locals_blocks"] = len(all_locals)
    stats["output_blocks"] = len(all_outputs)

    if not all_locals and not all_outputs:
        return stats

    if dry_run:
        return stats

    locals_path = module_dir / "locals.tf"
    outputs_path = module_dir / "outputs.tf"

    if all_locals:
        existing_locals = ""
        if locals_path.exists():
            existing_locals = locals_path.read_text(encoding="utf-8").rstrip() + "\n\n"
        locals_path.write_text(existing_locals + "".join(all_locals), encoding="utf-8")

    if all_outputs:
        existing_outputs = ""
        if outputs_path.exists():
            existing_outputs = outputs_path.read_text(encoding="utf-8").rstrip() + "\n\n"
        outputs_path.write_text(
            existing_outputs + "".join(all_outputs), encoding="utf-8"
        )

    for tf_path, new_content in file_updates.items():
        if not new_content.strip():
            tf_path.unlink()
        else:
            tf_path.write_text(new_content, encoding="utf-8")

    # Remove runner_defaults.tf if emptied (locals moved out)
    runner_defaults = module_dir / "runner_defaults.tf"
    if runner_defaults.exists() and not runner_defaults.read_text(encoding="utf-8").strip():
        runner_defaults.unlink()

    return stats


def main() -> int:
    dry_run = "--dry-run" in sys.argv
    total = {"modules": 0, "locals_blocks": 0, "output_blocks": 0, "files_changed": 0}

    for module_dir in module_dirs(TERRAFORM_ROOT):
        stats = process_module(module_dir, dry_run=dry_run)
        if stats["locals_blocks"] or stats["output_blocks"]:
            total["modules"] += 1
            total["locals_blocks"] += stats["locals_blocks"]
            total["output_blocks"] += stats["output_blocks"]
            total["files_changed"] += stats["files_changed"]
            rel = module_dir.relative_to(TERRAFORM_ROOT)
            print(
                f"{rel}: {stats['locals_blocks']} locals, "
                f"{stats['output_blocks']} outputs, "
                f"{stats['files_changed']} files"
            )

    print(
        f"\n{'DRY RUN ' if dry_run else ''}Total: {total['modules']} modules, "
        f"{total['locals_blocks']} locals blocks, "
        f"{total['output_blocks']} output blocks, "
        f"{total['files_changed']} files updated"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
