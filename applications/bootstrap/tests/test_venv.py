"""Tests for project virtualenv ensure and activate logic."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from bootstrap.prompt import OperatorPrompt
from bootstrap.venv import ProjectVenv, VenvEnsureError


class _FakePackageManager:
    """Record whether install was requested."""

    def __init__(self) -> None:
        """Initialize call tracking."""
        self.install_calls = 0

    def install_python_venv(self) -> None:
        """Record an install request."""
        self.install_calls += 1


def _make_venv(tmp_path: Path) -> Path:
    """Create a minimal fake virtualenv tree.

    Args:
        tmp_path: Temporary project root.

    Returns:
        Path to the created ``.venv`` directory.
    """
    venv_dir = tmp_path / ".venv"
    bin_dir = venv_dir / "bin"
    bin_dir.mkdir(parents=True)
    (venv_dir / "pyvenv.cfg").write_text("home = /usr\n", encoding="utf-8")
    (bin_dir / "python3").write_text("#!/bin/sh\n", encoding="utf-8")
    (bin_dir / "python3").chmod(0o755)
    return venv_dir


def test_exists_true_when_pyvenv_cfg_present(tmp_path: Path, caplog) -> None:
    """A directory with pyvenv.cfg counts as an existing venv."""
    venv_dir = _make_venv(tmp_path)

    project = ProjectVenv(project_root=tmp_path, venv_dir=venv_dir)
    with caplog.at_level("INFO"):
        assert project.exists() is True
    assert "exists" in caplog.text


def test_ensure_returns_existing_without_prompt(tmp_path: Path) -> None:
    """Existing venvs short-circuit without prompting."""
    venv_dir = _make_venv(tmp_path)

    prompted: list[str] = []

    def boom(_: str) -> str:
        prompted.append("called")
        return "n"

    project = ProjectVenv(
        project_root=tmp_path,
        venv_dir=venv_dir,
        prompt=OperatorPrompt(input_func=boom),
    )
    assert project.ensure() == venv_dir
    assert prompted == []


def test_ensure_declined_raises(tmp_path: Path) -> None:
    """Operator decline raises VenvEnsureError."""
    project = ProjectVenv(
        project_root=tmp_path,
        prompt=OperatorPrompt(input_func=lambda _: "n"),
    )
    with pytest.raises(VenvEnsureError, match="declined"):
        project.ensure()


def test_ensure_creates_when_venv_module_available(
    tmp_path: Path, monkeypatch, caplog
) -> None:
    """Missing venv is created when python3 -m venv already works."""
    package_manager = _FakePackageManager()
    created: list[list[str]] = []

    def run(cmd: list[str], check: bool = False, **kwargs: object) -> object:
        if cmd[-1] == "--help":
            return type("R", (), {"returncode": 0})()
        created.append(cmd)
        venv_dir = Path(cmd[-1])
        bin_dir = venv_dir / "bin"
        bin_dir.mkdir(parents=True, exist_ok=True)
        (venv_dir / "pyvenv.cfg").write_text("home = /usr\n", encoding="utf-8")
        (bin_dir / "python3").write_text("#!/bin/sh\n", encoding="utf-8")
        return type("R", (), {"returncode": 0})()

    monkeypatch.setattr("bootstrap.venv.subprocess.run", run)

    project = ProjectVenv(
        project_root=tmp_path,
        package_manager=package_manager,  # type: ignore[arg-type]
        prompt=OperatorPrompt(input_func=lambda _: "y"),
    )

    with caplog.at_level("WARNING"):
        result = project.ensure()

    assert result == tmp_path / ".venv"
    assert package_manager.install_calls == 0
    assert created == [["python3", "-m", "venv", str(tmp_path / ".venv")]]
    assert any(record.levelname == "WARNING" for record in caplog.records)


def test_ensure_installs_package_when_venv_missing(
    tmp_path: Path, monkeypatch, caplog
) -> None:
    """OS package install runs when python3 -m venv is unavailable."""
    package_manager = _FakePackageManager()
    help_calls = {"n": 0}

    def run(cmd: list[str], check: bool = False, **kwargs: object) -> object:
        if cmd[-1] == "--help":
            help_calls["n"] += 1
            # First check fails; after package install, succeed.
            returncode = 0 if help_calls["n"] > 1 else 1
            return type("R", (), {"returncode": returncode})()
        venv_dir = Path(cmd[-1])
        bin_dir = venv_dir / "bin"
        bin_dir.mkdir(parents=True, exist_ok=True)
        (venv_dir / "pyvenv.cfg").write_text("home = /usr\n", encoding="utf-8")
        (bin_dir / "python3").write_text("#!/bin/sh\n", encoding="utf-8")
        return type("R", (), {"returncode": 0})()

    monkeypatch.setattr("bootstrap.venv.subprocess.run", run)

    project = ProjectVenv(
        project_root=tmp_path,
        package_manager=package_manager,  # type: ignore[arg-type]
        prompt=OperatorPrompt(input_func=lambda _: "y"),
    )

    with caplog.at_level("INFO"):
        project.ensure()

    assert package_manager.install_calls == 1
    assert "installing via OS package manager" in caplog.text


def test_activate_sets_environ_when_already_active(
    tmp_path: Path, monkeypatch, caplog
) -> None:
    """Activate applies env vars and skips re-exec when already inside the venv."""
    venv_dir = _make_venv(tmp_path)
    monkeypatch.setattr("bootstrap.venv.sys.prefix", str(venv_dir))
    monkeypatch.setattr("bootstrap.venv.os.execv", lambda *_args: (_ for _ in ()).throw(
        AssertionError("execv should not run when already active")
    ))
    monkeypatch.setenv("PATH", "/usr/bin")
    monkeypatch.delenv("VIRTUAL_ENV", raising=False)
    monkeypatch.setenv("PYTHONHOME", "/old")

    project = ProjectVenv(project_root=tmp_path, venv_dir=venv_dir)
    with caplog.at_level("INFO"):
        project.activate()

    assert os.environ["VIRTUAL_ENV"] == str(venv_dir)
    assert os.environ["PATH"].startswith(f"{venv_dir / 'bin'}{os.pathsep}")
    assert "PYTHONHOME" not in os.environ
    assert "already active" in caplog.text


def test_activate_reexecs_when_inactive(tmp_path: Path, monkeypatch, caplog) -> None:
    """Activate re-executes under the venv interpreter when inactive."""
    venv_dir = _make_venv(tmp_path)
    python = venv_dir / "bin" / "python3"
    monkeypatch.setattr("bootstrap.venv.sys.prefix", "/usr")
    monkeypatch.setattr("bootstrap.venv.sys.argv", ["bootstrap.py", "--flag"])

    exec_calls: list[tuple[str, list[str]]] = []

    def fake_execv(path: str, argv: list[str]) -> None:
        exec_calls.append((path, list(argv)))

    monkeypatch.setattr("bootstrap.venv.os.execv", fake_execv)

    project = ProjectVenv(project_root=tmp_path, venv_dir=venv_dir)
    with caplog.at_level("INFO"):
        project.activate()

    assert exec_calls == [(str(python), [str(python), "bootstrap.py", "--flag"])]
    assert "re-executing" in caplog.text


def test_activate_raises_when_venv_missing(tmp_path: Path) -> None:
    """Activate fails clearly when the venv has not been created."""
    project = ProjectVenv(project_root=tmp_path)
    with pytest.raises(VenvEnsureError, match="missing"):
        project.activate()


def test_install_requirements_runs_pip(tmp_path: Path, monkeypatch, caplog) -> None:
    """install_requirements invokes pip against the requirements file."""
    venv_dir = _make_venv(tmp_path)
    req = tmp_path / "requirements.txt"
    req.write_text("coloredlogs\n", encoding="utf-8")

    calls: list[list[str]] = []

    def run(cmd: list[str], check: bool = False, **kwargs: object) -> object:
        calls.append(cmd)
        return type("R", (), {"returncode": 0})()

    monkeypatch.setattr("bootstrap.venv.subprocess.run", run)

    project = ProjectVenv(project_root=tmp_path, venv_dir=venv_dir)
    with caplog.at_level("INFO"):
        project.install_requirements(requirements=req)

    assert calls == [
        [
            str(venv_dir / "bin" / "python3"),
            "-m",
            "pip",
            "install",
            "-q",
            "-r",
            str(req),
        ]
    ]
    assert "Bootstrap dependencies installed" in caplog.text


def test_install_requirements_skips_when_missing(
    tmp_path: Path, monkeypatch, caplog
) -> None:
    """A missing requirements file is skipped without invoking pip."""
    venv_dir = _make_venv(tmp_path)

    def run(cmd: list[str], check: bool = False, **kwargs: object) -> object:
        raise AssertionError("pip should not run when requirements are missing")

    monkeypatch.setattr("bootstrap.venv.subprocess.run", run)

    project = ProjectVenv(project_root=tmp_path, venv_dir=venv_dir)
    with caplog.at_level("INFO"):
        project.install_requirements(requirements=tmp_path / "nope.txt")

    assert "skipping dependency install" in caplog.text


def test_install_requirements_raises_on_failure(tmp_path: Path, monkeypatch) -> None:
    """A pip failure surfaces as VenvEnsureError."""
    import subprocess

    venv_dir = _make_venv(tmp_path)
    req = tmp_path / "requirements.txt"
    req.write_text("coloredlogs\n", encoding="utf-8")

    def run(cmd: list[str], check: bool = False, **kwargs: object) -> object:
        raise subprocess.CalledProcessError(1, cmd)

    monkeypatch.setattr("bootstrap.venv.subprocess.run", run)

    project = ProjectVenv(project_root=tmp_path, venv_dir=venv_dir)
    with pytest.raises(VenvEnsureError, match="dependencies"):
        project.install_requirements(requirements=req)
