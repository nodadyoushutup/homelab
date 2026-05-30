#!/usr/bin/env python3
"""
Merge each secrets.tfvars into the sibling slice tfvars (app, config, or database)
under CONFIG_DIR, then delete secrets.tfvars.

Preference: existing app.tfvars > config.tfvars > database.tfvars; otherwise
create app.tfvars.

When the target file has no existing secrets/secret_files keys, the secrets file
body is appended verbatim so comments and ordering in the target are preserved.
Otherwise HCL is merged via python-hcl2 and the target is rewritten (comments may
be lost for that file).

Optional: --patch-terraform-roots adds ignored variable "secrets" / "secret_files"
to Terraform slice roots so -var-file can include those keys (see vault_merge).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

try:
    import hcl2
except ImportError as exc:  # pragma: no cover
    print(
        "[ERR] python-hcl2 is required.\n"
        "  uv run --with 'python-hcl2>=4,<5' python3 .../consolidate_secrets_into_slice_tfvars.py ...\n",
        file=sys.stderr,
    )
    raise SystemExit(1) from exc

_IDENT = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_-]*$")

_TFVARS_SNIPPET = """

# Vault KV fragments (parsed by scripts/terraform/vault_merge_config_secrets.py); unused by this module.
variable "secrets" {
  type        = any
  default     = {}
  sensitive   = true
}

