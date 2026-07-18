"""Tests for the Jenkins deployment step."""

from __future__ import annotations

from collections.abc import Iterable
from pathlib import Path

import pytest

from bootstrap.jenkins import JenkinsDeployer, JenkinsError

_CONFIG_TFVARS = (
    "# homelab-config: terraform/components/swarm/jenkins-controller/config\n"
    "provider_config = {\n"
    "  jenkins = {\n"
    '    server_url = "http://jenkins.example:8080"\n'
    '    username   = "admin"\n'
    '    password   = "secret"\n'
    "  }\n"
    "}\n"
)

_PIPELINES = (
    "jenkins-controller/pipeline/app.sh",
    "jenkins-controller/pipeline/config.sh",
    "jenkins-agent-amd64/pipeline/app.sh",
    "jenkins-agent-arm64/pipeline/app.sh",
)


class FakePrompt:
    """Prompt stub returning a canned architecture answer."""

    def __init__(self, *, arch: str = "both") -> None:
        """Store the canned architecture answer.

        Args:
            arch: Answer for the architecture selection.
        """
        self._arch = arch

    def ask(self, question: str, *, default: str = "") -> str:
        """Return the canned architecture answer."""
        return self._arch


def _make_pipelines(tmp_path: Path) -> None:
    """Create placeholder pipeline scripts so is_file() checks pass."""
    base = tmp_path / "terraform/components/swarm"
    for rel in _PIPELINES:
        script = base / rel
        script.parent.mkdir(parents=True, exist_ok=True)
        script.write_text("#!/usr/bin/env bash\n", encoding="utf-8")


def _config_file(tmp_path: Path, text: str = _CONFIG_TFVARS) -> Path:
    path = tmp_path / "config.tfvars"
    path.write_text(text, encoding="utf-8")
    return path


def _slice_key(script: Path) -> str:
    """Identify a pipeline by ``<component>/<script>`` (app.sh repeats across slices)."""
    return f"{script.parent.parent.name}/{script.name}"


def _deployer(
    tmp_path: Path,
    *,
    prompt: FakePrompt,
    pipeline_runner,
    http_probe,
    config_text: str = _CONFIG_TFVARS,
) -> JenkinsDeployer:
    _make_pipelines(tmp_path)
    return JenkinsDeployer(
        project_root=tmp_path,
        prompt=prompt,
        pipeline_runner=pipeline_runner,
        http_probe=http_probe,
        config_tfvars=_config_file(tmp_path, config_text),
        sleep=lambda _: None,
        health_attempts=3,
        health_interval=0,
    )


def _recording_runner(order: list[str], failures: Iterable[str] = ()):
    fail = set(failures)

    def runner(script: Path) -> int:
        key = _slice_key(script)
        order.append(key)
        return 1 if key in fail else 0

    return runner


def test_deploys_controller_then_both_agents(tmp_path, caplog) -> None:
    """Default (both) runs controller app, health, config, then both agents."""
    order: list[str] = []
    deployer = _deployer(
        tmp_path,
        prompt=FakePrompt(arch="both"),
        pipeline_runner=_recording_runner(order),
        http_probe=lambda _: 200,
    )

    with caplog.at_level("INFO"):
        deployer.run()

    assert order == [
        "jenkins-controller/app.sh",
        "jenkins-controller/config.sh",
        "jenkins-agent-amd64/app.sh",
        "jenkins-agent-arm64/app.sh",
    ]
    assert "Jenkins controller is healthy" in caplog.text


def test_none_arch_deploys_controller_only(tmp_path) -> None:
    """Answering 'none' still deploys the controller but no build agents."""
    order: list[str] = []
    deployer = _deployer(
        tmp_path,
        prompt=FakePrompt(arch="none"),
        pipeline_runner=_recording_runner(order),
        http_probe=lambda _: 200,
    )

    deployer.run()

    assert order == [
        "jenkins-controller/app.sh",
        "jenkins-controller/config.sh",
    ]


def test_amd64_only(tmp_path) -> None:
    """Selecting amd64 deploys the controller and only the amd64 agent."""
    order: list[str] = []
    deployer = _deployer(
        tmp_path,
        prompt=FakePrompt(arch="amd64"),
        pipeline_runner=_recording_runner(order),
        http_probe=lambda _: 200,
    )
    deployer.run()

    assert order == [
        "jenkins-controller/app.sh",
        "jenkins-controller/config.sh",
        "jenkins-agent-amd64/app.sh",
    ]


