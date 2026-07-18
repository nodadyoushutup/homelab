"""Tests for bootstrap path constants."""

from __future__ import annotations

from pathlib import Path

from bootstrap.paths import CONFIG_DIR, PROJECT_ROOT, VENV_DIR, display_path


def test_project_root_is_repo_root() -> None:
    """PROJECT_ROOT points at the repository root containing applications/."""
    assert (PROJECT_ROOT / "applications" / "bootstrap").is_dir()
    assert (PROJECT_ROOT / "bootstrap.py").is_file()


def test_venv_dir_is_under_project_root() -> None:
    """VENV_DIR is the conventional project-root .venv path."""
    assert VENV_DIR == PROJECT_ROOT / ".venv"


def test_config_dir_is_under_project_root() -> None:
    """CONFIG_DIR is the conventional project-root .config path."""
    assert CONFIG_DIR == PROJECT_ROOT / ".config"


def test_display_path_is_repo_relative(tmp_path: Path) -> None:
    """display_path renders paths relative to the given root."""
    root = tmp_path / "repo"
    target = root / ".config" / "docker" / "site.env"
    target.parent.mkdir(parents=True)
    target.write_text("CONFIG_DIR=\n", encoding="utf-8")

    assert display_path(target, root=root) == ".config/docker/site.env"
    assert display_path(target.resolve(), root=root) == ".config/docker/site.env"


def test_display_path_keeps_symlink_targets_inside_repo(tmp_path: Path) -> None:
    """Symlinks that resolve outside the repo still display as repo-relative."""
    root = tmp_path / "repo"
    bin_dir = root / ".venv" / "bin"
    bin_dir.mkdir(parents=True)
    python = bin_dir / "python3"
    python.symlink_to("/usr/bin/python3")

    assert display_path(python, root=root) == ".venv/bin/python3"
