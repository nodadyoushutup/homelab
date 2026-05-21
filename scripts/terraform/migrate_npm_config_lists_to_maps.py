#!/usr/bin/env python3
"""One-off: convert NPM config.tfvars list blocks to maps (drops redundant name keys)."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


MAP_KEYS = ("certificates", "access_lists", "proxy_hosts", "redirections", "streams")


def list_to_map(items: list) -> dict:
    out: dict = {}
    for item in items:
        if not isinstance(item, dict):
            raise TypeError(f"expected object in list, got {type(item)!r}")
        if "name" not in item:
            raise KeyError(f"list item missing name: {item!r}")
        name = strip_hcl_quotes(str(item["name"]))
        if name in out:
            raise KeyError(f"duplicate name {name!r}")
        body = {k: v for k, v in item.items() if k != "name"}
        out[name] = body
    return out


def strip_hcl_quotes(value: str) -> str:
    s = value
    while len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        s = s[1:-1]
    return s


def hcl_quote(value: str) -> str:
    escaped = (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )
    return f'"{escaped}"'


def hcl_key(key: str) -> str:
    key = strip_hcl_quotes(key)
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_-]*", key):
        return key
    return hcl_quote(key)


def to_hcl(value, indent: int = 0) -> str:
    pad = "  " * indent
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, str):
        return hcl_quote(strip_hcl_quotes(value))
    if isinstance(value, list):
        if not value:
            return "[]"
        inner = ",\n".join(f"{pad}  {to_hcl(v, indent + 1)}" for v in value)
        return f"[\n{inner},\n{pad}]"
    if isinstance(value, dict):
        if not value:
            return "{}"
        lines = [f"{pad}{{"]
        for key, val in value.items():
            lines.append(f"{pad}  {hcl_key(str(key))} = {to_hcl(val, indent + 1)}")
        lines.append(f"{pad}}}")
        return "\n".join(lines)
    raise TypeError(f"unsupported value type: {type(value)!r}")


def emit_assignment(key: str, value, indent: int = 0) -> str:
    pad = "  " * indent
    return f"{pad}{key} = {to_hcl(value, indent)}"


def convert_data(data: dict) -> dict:
    for key in MAP_KEYS:
        if key not in data:
            continue
        raw = data[key]
        if raw is None:
            data[key] = {}
        elif isinstance(raw, list):
            data[key] = list_to_map(raw)
        elif isinstance(raw, dict):
            pass
        else:
            raise TypeError(f"{key}: expected list or map, got {type(raw)!r}")
    return data


def render_tfvars(data: dict, order: list[str]) -> str:
    lines: list[str] = []
    seen = set()

    for key in order:
        if key not in data:
            continue
        lines.append(emit_assignment(key, data[key]))
        lines.append("")
        seen.add(key)

    for key, value in data.items():
        if key in seen:
            continue
        lines.append(emit_assignment(key, value))
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("tfvars", type=Path)
    parser.add_argument("--in-place", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    venv_dir = Path("/tmp/homelab-hcl2-venv")
    venv_python = venv_dir / "bin/python"
    if not venv_python.exists():
        subprocess.run([sys.executable, "-m", "venv", str(venv_dir)], check=True)
        subprocess.run(
            [str(venv_dir / "bin/pip"), "install", "python-hcl2"],
            check=True,
        )

    text = args.tfvars.read_text()
    parse_script = """
import hcl2, json, sys
data = hcl2.loads(sys.stdin.read())
print(json.dumps(data))
"""
    proc = subprocess.run(
        [str(venv_python), "-c", parse_script],
        input=text,
        text=True,
        capture_output=True,
        check=True,
    )
    data = json.loads(proc.stdout)
    if not isinstance(data, dict):
        raise SystemExit("tfvars root must be an object")

    order = list(data.keys())
    converted = convert_data(data)
    rendered = render_tfvars(converted, order)

    out_path = args.tfvars if args.in_place else args.output
    if out_path is None:
        sys.stdout.write(rendered)
        return 0

    if args.in_place:
        backup = args.tfvars.with_suffix(args.tfvars.suffix + ".pre-map-migration")
        backup.write_text(text)
        print(f"backup: {backup}", file=sys.stderr)

    out_path.write_text(rendered)
    print(f"wrote: {out_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
