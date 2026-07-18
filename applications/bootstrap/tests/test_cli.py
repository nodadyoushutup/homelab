"""Tests for the bootstrap CLI."""

from __future__ import annotations

import pytest

from bootstrap.cli import main


class FakeVenv:
    """Stub ProjectVenv that records lifecycle calls."""

    def __init__(self) -> None:
        """Track method calls."""
        self.calls: list[str] = []

    def ensure(self) -> object:
        """No-op ensure."""
        self.calls.append("ensure")
        return object()

    def activate(self) -> None:
        """No-op activate."""
        self.calls.append("activate")

    def install_requirements(self) -> None:
        """No-op requirements install."""
        self.calls.append("install")


class FakeStep:
    """Stub for a step object exposing ``run``."""

    def __init__(self) -> None:
        """Track run calls."""
        self.run_called = False

    def run(self) -> None:
        """No-op run."""
        self.run_called = True


def _patch_success(monkeypatch) -> dict[str, object]:
    """Patch the CLI collaborators with success stubs.

    Args:
        monkeypatch: pytest monkeypatch fixture.

    Returns:
        Mapping of instances so tests can assert on them.
    """
    instances = {
        "venv": FakeVenv(),
        "host": FakeStep(),
        "scaffold": FakeStep(),
        "ack": FakeStep(),
        "ssh": FakeStep(),
        "swarm": FakeStep(),
        "minio": FakeStep(),
        "backend": FakeStep(),
        "npm": FakeStep(),
        "cir": FakeStep(),
        "jenkins": FakeStep(),
        "gha": FakeStep(),
    }
    configure_calls: list[str] = []
    instances["configure_calls"] = configure_calls

    monkeypatch.setattr("bootstrap.cli.ProjectVenv", lambda: instances["venv"])
    monkeypatch.setattr(
        "bootstrap.cli.HostToolingInstaller", lambda: instances["host"]
    )
    monkeypatch.setattr(
        "bootstrap.cli.ConfigScaffolder", lambda: instances["scaffold"]
    )
    monkeypatch.setattr(
        "bootstrap.cli.ConfigAcknowledger", lambda: instances["ack"]
    )
    monkeypatch.setattr("bootstrap.cli.SshConfigCopier", lambda: instances["ssh"])
    monkeypatch.setattr("bootstrap.cli.SwarmManager", lambda: instances["swarm"])
    monkeypatch.setattr("bootstrap.cli.MinioDeployer", lambda: instances["minio"])
    monkeypatch.setattr(
        "bootstrap.cli.MinioBackendProvisioner", lambda: instances["backend"]
    )
    monkeypatch.setattr("bootstrap.cli.NpmDeployer", lambda: instances["npm"])
    monkeypatch.setattr(
        "bootstrap.cli.CloudImageRepositoryDeployer", lambda: instances["cir"]
    )
    monkeypatch.setattr(
        "bootstrap.cli.JenkinsDeployer", lambda: instances["jenkins"]
    )
    monkeypatch.setattr(
        "bootstrap.cli.GhaRunnerDeployer", lambda: instances["gha"]
    )
    monkeypatch.setattr(
        "bootstrap.cli.configure_logging",
        lambda: configure_calls.append("stdlib"),
    )
    monkeypatch.setattr(
        "bootstrap.cli.configure_colored_logging",
        lambda: configure_calls.append("colored"),
    )
    # Exercise the full step flow unless a test overrides the selection.
    monkeypatch.setenv("BOOTSTRAP_STEPS", "all")
    return instances


def test_main_returns_zero_when_all_steps_succeed(monkeypatch, caplog) -> None:
    """main runs every step in order and completes."""
    instances = _patch_success(monkeypatch)

    with caplog.at_level("INFO"):
        assert main() == 0

    assert instances["venv"].calls == ["ensure", "activate", "install"]
    assert instances["host"].run_called is True
    assert instances["scaffold"].run_called is True
    assert instances["ack"].run_called is True
    assert instances["ssh"].run_called is True
    assert instances["swarm"].run_called is True
    assert instances["minio"].run_called is True
    assert instances["backend"].run_called is True
    assert instances["npm"].run_called is True
    assert instances["cir"].run_called is True
    assert instances["jenkins"].run_called is True
    assert instances["gha"].run_called is True
    assert instances["configure_calls"] == ["stdlib", "colored"]
    assert "Starting bootstrap" in caplog.text
    assert "Bootstrap complete" in caplog.text


