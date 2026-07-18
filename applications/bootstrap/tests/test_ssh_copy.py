"""Tests for host ~/.ssh -> .config/.ssh copying."""

from __future__ import annotations

from pathlib import Path

import pytest

from bootstrap.prompt import OperatorPrompt
from bootstrap.ssh_copy import SshConfigCopier, SshCopyError


def _write_ssh_tree(root: Path) -> None:
    """Create a minimal host SSH directory for tests.

    Args:
        root: Directory that should become a fake ``~/.ssh``.
    """
    root.mkdir(parents=True)
    (root / "config").write_text("Host *\n", encoding="utf-8")
    (root / "id_ed25519").write_text("PRIVATE\n", encoding="utf-8")
    (root / "id_ed25519").chmod(0o600)
    (root / "id_ed25519.pub").write_text("PUBLIC\n", encoding="utf-8")
    agent = root / "agent" / "sock"
    agent.parent.mkdir()
    agent.write_text("socket-like\n", encoding="utf-8")


def test_run_skips_when_declined(tmp_path: Path, caplog) -> None:
    """Declining the prompt does not copy SSH files."""
    source = tmp_path / "home" / ".ssh"
    _write_ssh_tree(source)
    project = tmp_path / "repo"
    project.mkdir()

    copier = SshConfigCopier(
        project_root=project,
        source_dir=source,
        prompt=OperatorPrompt(input_func=lambda _: "n"),
    )
    with caplog.at_level("WARNING"):
        copier.run()

    assert "separate site copy" in caplog.text
    assert "highly recommended" in caplog.text
    assert not (project / ".config" / ".ssh").exists()


def test_copy_writes_site_ssh_and_skips_agent(tmp_path: Path, caplog) -> None:
    """copy mirrors SSH files into .config/.ssh and skips agent runtime paths."""
    source = tmp_path / "home" / ".ssh"
    _write_ssh_tree(source)
    project = tmp_path / "repo"
    project.mkdir()

    copier = SshConfigCopier(
        project_root=project,
        source_dir=source,
        prompt=OperatorPrompt(input_func=lambda _: "y"),
    )
    with caplog.at_level("INFO"):
        copier.copy()

    dest = project / ".config" / ".ssh"
    assert (dest / "config").read_text(encoding="utf-8") == "Host *\n"
    assert (dest / "id_ed25519").read_text(encoding="utf-8") == "PRIVATE\n"
    assert (dest / "id_ed25519.pub").read_text(encoding="utf-8") == "PUBLIC\n"
    assert not (dest / "agent").exists()
    assert (dest / "id_ed25519").stat().st_mode & 0o777 == 0o600
    assert "host ~/.ssh unchanged" in caplog.text


def test_run_defaults_yes(tmp_path: Path) -> None:
    """Empty answer accepts the SSH copy prompt."""
    source = tmp_path / "home" / ".ssh"
    _write_ssh_tree(source)
    project = tmp_path / "repo"
    project.mkdir()

    copier = SshConfigCopier(
        project_root=project,
        source_dir=source,
        prompt=OperatorPrompt(input_func=lambda _: ""),
    )
    copier.run()
    assert (project / ".config" / ".ssh" / "config").is_file()


def test_copy_raises_when_source_missing(tmp_path: Path) -> None:
    """Missing host ~/.ssh raises SshCopyError."""
    project = tmp_path / "repo"
    project.mkdir()
    copier = SshConfigCopier(
        project_root=project,
        source_dir=tmp_path / "missing-ssh",
    )
    with pytest.raises(SshCopyError, match="missing"):
        copier.copy()


def test_run_skips_when_dest_exists(tmp_path: Path, caplog) -> None:
    """Existing .config/.ssh is acknowledged and left untouched."""
    source = tmp_path / "home" / ".ssh"
    _write_ssh_tree(source)
    project = tmp_path / "repo"
    dest = project / ".config" / ".ssh"
    dest.mkdir(parents=True)
    (dest / "config").write_text("EXISTING\n", encoding="utf-8")

    prompted: list[str] = []

    copier = SshConfigCopier(
        project_root=project,
        source_dir=source,
        prompt=OperatorPrompt(input_func=lambda _: prompted.append("asked") or "y"),
    )
    with caplog.at_level("INFO"):
        copier.run()

    assert prompted == []
    assert (dest / "config").read_text(encoding="utf-8") == "EXISTING\n"
    assert "already exists" in caplog.text
