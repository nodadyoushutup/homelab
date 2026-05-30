#!/usr/bin/env python3
"""
Move CONFIG_DIR top-level service folders into terraform/* and kubernetes/*
trees that mirror homelab repo layout.

Run with --dry-run first. Requires HOMELAB_REPO_ROOT (default: parent of scripts/config).

Use --flatten-only to only normalize tfvars on an already-migrated tree:
  <stack>/<slice>/<slice>.tfvars -> <stack>/<slice>.tfvars,
  .../config/secrets.tfvars -> .../secrets.tfvars (iterative for nested config),
  .../<name>/<name>/*.tfvars -> .../<name>/*.tfvars (duplicate directory cleanup).
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

SKIP_TOPLEVEL = frozenset(
    {
        "terraform",
        "kubernetes",
        "providers",
        ".ssh",
        ".Trash-1000",
        ".Trash-1000",
        ".git",
    }
)
SKIP_PREFIXES = (".",)


def norm(s: str) -> str:
    return "".join(c for c in s.lower() if c not in "-_")


def find_swarm_dir(repo: Path, cfg_name: str) -> str | None:
    swarm = repo / "terraform" / "components" / "swarm"
    if not swarm.is_dir():
        return None
    n = norm(cfg_name)
    for child in sorted(swarm.iterdir()):
        if child.is_dir() and norm(child.name) == n:
            return f"terraform/components/swarm/{child.name}"
    return None


def find_k8s_dir(repo: Path, cfg_name: str) -> str | None:
    k = repo / "kubernetes" / cfg_name
    return f"kubernetes/{cfg_name}" if k.is_dir() else None


def qbittorrent_overlay_dest(repo: Path, cfg_name: str) -> str | None:
    if not cfg_name.startswith("qbittorrent-"):
        return None
    rest = cfg_name[len("qbittorrent-") :]
    ov = repo / "kubernetes" / "qbittorrent" / "overlays" / rest
    if ov.is_dir():
        return f"kubernetes/qbittorrent/overlays/{rest}"
    return None


def explicit_remote(repo: Path, cfg_name: str) -> str | None:
    mapping = {
        "cloudflare": "terraform/components/remote/cloudflare/config",
        "fortigate": "terraform/components/network/fortigate/config",
        "argocd": "terraform/components/cluster/argocd/config",
        "proxmox": "terraform/components/cluster/proxmox/app",
        "talos": "terraform/components/cluster/talos/app",
    }
    rel = mapping.get(cfg_name)
    if not rel:
        return None
    base = repo.joinpath(*rel.split("/"))
    return rel if base.is_dir() else None


ALIASES: dict[str, str] = {
    "victoriametrics": "terraform/components/swarm/victoriametrics/app",
    "webserver-image": "terraform/components/swarm/cloud-image-repository",
}


def resolve_dest(repo: Path, cfg_name: str) -> str | None:
    if cfg_name in SKIP_TOPLEVEL or cfg_name.startswith(SKIP_PREFIXES):
        return None
    if cfg_name == "providers":
        return None
    if cfg_name.endswith(".hcl") or cfg_name.endswith(".md"):
        return None

    alias = ALIASES.get(cfg_name)
    if alias:
        return alias

    hit = explicit_remote(repo, cfg_name)
    if hit:
        return hit

    q = qbittorrent_overlay_dest(repo, cfg_name)
    if q:
        return q

    k = find_k8s_dir(repo, cfg_name)
    if k:
        return k

    s = find_swarm_dir(repo, cfg_name)
    if s:
        return s

    return f"terraform/components/swarm/{cfg_name}"


def replace_prefixes(text: str, replacements: list[tuple[str, str]]) -> str:
    for old, new in sorted(replacements, key=lambda x: -len(x[0])):
        text = text.replace(old, new)
    return text


def _rmdir_if_empty(path: Path) -> None:
    try:
        path.rmdir()
    except OSError:
        pass


def _under_terraform_or_kubernetes(p: Path) -> bool:
    return "terraform" in p.parts or "kubernetes" in p.parts


def flatten_slice_tfvars(cfg: Path) -> None:
    """Move <stack>/<slice>/<slice>.tfvars -> <stack>/<slice>.tfvars (CONFIG_DIR policy)."""
    for name in ("app", "config", "database"):
        for nested in sorted(cfg.rglob(f"{name}/{name}.tfvars")):
            if not nested.is_file() or ".terraform" in nested.parts:
                continue
            if not _under_terraform_or_kubernetes(nested):
                continue
            dest = nested.parent.parent / f"{name}.tfvars"
            if dest.exists():
                print(f"[SKIP] flatten target exists: {dest}", file=sys.stderr)
                continue
            dest.parent.mkdir(parents=True, exist_ok=True)
            nested.rename(dest)
            print(f"[FLATTEN] {nested} -> {dest}", file=sys.stderr)
            _rmdir_if_empty(nested.parent)


def flatten_legacy_config_secrets_iterative(cfg: Path) -> None:
    """Move .../config/secrets.tfvars -> .../secrets.tfvars; repeat for argocd-style nesting."""
    for _ in range(32):
        changed = False
        paths = sorted(
            (
                p
                for p in cfg.rglob("config/secrets.tfvars")
                if p.is_file() and ".terraform" not in p.parts and _under_terraform_or_kubernetes(p)
            ),
            key=lambda p: len(p.parts),
            reverse=True,
        )
        for p in paths:
            if p.parent.name != "config":
                continue
            dest = p.parent.parent / "secrets.tfvars"
            try:
                if p.resolve() == dest.resolve():
                    continue
            except OSError:
                continue
            if dest.exists():
                print(f"[SKIP] secrets flatten target exists: {dest}", file=sys.stderr)
                continue
            dest.parent.mkdir(parents=True, exist_ok=True)
            p.rename(dest)
            print(f"[FLATTEN] {p} -> {dest}", file=sys.stderr)
            _rmdir_if_empty(p.parent)
            changed = True
        if not changed:
            break


def flatten_duplicate_parent_dir_tfvars(cfg: Path) -> None:
    """e.g. .../mcp-code/mcp-code/app.tfvars -> .../mcp-code/app.tfvars."""
    for p in sorted(cfg.rglob("*.tfvars")):
        if not p.is_file() or ".terraform" in p.parts:
            continue
        if not _under_terraform_or_kubernetes(p):
            continue
        par = p.parent
        gp = par.parent
        if gp == par or not gp.name:
            continue
        if par.name != gp.name:
            continue
        dest = gp / p.name
        try:
            if p.resolve() == dest.resolve():
                continue
        except OSError:
            continue
        if dest.exists():
            print(f"[SKIP] duplicate-dir flatten target exists: {dest}", file=sys.stderr)
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        p.rename(dest)
        print(f"[FLATTEN] duplicate-dir {p} -> {dest}", file=sys.stderr)
        _rmdir_if_empty(par)


def run_flatten_passes(cfg: Path) -> None:
    """Run flatten steps until a fixed point (handles ordering between rules)."""
    for _ in range(8):
        before = sum(1 for _ in cfg.rglob("*.tfvars"))
        flatten_slice_tfvars(cfg)
        flatten_legacy_config_secrets_iterative(cfg)
        flatten_duplicate_parent_dir_tfvars(cfg)
        after = sum(1 for _ in cfg.rglob("*.tfvars"))
        if before == after:
            break


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    ap.add_argument("--config-dir", type=Path, default=Path(__file__).resolve().parents[2] / ".config")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--flatten-only", action="store_true", help="Only run tfvars/secrets flatten passes")
    args = ap.parse_args()

    repo: Path = args.repo_root.resolve()
    cfg: Path = args.config_dir.resolve()

    if args.flatten_only:
        if args.dry_run:
            print("[ERR] --flatten-only does not support --dry-run yet; omit --dry-run.", file=sys.stderr)
            raise SystemExit(2)
        run_flatten_passes(cfg)
        return

    moves: list[tuple[Path, Path]] = []
    for child in sorted(cfg.iterdir()):
        if not child.is_dir():
            continue
        if child.name in SKIP_TOPLEVEL or child.name.startswith(SKIP_PREFIXES):
            continue
        rel = resolve_dest(repo, child.name)
        if not rel:
            print(f"[SKIP] no repo match for {child.name}", file=sys.stderr)
            continue
        dest = cfg / rel
        if dest.exists():
            print(f"[SKIP] destination already exists: {dest}", file=sys.stderr)
            continue
        moves.append((child, dest))

    providers_src = cfg / "providers"
    providers_dst = cfg / "terraform" / "providers"
    if providers_src.is_dir():
        moves.append((providers_src, providers_dst))

    for src, dst in moves:
        print(f"[PLAN] {src} -> {dst}", file=sys.stderr)

    if args.dry_run:
        return

    replacements: list[tuple[str, str]] = []
    for src, dst in moves:
        replacements.append((str(src) + "/", str(dst) + "/"))

    for src, dst in moves:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(src), str(dst))

    run_flatten_passes(cfg)

    exts = {".tfvars", ".tf", ".hcl", ".yaml", ".yml", ".env", ".json", ".md", ".sh", ".toml"}
    for path in cfg.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() not in exts and path.name not in {"Dockerfile", "Jenkinsfile"}:
            continue
        try:
            raw = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        new = replace_prefixes(raw, replacements)
        if new != raw:
            path.write_text(new, encoding="utf-8")
            print(f"[PATCH] {path}", file=sys.stderr)


if __name__ == "__main__":
    main()
