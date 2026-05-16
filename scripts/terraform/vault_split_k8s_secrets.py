#!/usr/bin/env python3
"""
Split vault slice tfvars: move secrets.k8s.* and secret_files.k8s.* into
per-stack app.tfvars under TFVARS_HOME (plain HCL), then leave the vault
slice tfvars with only mount_path.

Fragments are written into each stack's **app.tfvars** (appended when that file
already exists without a `secrets` block; otherwise the file is overwritten
with the fragment only — use consolidate_secrets_into_slice_tfvars.py after
merging a monolith if app.tfvars already holds non-Vault settings).

Directory naming: underscore -> hyphen (mcp_argocd -> mcp-argocd).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

try:
    import hcl2
except ImportError as exc:  # pragma: no cover
    print("[ERR] pip install python-hcl2 or: uv run --with 'python-hcl2>=4,<5' python3 ...", file=sys.stderr)
    raise SystemExit(1) from exc

_IDENT = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_-]*$")


def _hcl_string(s: str) -> str:
    escaped = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r")
    return f'"{escaped}"'


def _hcl_attr_key(k: str) -> str:
    return k if _IDENT.match(k) else _hcl_string(k)


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


def _service_dir_name(key: str) -> str:
    return str(key).replace("_", "-")


def _fragment_out_path(home: Path, key: str) -> Path:
    """Pick terraform/swarm, kubernetes, cluster, or qbittorrent overlay root for this key."""
    hyp = _service_dir_name(str(key))
    candidates: list[Path] = []
    if hyp.startswith("qbittorrent-"):
        suf = hyp[len("qbittorrent-") :]
        candidates.append(home / "kubernetes" / "qbittorrent" / "overlays" / suf)
    candidates.extend(
        [
            home / "terraform" / "swarm" / hyp,
            home / "kubernetes" / hyp,
            home / "terraform" / "cluster" / hyp,
        ]
    )
    for root in candidates:
        if root.is_dir():
            return root / "app.tfvars"
    return home / "terraform" / "swarm" / hyp / "app.tfvars"


def _write_fragment(path: Path, secrets_k8s: dict | None, files_k8s: dict | None) -> None:
    chunks: list[str] = []
    if secrets_k8s:
        chunks.append("secrets = {\n  k8s = " + _fmt_object(secrets_k8s, 1) + "\n}\n")
    if files_k8s:
        chunks.append("secret_files = {\n  k8s = " + _fmt_object(files_k8s, 1) + "\n}\n")
    if not chunks:
        return
    body = "".join(chunks).rstrip() + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file():
        try:
            cur = hcl2.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            raise SystemExit(f"[ERR] cannot parse existing {path}: {exc}") from exc
        if cur.get("secrets") is not None or cur.get("secret_files") is not None:
            raise SystemExit(
                f"[ERR] {path} already defines secrets or secret_files; merge manually or use "
                "scripts/config/consolidate_secrets_into_slice_tfvars.py"
            )
        existing = path.read_text(encoding="utf-8").rstrip()
        path.write_text(existing + "\n\n" + body, encoding="utf-8")
    else:
        path.write_text(body, encoding="utf-8")
    print(f"[OK] wrote {path}", file=sys.stderr)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--tfvars-home", type=Path, required=True)
    ap.add_argument("--vault-config", type=Path, required=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    home = args.tfvars_home.expanduser().resolve()
    vault_cfg = args.vault_config.expanduser().resolve()

    with vault_cfg.open(encoding="utf-8") as handle:
        doc = hcl2.load(handle)

    secrets = doc.get("secrets") or {}
    secret_files = doc.get("secret_files") or {}
    if not isinstance(secrets, dict) or not isinstance(secret_files, dict):
        raise SystemExit("[ERR] secrets / secret_files must be object maps")

    k8s = secrets.get("k8s")
    k8s_files = secret_files.get("k8s") if secret_files else None
    if not isinstance(k8s, dict):
        raise SystemExit("[ERR] expected secrets.k8s object map")
    if k8s_files is not None and not isinstance(k8s_files, dict):
        raise SystemExit("[ERR] expected secret_files.k8s object map")

    keys = sorted(set(k8s.keys()) | (set(k8s_files.keys()) if k8s_files else set()))

    for key in keys:
        sk = {str(key): k8s[key]} if key in k8s else None
        fk = {str(key): k8s_files[key]} if k8s_files and key in k8s_files else None
        if not sk and not fk:
            continue
        out = _fragment_out_path(home, str(key))
        if args.dry_run:
            print(f"[DRY] would write {out}", file=sys.stderr)
            continue
        _write_fragment(out, sk, fk)

    if args.dry_run:
        print(f"[DRY] would rewrite {vault_cfg} to mount_path only", file=sys.stderr)
        return

    vault_cfg.write_text('mount_path = "secret"\n', encoding="utf-8")
    print(f"[OK] rewrote {vault_cfg}", file=sys.stderr)


if __name__ == "__main__":
    main()