def test_config_steps_run_after_dependency_install(monkeypatch) -> None:
    """Host tooling install must run before config scaffold/acknowledge."""
    order: list[str] = []
    instances = _patch_success(monkeypatch)

    monkeypatch.setattr(
        instances["host"], "run", lambda: order.append("host")
    )
    monkeypatch.setattr(
        instances["scaffold"], "run", lambda: order.append("scaffold")
    )
    monkeypatch.setattr(instances["ack"], "run", lambda: order.append("ack"))

    assert main() == 0
    assert order == ["host", "scaffold", "ack"]


def test_main_returns_one_when_venv_ensure_fails(monkeypatch, caplog) -> None:
    """main exits non-zero when virtualenv ensure raises."""
    from bootstrap.venv import VenvEnsureError

    class FailingVenv:
        """Stub ProjectVenv that fails on ensure."""

        def ensure(self) -> object:
            """Raise ensure failure."""
            raise VenvEnsureError("declined")

        def activate(self) -> None:
            """Should not be reached."""
            raise AssertionError("activate should not run after ensure failure")

        def install_requirements(self) -> None:
            """Should not be reached."""
            raise AssertionError("install should not run after ensure failure")

    monkeypatch.setattr("bootstrap.cli.ProjectVenv", FailingVenv)
    monkeypatch.setattr("bootstrap.cli.configure_logging", lambda: None)
    monkeypatch.setattr("bootstrap.cli.configure_colored_logging", lambda: None)

    with caplog.at_level("ERROR"):
        assert main() == 1

    assert "declined" in caplog.text


def test_main_skips_colored_logging_when_ensure_fails(monkeypatch) -> None:
    """coloredlogs setup must not run before the venv is ready."""
    from bootstrap.venv import VenvEnsureError

    class FailingVenv:
        """Stub ProjectVenv that fails on ensure."""

        def ensure(self) -> object:
            """Raise ensure failure."""
            raise VenvEnsureError("declined")

        def activate(self) -> None:
            """Unused."""
            return None

        def install_requirements(self) -> None:
            """Unused."""
            return None

    colored_called = {"value": False}

    monkeypatch.setattr("bootstrap.cli.ProjectVenv", FailingVenv)
    monkeypatch.setattr("bootstrap.cli.configure_logging", lambda: None)
    monkeypatch.setattr(
        "bootstrap.cli.configure_colored_logging",
        lambda: colored_called.__setitem__("value", True),
    )

    assert main() == 1
    assert colored_called["value"] is False


def test_main_returns_one_when_requirements_install_fails(
    monkeypatch, caplog
) -> None:
    """main exits non-zero when dependency install raises."""
    from bootstrap.venv import VenvEnsureError

    instances = _patch_success(monkeypatch)

    def _boom() -> None:
        raise VenvEnsureError("pip failed")

    monkeypatch.setattr(instances["venv"], "install_requirements", _boom)

    with caplog.at_level("ERROR"):
        assert main() == 1

    assert "pip failed" in caplog.text


def test_main_handles_keyboard_interrupt(monkeypatch, caplog) -> None:
    """Ctrl+C exits cleanly with status 130 and no traceback."""
    instances = _patch_success(monkeypatch)

    def _cancel() -> None:
        raise KeyboardInterrupt

    monkeypatch.setattr(instances["host"], "run", _cancel)

    with caplog.at_level("WARNING"):
        assert main() == 130

    assert "Interrupted by user; exiting" in caplog.text


def test_main_returns_one_when_host_tooling_fails(monkeypatch, caplog) -> None:
    """main exits non-zero when host tooling install fails."""
    from bootstrap.host_tooling import HostToolingError

    instances = _patch_success(monkeypatch)

    def _boom() -> None:
        raise HostToolingError("install failed")

    monkeypatch.setattr(instances["host"], "run", _boom)

    with caplog.at_level("ERROR"):
        assert main() == 1

    assert "install failed" in caplog.text


def test_main_returns_one_when_ssh_copy_fails(monkeypatch, caplog) -> None:
    """main exits non-zero when SSH copy fails."""
    from bootstrap.ssh_copy import SshCopyError

    instances = _patch_success(monkeypatch)

    def _boom() -> None:
        raise SshCopyError("ssh missing")

    monkeypatch.setattr(instances["ssh"], "run", _boom)

    with caplog.at_level("ERROR"):
        assert main() == 1

    assert "ssh missing" in caplog.text


