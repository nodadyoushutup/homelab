"""Filesystem paths for the bootstrap application."""

from __future__ import annotations

from pathlib import Path

# applications/bootstrap/paths.py -> applications/bootstrap -> applications -> repo root
PROJECT_ROOT = Path(__file__).resolve().parents[2]
VENV_DIR = PROJECT_ROOT / ".venv"
CONFIG_DIR = PROJECT_ROOT / ".config"


def display_path(path: Path | str, *, root: Path = PROJECT_ROOT) -> str:
    """Return a repo-relative path string for logs and prompts.

    Uses the logical path under ``root`` and does not follow symlinks out of the
    tree (important for ``.venv/bin/python3`` → system interpreter). Paths
    outside ``root`` fall back to their original string form.

    Args:
        path: Filesystem path to display.
        root: Repository root used as the relative base.

    Returns:
        POSIX-style relative path when under ``root``, otherwise ``str(path)``.
    """
    candidate = Path(path)
    root_resolved = root.resolve()
    absolute = candidate if candidate.is_absolute() else root_resolved / candidate
    # absolute() does not follow symlinks; resolve() can escape the repo.
    try:
        return absolute.absolute().relative_to(root_resolved).as_posix()
    except ValueError:
        return candidate.as_posix()
