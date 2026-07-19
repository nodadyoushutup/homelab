"""Repo-root and ``.config`` directory discovery for the pipeline library.

Mirrors the bash pipelines, which compute ``ROOT_DIR`` from the script location
and default ``CONFIG_DIR`` to ``<repo>/.config`` (overridable via the
``CONFIG_DIR`` environment variable).
"""

from __future__ import annotations

import os
from pathlib import Path


# Marker that uniquely identifies the repository root from any nested location.
_ROOT_MARKERS = ("scripts/terraform/pipelines/__init__.py",)


def find_repo_root(start: Path | str) -> Path:
    """Walk upward from ``start`` until the pipelines package is found."""

    current = Path(start).resolve()
    candidates = [current, *current.parents] if current.is_file() else [current, *current.parents]
    for candidate in candidates:
        if all((candidate / marker).exists() for marker in _ROOT_MARKERS):
            return candidate
    raise RuntimeError(f"Unable to locate homelab repo root from {start!r}")


def repo_root() -> Path:
    """Repo root inferred from this module's location."""

    return Path(__file__).resolve().parents[3]


def config_dir(root: Path | None = None) -> Path:
    """Resolve ``CONFIG_DIR`` (env override wins, else ``<repo>/.config``)."""

    override = os.environ.get("CONFIG_DIR")
    if override:
        return Path(override)
    base = root if root is not None else repo_root()
    return base / ".config"


def tfvars_home_dir(root: Path | None = None) -> Path:
    """Resolve ``TFVARS_HOME_DIR`` (env override, else ``CONFIG_DIR``)."""

    override = os.environ.get("TFVARS_HOME_DIR")
    if override:
        return Path(override)
    return config_dir(root)
