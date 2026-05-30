#!/usr/bin/env python3
"""
Merge Vault KV inputs from optional secrets / secret_files blocks embedded in
slice tfvars (app.tfvars, config.tfvars, database.tfvars) under TFVARS_HOME/terraform
and TFVARS_HOME/kubernetes (plain HCL), sorted by path, into one Terraform JSON
variable definitions file for use as a trailing -var-file.

The root vault slice tfvars must not define secrets or secret_files (only
non-secret settings such as mount_path). Colocate Vault payloads in the same
slice tfvars files next to each stack (for example terraform/components/swarm/grafana/app.tfvars).
"""


from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    import hcl2
except ImportError as exc:  # pragma: no cover
    print(
        "[ERR] python-hcl2 is required to parse plain .tfvars HCL.\n"
        "      Install one of:\n"
        "        uv run --with 'python-hcl2>=4,<5' python3 .../vault_merge_config_secrets.py ...\n"
        "        pip install 'python-hcl2>=4,<5'  (into a venv or your chosen environment)\n",
        file=sys.stderr,
    )
    raise SystemExit(1) from exc


def _non_empty_map(value: object) -> bool:
    return isinstance(value, dict) and len(value) > 0


def _assert_vault_config_has_no_secrets(doc: dict, vault_config: Path) -> None:
    if _non_empty_map(doc.get("secrets")) or _non_empty_map(doc.get("secret_files")):
        print(
            f"[ERR] {vault_config} must not define secrets or secret_files.\n"
            "      Use secrets / secret_files blocks in slice tfvars under terraform/... or kubernetes/...\n"
            "      (see scripts/terraform/vault_split_k8s_secrets.py for a bulk split helper).",
            file=sys.stderr,
        )
        raise SystemExit(1)


def _deep_merge(left: dict, right: dict) -> dict:
    out = dict(left)
    for key, rv in right.items():
        lv = out.get(key)
        if isinstance(lv, dict) and isinstance(rv, dict):
            out[key] = _deep_merge(lv, rv)
        else:
            out[key] = rv
    return out


def _stringify_leaves(obj: object) -> object:
    """Normalize HCL2 values to JSON compatible with map(map(map(string)))."""
    if isinstance(obj, dict):
        return {str(k): _stringify_leaves(v) for k, v in obj.items()}
    if isinstance(obj, list):
        if len(obj) == 1:
            return _stringify_leaves(obj[0])
        if not obj:
            return ""
        return json.dumps(obj)
    if obj is True or obj is False:
        return "true" if obj else "false"
    if obj is None:
        return ""
    return str(obj)


def _parse_tfvars(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return hcl2.load(handle)


def _iter_vault_input_tfvars(home: Path) -> list[Path]:
    """Slice tfvars that may embed secrets / secret_files for Vault merge."""
    names = ("app.tfvars", "config.tfvars", "database.tfvars")
    found: list[Path] = []
    for name in names:
        for p in home.rglob(name):
            if not p.is_file() or ".terraform" in p.parts:
                continue
            parts = p.parts
            if "terraform" not in parts and "kubernetes" not in parts:
                continue
            found.append(p)
    return sorted(set(found))


def _iter_secret_fragments(home: Path) -> list[Path]:
    """Legacy standalone secrets.tfvars (still merged if present)."""
    found: list[Path] = []
    for p in home.rglob("secrets.tfvars"):
        if not p.is_file() or ".terraform" in p.parts:
            continue
        parts = p.parts
        if "terraform" not in parts and "kubernetes" not in parts:
            continue
        found.append(p)
    return found


def _iter_all_vault_sources(home: Path) -> list[Path]:
    return sorted(set(_iter_vault_input_tfvars(home)) | set(_iter_secret_fragments(home)))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tfvars-home", required=True, type=Path)
    parser.add_argument("--vault-config-tfvars", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    home: Path = args.tfvars_home.expanduser().resolve()
    vault_config: Path = args.vault_config_tfvars.expanduser().resolve()
    out_path: Path = args.out.expanduser().resolve()

    merged_secrets: dict = {}
    merged_files: dict = {}

    if vault_config.is_file():
        doc = _parse_tfvars(vault_config)
        _assert_vault_config_has_no_secrets(doc, vault_config)

    fragments = sorted(_iter_all_vault_sources(home))
    for frag in fragments:
        try:
            doc = _parse_tfvars(frag)
        except Exception as exc:
            print(f"[WARN] skip unreadable {frag}: {exc}", file=sys.stderr)
            continue
        s, sf = _extract_branch_maps(doc, frag)
        if not s and not sf:
            continue
        merged_secrets = _deep_merge(merged_secrets, s)
        merged_files = _deep_merge(merged_files, sf)
        print(f"[INFO] merged Vault fragment {frag}", file=sys.stderr)

    payload = {
        "secrets": _stringify_leaves(merged_secrets),
        "secret_files": _stringify_leaves(merged_files),
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"[INFO] wrote merged Vault var-file {out_path}", file=sys.stderr)


def _extract_branch_maps(doc: dict, src: Path) -> tuple[dict, dict]:
    secrets = doc.get("secrets")
    secret_files = doc.get("secret_files")
    if secrets is not None and not isinstance(secrets, dict):
        raise SystemExit(f"[ERR] {src}: secrets must be an object map when set")
    if secret_files is not None and not isinstance(secret_files, dict):
        raise SystemExit(f"[ERR] {src}: secret_files must be an object map when set")
    return secrets or {}, secret_files or {}


if __name__ == "__main__":
    main()