def test_main_returns_one_when_swarm_fails(monkeypatch, caplog) -> None:
    """main exits non-zero when swarm setup fails."""
    from bootstrap.swarm import SwarmError

    instances = _patch_success(monkeypatch)

    def _boom() -> None:
        raise SwarmError("swarm init failed")

    monkeypatch.setattr(instances["swarm"], "run", _boom)

    with caplog.at_level("ERROR"):
        assert main() == 1

    assert "swarm init failed" in caplog.text


def test_main_returns_one_when_minio_fails(monkeypatch, caplog) -> None:
    """main exits non-zero when MinIO deployment fails."""
    from bootstrap.minio import MinioError

    instances = _patch_success(monkeypatch)

    def _boom() -> None:
        raise MinioError("minio unhealthy")

    monkeypatch.setattr(instances["minio"], "run", _boom)

    with caplog.at_level("ERROR"):
        assert main() == 1

    assert "minio unhealthy" in caplog.text


def test_main_returns_one_when_npm_fails(monkeypatch, caplog) -> None:
    """main exits non-zero when NPM deployment fails."""
    from bootstrap.npm import NpmError

    instances = _patch_success(monkeypatch)

    def _boom() -> None:
        raise NpmError("npm apply failed")

    monkeypatch.setattr(instances["npm"], "run", _boom)

    with caplog.at_level("ERROR"):
        assert main() == 1

    assert "npm apply failed" in caplog.text


def test_only_enabled_steps_run(monkeypatch, caplog) -> None:
    """BOOTSTRAP_STEPS scopes execution to the selected indices only."""
    instances = _patch_success(monkeypatch)
    monkeypatch.setenv("BOOTSTRAP_STEPS", "10")

    with caplog.at_level("INFO"):
        assert main() == 0

    assert instances["jenkins"].run_called is True
    for key in (
        "host", "scaffold", "ack", "ssh", "swarm", "minio", "backend", "npm",
        "cir", "gha",
    ):
        assert instances[key].run_called is False
    assert "Skipping step 1" in caplog.text


def test_enabled_steps_constant_used_when_env_absent(monkeypatch) -> None:
    """With no env override, the ENABLED_STEPS constant selects what runs."""
    instances = _patch_success(monkeypatch)
    monkeypatch.delenv("BOOTSTRAP_STEPS", raising=False)
    monkeypatch.setattr("bootstrap.cli.ENABLED_STEPS", {8})

    assert main() == 0

    assert instances["npm"].run_called is True
    assert instances["jenkins"].run_called is False
    assert instances["host"].run_called is False


def test_main_returns_one_when_cloud_image_repository_fails(
    monkeypatch, caplog
) -> None:
    """main exits non-zero when cloud image repository deployment fails."""
    from bootstrap.cloud_image_repository import CloudImageRepositoryError

    instances = _patch_success(monkeypatch)

    def _boom() -> None:
        raise CloudImageRepositoryError("cir apply failed")

    monkeypatch.setattr(instances["cir"], "run", _boom)

    with caplog.at_level("ERROR"):
        assert main() == 1

    assert "cir apply failed" in caplog.text


def test_main_returns_one_when_jenkins_fails(monkeypatch, caplog) -> None:
    """main exits non-zero when Jenkins deployment fails."""
    from bootstrap.jenkins import JenkinsError

    instances = _patch_success(monkeypatch)

    def _boom() -> None:
        raise JenkinsError("jenkins apply failed")

    monkeypatch.setattr(instances["jenkins"], "run", _boom)

    with caplog.at_level("ERROR"):
        assert main() == 1

    assert "jenkins apply failed" in caplog.text


def test_main_returns_one_when_gha_runner_fails(monkeypatch, caplog) -> None:
    """main exits non-zero when GHA runner deployment fails."""
    from bootstrap.gha_runner import GhaRunnerError

    instances = _patch_success(monkeypatch)

    def _boom() -> None:
        raise GhaRunnerError("gha apply failed")

    monkeypatch.setattr(instances["gha"], "run", _boom)

    with caplog.at_level("ERROR"):
        assert main() == 1

    assert "gha apply failed" in caplog.text


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(pytest.main([__file__]))
