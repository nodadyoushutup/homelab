"""Tests for OS package manager detection and installs."""

from __future__ import annotations

import pytest

from bootstrap.package_manager import (
    PackageManager,
    PackageManagerKind,
    UnsupportedPackageManagerError,
)


def test_detect_prefers_apt(monkeypatch) -> None:
    """apt-get is selected when present."""

    def which(name: str) -> str | None:
        return "/usr/bin/apt-get" if name == "apt-get" else None

    monkeypatch.setattr("bootstrap.package_manager.shutil.which", which)
    plan = PackageManager().detect()
    assert plan.kind is PackageManagerKind.APT
    assert plan.package == "python3-venv"
    assert plan.command == ("sudo", "apt-get", "install", "-y", "python3-venv")


def test_detect_raises_when_unsupported(monkeypatch) -> None:
    """Missing package managers raise a clear error."""
    monkeypatch.setattr("bootstrap.package_manager.shutil.which", lambda _: None)
    with pytest.raises(UnsupportedPackageManagerError):
        PackageManager().detect()


def test_install_python_venv_runs_command(monkeypatch, caplog) -> None:
    """install_python_venv executes the planned command."""
    calls: list[list[str]] = []

    def run(cmd: list[str], check: bool) -> None:
        calls.append(cmd)
        assert check is True

    monkeypatch.setattr(
        "bootstrap.package_manager.shutil.which",
        lambda name: "/usr/bin/dnf" if name == "dnf" else None,
    )
    monkeypatch.setattr("bootstrap.package_manager.subprocess.run", run)

    with caplog.at_level("INFO"):
        PackageManager().install_python_venv()

    assert calls == [["sudo", "dnf", "install", "-y", "python3-venv"]]
    assert "Installing python3-venv with dnf" in caplog.text