def test_arm64_only(tmp_path) -> None:
    """Selecting arm64 deploys the controller and only the arm64 agent."""
    order: list[str] = []
    deployer = _deployer(
        tmp_path,
        prompt=FakePrompt(arch="arm64"),
        pipeline_runner=_recording_runner(order),
        http_probe=lambda _: 200,
    )
    deployer.run()

    assert order == [
        "jenkins-controller/app.sh",
        "jenkins-controller/config.sh",
        "jenkins-agent-arm64/app.sh",
    ]


def test_unknown_arch_answer_defaults_to_both(tmp_path, caplog) -> None:
    """An unrecognized architecture answer falls back to both agents."""
    order: list[str] = []
    deployer = _deployer(
        tmp_path,
        prompt=FakePrompt(arch="sparc"),
        pipeline_runner=_recording_runner(order),
        http_probe=lambda _: 200,
    )

    with caplog.at_level("WARNING"):
        deployer.run()

    assert order[-2:] == [
        "jenkins-agent-amd64/app.sh",
        "jenkins-agent-arm64/app.sh",
    ]
    assert "defaulting to both" in caplog.text


def test_config_and_agents_not_run_when_controller_app_fails(tmp_path) -> None:
    """A failing controller app aborts before health check, config, and agents."""
    order: list[str] = []
    probed = {"count": 0}

    def probe(_: str) -> int:
        probed["count"] += 1
        return 200

    deployer = _deployer(
        tmp_path,
        prompt=FakePrompt(arch="both"),
        pipeline_runner=_recording_runner(
            order, failures={"jenkins-controller/app.sh"}
        ),
        http_probe=probe,
    )

    with pytest.raises(JenkinsError):
        deployer.run()

    assert order == ["jenkins-controller/app.sh"]
    assert probed["count"] == 0


def test_config_not_run_when_healthcheck_fails(tmp_path) -> None:
    """If the controller never answers, config and agents are not applied."""
    order: list[str] = []
    deployer = _deployer(
        tmp_path,
        prompt=FakePrompt(arch="both"),
        pipeline_runner=_recording_runner(order),
        http_probe=lambda _: None,
    )

    with pytest.raises(JenkinsError):
        deployer.run()

    assert order == ["jenkins-controller/app.sh"]


def test_healthcheck_waits_for_starting_controller(tmp_path) -> None:
    """A 503 while Jenkins boots keeps waiting until it returns < 500."""
    statuses = iter([503, 503, 200])
    order: list[str] = []
    deployer = _deployer(
        tmp_path,
        prompt=FakePrompt(arch="amd64"),
        pipeline_runner=_recording_runner(order),
        http_probe=lambda _: next(statuses),
    )
    deployer.run()

    assert order == [
        "jenkins-controller/app.sh",
        "jenkins-controller/config.sh",
        "jenkins-agent-amd64/app.sh",
    ]


def test_missing_server_url_raises(tmp_path) -> None:
    """A blank server_url raises after the app deploy, before health check."""
    config_text = (
        "provider_config = {\n"
        "  jenkins = {\n"
        '    server_url = ""\n'
        "  }\n"
        "}\n"
    )
    order: list[str] = []
    deployer = _deployer(
        tmp_path,
        prompt=FakePrompt(arch="both"),
        pipeline_runner=_recording_runner(order),
        http_probe=lambda _: 200,
        config_text=config_text,
    )

    with pytest.raises(JenkinsError):
        deployer.run()

    assert order == ["jenkins-controller/app.sh"]


def test_backend_cache_cleared_but_lock_preserved(tmp_path) -> None:
    """Each deployed slice's .terraform is removed; lock files are kept."""
    order: list[str] = []
    deployer = _deployer(
        tmp_path,
        prompt=FakePrompt(arch="both"),
        pipeline_runner=_recording_runner(order),
        http_probe=lambda _: 200,
    )

    slices = [
        tmp_path / "terraform/components/swarm/jenkins-controller/app",
        tmp_path / "terraform/components/swarm/jenkins-controller/config",
        tmp_path / "terraform/components/swarm/jenkins-agent-amd64/app",
        tmp_path / "terraform/components/swarm/jenkins-agent-arm64/app",
    ]
    for slice_dir in slices:
        (slice_dir / ".terraform").mkdir(parents=True, exist_ok=True)
        (slice_dir / ".terraform" / "terraform.tfstate").write_text("{}", "utf-8")
        (slice_dir / ".terraform.lock.hcl").write_text("# lock", "utf-8")

    deployer.run()

    for slice_dir in slices:
        assert not (slice_dir / ".terraform").exists()
        assert (slice_dir / ".terraform.lock.hcl").exists()


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(pytest.main([__file__]))