variable "secret_files" {
  type        = any
  default     = {}
  sensitive   = true
}
"""


def _hcl_string(s: str) -> str:
    escaped = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r")
    return f'"{escaped}"'


def _hcl_attr_key(k: str) -> str:
    return k if _IDENT.match(k) else _hcl_string(k)


def _fmt_scalar(v: object) -> str:
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return _hcl_string(v)
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return str(v)
    return _hcl_string(str(v))


def _fmt_object(d: dict, indent: int) -> str:
    pad = "  " * indent
    inner = "  " * (indent + 1)
    if not d:
        return "{}"
    lines = ["{"]
    for k in sorted(d.keys(), key=str):
        v = d[k]
        key = _hcl_attr_key(str(k))
        if isinstance(v, dict):
            lines.append(f"{inner}{key} = {_fmt_object(v, indent + 1)}")
        elif v is None:
            lines.append(f"{inner}{key} = null")
        elif isinstance(v, bool):
            lines.append(f"{inner}{key} = {'true' if v else 'false'}")
        elif isinstance(v, str):
            lines.append(f"{inner}{key} = {_hcl_string(v)}")
        elif isinstance(v, (int, float)) and not isinstance(v, bool):
            lines.append(f"{inner}{key} = {v}")
        elif isinstance(v, list):
            if len(v) == 1:
                lines.append(f"{inner}{key} = {_fmt_scalar(v[0])}")
            else:
                raise SystemExit(f"[ERR] unsupported non-singleton list at {k!r}")
        else:
            lines.append(f"{inner}{key} = {_hcl_string(str(v))}")
    lines.append(f"{pad}}}")
    return "\n".join(lines)


def _unwrap_hcl2_value(v: object) -> object:
    if isinstance(v, list) and len(v) == 1:
        return _unwrap_hcl2_value(v[0])
    if isinstance(v, list) and not v:
        return ""
    return v


def _write_tfvars_document(doc: dict, path: Path) -> None:
    chunks: list[str] = []
    for k in sorted(doc.keys(), key=str):
        v = _unwrap_hcl2_value(doc[k])
        key = _hcl_attr_key(str(k))
        if isinstance(v, dict):
            chunks.append(f"{key} = {_fmt_object(v, 0)}")
        elif isinstance(v, list):
            if len(v) == 1:
                chunks.append(f"{key} = {_fmt_scalar(_unwrap_hcl2_value(v))}")
            else:
                raise SystemExit(f"[ERR] unsupported top-level list at {k!r}")
        else:
            chunks.append(f"{key} = {_fmt_scalar(v)}")
        chunks.append("")
    path.write_text("\n".join(chunks).rstrip() + "\n", encoding="utf-8")


def _deep_merge(left: dict, right: dict) -> dict:
    out = dict(left)
    for key, rv in right.items():
        lv = out.get(key)
        if isinstance(lv, dict) and isinstance(rv, dict):
            out[key] = _deep_merge(lv, rv)
        else:
            out[key] = rv
    return out


def _parse(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return hcl2.load(handle)


def _pick_target_tfvars(stack_dir: Path) -> Path:
    for name in ("app.tfvars", "config.tfvars", "database.tfvars"):
        p = stack_dir / name
        if p.is_file():
            return p
    return stack_dir / "app.tfvars"


def _should_append_verbatim(target: Path, sec_doc: dict) -> bool:
    if not target.is_file():
        return False
    try:
        cur = _parse(target)
    except Exception:
        return False
    if cur.get("secrets") is not None or cur.get("secret_files") is not None:
        return False
    if not sec_doc.get("secrets") and not sec_doc.get("secret_files"):
        return False
    return True


def consolidate_config_dir(cfg: Path) -> None:
    secrets_files = sorted(
        p
        for p in cfg.rglob("secrets.tfvars")
        if p.is_file() and ".terraform" not in p.parts and ("terraform" in p.parts or "kubernetes" in p.parts)
    )
    for sec_path in secrets_files:
        stack_dir = sec_path.parent
        sec_doc = _parse(sec_path)
        target = _pick_target_tfvars(stack_dir)
        sec_raw = sec_path.read_text(encoding="utf-8").strip()
        if not sec_raw:
            sec_path.unlink()
            print(f"[SKIP] empty {sec_path}, removed", file=sys.stderr)
            continue

        if _should_append_verbatim(target, sec_doc):
            base = target.read_text(encoding="utf-8").rstrip()
            sep = "\n\n" if base else ""
            target.write_text(base + sep + sec_raw + "\n", encoding="utf-8")
            print(f"[OK] appended {sec_path.name} -> {target}", file=sys.stderr)
        else:
            merged: dict = {}
            if target.is_file():
                merged = _parse(target)
            s_in = merged.get("secrets") or {}
            sf_in = merged.get("secret_files") or {}
            s_sec = sec_doc.get("secrets") or {}
            sf_sec = sec_doc.get("secret_files") or {}
            if not isinstance(s_in, dict) or not isinstance(sf_in, dict):
                raise SystemExit(f"[ERR] {target}: invalid secrets/secret_files shape")
            if not isinstance(s_sec, dict) or not isinstance(sf_sec, dict):
                raise SystemExit(f"[ERR] {sec_path}: invalid secrets/secret_files shape")
            merged["secrets"] = _deep_merge(s_in, s_sec)
            merged["secret_files"] = _deep_merge(sf_in, sf_sec)
            if not merged["secrets"]:
                merged.pop("secrets", None)
            if not merged["secret_files"]:
                merged.pop("secret_files", None)
            target.parent.mkdir(parents=True, exist_ok=True)
            _write_tfvars_document(merged, target)
            print(f"[OK] merged HCL {sec_path.name} -> {target}", file=sys.stderr)

        sec_path.unlink()
        print(f"[OK] removed {sec_path}", file=sys.stderr)


def patch_terraform_roots(repo: Path) -> None:
    swarm = repo / "terraform" / "components" / "swarm"
    if swarm.is_dir():
        for slice in ("app", "config", "database"):
            for vf in sorted(swarm.rglob(f"{slice}/variables.tf")):
                if ".terraform" in vf.parts:
                    continue
                rel = vf.relative_to(repo)
                if "components/swarm/vault/config" in str(rel).replace("\\", "/"):
                    continue
                text = vf.read_text(encoding="utf-8")
                if 'variable "secrets"' in text:
                    continue
                vf.write_text(text.rstrip() + _TFVARS_SNIPPET, encoding="utf-8")
                print(f"[PATCH] {vf}", file=sys.stderr)

    for rel in (
        repo / "terraform" / "components" / "cluster" / "argocd" / "config" / "variables.tf",
        repo / "terraform" / "components" / "cluster" / "proxmox" / "app" / "variables.tf",
        repo / "terraform" / "components" / "cluster" / "talos" / "app" / "variables.tf",
        repo / "terraform" / "components" / "remote" / "cloudflare" / "config" / "variables.tf",
        repo / "terraform" / "components" / "network" / "fortigate" / "config" / "variables.tf",
    ):
        if not rel.is_file():
            continue
        text = rel.read_text(encoding="utf-8")
        if 'variable "secrets"' in text:
            continue
        rel.write_text(text.rstrip() + _TFVARS_SNIPPET, encoding="utf-8")
        print(f"[PATCH] {rel}", file=sys.stderr)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--config-dir", type=Path, default=Path(__file__).resolve().parents[2] / ".config")
    ap.add_argument("--repo-root", type=Path, help="If set, append optional secrets variables to Terraform slice roots")
    args = ap.parse_args()

    cfg = args.config_dir.expanduser().resolve()
    if not cfg.is_dir():
        print(f"[ERR] not a directory: {cfg}", file=sys.stderr)
        raise SystemExit(1)

    consolidate_config_dir(cfg)

    if args.repo_root:
        repo = args.repo_root.expanduser().resolve()
        patch_terraform_roots(repo)


if __name__ == "__main__":
    main()
