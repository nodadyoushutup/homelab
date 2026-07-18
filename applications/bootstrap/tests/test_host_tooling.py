"""Tests for host tooling installation."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from bootstrap.host_tooling import HostToolingError, HostToolingInstaller
from bootstrap.prompt import OperatorPrompt


def test_run_skips_when_declined(tmp_path: Path, caplog) -> None:
    """Declining the prompt skips the install script."""
    script = tmp_path / "scripts" / "install" / "automation_tooling.sh"
    script.parent.mkdir(parents=True)
    script.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")

    installer = HostToolingInstaller(
        project_root=tmp_path,
        script_path=script,
        prompt=OperatorPrompt(input_func=lambda _: "n"),
    )
    with caplog.at_level("INFO"):
        installer.run()

    assert "Skipping host tooling install" in caplog.text


def test_install_runs_script(tmp_path: Path, monkeypatch, caplog) -> None:
    """install executes the automation tooling script from the repo root."""
    script = tmp_path / "scripts" / "install" / "automation_tooling.sh"
    script.parent.mkdir(parents=True)
    script.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")

    calls: list[list[str]] = []

    def fake_run(cmd: list[str], check: bool, cwd: str) -> None:
        calls.append(cmd)
        assert check is True
        assert cwd == str(tmp_path)

    monkeypatch.setattr("bootstrap.host_tooling.subprocess.run", fake_run)

    installer = HostToolingInstaller(
        project_root=tmp_path,
        script_path=script,
        prompt=OperatorPrompt(input_func=lambda _: "y"),
    )
    with caplog.at_level("INFO"):
        installer.install()

    assert calls == [[str(script)]]
    assert "Host tooling install complete" in caplog.text
    assert script.stat().st_mode & 0o111


def test_install_raises_when_script_fails(tmp_path: Path, monkeypatch) -> None:
    """Non-zero script exit becomes HostToolingError."""
    script = tmp_path / "automation_tooling.sh"
    script.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
    script.chmod(0o755)

    def fake_run(*_args: object, **_kwargs: object) -> None:
        raise subprocess.CalledProcessError(1, [str(script)])

    monkeypatch.setattr("bootstrap.host_tooling.subprocess.run", fake_run)

    installer = HostToolingInstaller(project_root=tmp_path, script_path=script)
    with pytest.raises(HostToolingError, match="failed"):
        installer.install()


def test_run_defaults_yes_on_empty_answer(tmp_path: Path, monkeypatch) -> None:
    """Empty operator answer accepts the host tooling prompt."""
    script = tmp_path / "automation_tooling.sh"
    script.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    script.chmod(0o755)

    ran = {"value": False}

    def fake_run(*_args: object, **_kwargs: object) -> None:
        ran["value"] = True

    monkeypatch.setattr("bootstrap.host_tooling.subprocess.run", fake_run)

    installer = HostToolingInstaller(
        project_root=tmp_path,
        script_path=script,
        prompt=OperatorPrompt(input_func=lambda _: ""),
    )
    installer.run()
    assert ran["value"] is True
