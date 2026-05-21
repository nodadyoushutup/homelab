#!/usr/bin/env python3
"""Convert NPM config.tfvars map blocks back to lists (adds name to each object)."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

MAP_KEYS = ("certificates", "access_lists", "proxy_hosts", "redirections", "streams")
VENV_PYTHON = Path("/tmp/homelab-hcl2-venv/bin/python")


def map_to_list(items: dict) -> list:
    out = []
    for name, body in items.items():
        if not isinstance(body, dict):
            raise TypeError(f"expected object for {name!r}, got {type(body)!r}")
        entry = {"name": name, **body}
        out.append(entry)
    return out


def convert_data(data: dict) -> dict:
    for key in MAP_KEYS:
        if key not in data:
            continue
        raw = data[key]
        if raw is None:
            data[key] = []
        elif isinstance(raw, dict):
            data[key] = map_to_list(raw)
        elif isinstance(raw, list):
            pass
        else:
            raise TypeError(f"{key}: expected list or map, got {type(raw)!r}")
    return data


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("tfvars", type=Path)
    parser.add_argument("--in-place", action="store_true")
    args = parser.parse_args()

    if not VENV_PYTHON.exists():
        subprocess.run([sys.executable, "-m", "venv", str(VENV_PYTHON.parent)], check=True)
        subprocess.run([str(VENV_PYTHON.parent / "bin/pip"), "install", "python-hcl2"], check=True)

    text = args.tfvars.read_text()
    proc = subprocess.run(
        [str(VENV_PYTHON), "-c", "import hcl2, json, sys; print(json.dumps(hcl2.loads(sys.stdin.read())))"],
        input=text,
        text=True,
        capture_output=True,
        check=True,
    )
    data = json.loads(proc.stdout)
    order = list(data.keys())
    converted = convert_data(data)

    # Reuse list→map migrator's HCL writer via import
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from migrate_npm_config_lists_to_maps import emit_assignment, render_tfvars  # noqa: PLC0415

    rendered = render_tfvars(converted, order)
    out_path = args.tfvars if args.in_place else args.output
    if not args.in_place and args.output is None:
        sys.stdout.write(rendered)
        return 0

    if args.in_place:
        backup = args.tfvars.with_suffix(args.tfvars.suffix + ".pre-list-migration")
        backup.write_text(text)
        print(f"backup: {backup}", file=sys.stderr)

    out_path.write_text(rendered)
    print(f"wrote: {out_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
