"""Tests for the GitHub Actions runner deployment step."""

from __future__ import annotations

from collections.abc import Iterable
from pathlib import Path

import pytest

from bootstrap.gha_runner import GhaRunnerDeployer, GhaRunnerError

_PIPELINES = (
    "gha-runner-amd64/pipeline/app.sh",
    "gha-runner-arm64/pipeline/app.sh",
)


class FakePrompt:
    """Prompt stub returning a canned architecture answer."""

    def __init__(self, *, arch: str = "both") -> None:
        """Store the canned architecture answer."""
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


def _slice_key(script: Path) -> str:
    """Identify a pipeline by ``<component>/<script>``."""
    return f"{script.parent.parent.name}/{script.name}"


def _recording_runner(order: list[str], failures: Iterable[str] = ()):
    fail = set(failures)

    def runner(script: Path) -> int:
        key = _slice_key(script)
        order.append(key)
        return 1 if key in fail else 0

    return runner


def _deployer(tmp_path: Path, *, prompt: FakePrompt, pipeline_runner) -> GhaRunnerDeployer:
    _make_pipelines(tmp_path)
    return GhaRunnerDeployer(
        project_root=tmp_path,
        prompt=prompt,
        pipeline_runner=pipeline_runner,
    )


def test_deploys_both_runners(tmp_path, caplog) -> None:
    """Default (both) deploys the amd64 then arm64 runner slices."""
    order: list[str] = []
    deployer = _deployer(
        tmp_path,
        prompt=FakePrompt(arch="both"),
        pipeline_runner=_recording_runner(order),
    )

    with caplog.at_level("INFO"):
        deployer.run()

    assert order == ["gha-runner-amd64/app.sh", "gha-runner-arm64/app.sh"]


def test_amd64_only(tmp_path) -> None:
    """Selecting amd64 deploys only the amd64 runner slice."""
    order: list[str] = []
    deployer = _deployer(
        tmp_path,
        prompt=FakePrompt(arch="amd64"),
        pipeline_runner=_recording_runner(order),
    )
    deployer.run()

    assert order == ["gha-runner-amd64/app.sh"]


def test_none_deploys_nothing(tmp_path, caplog) -> None:
    """Answering 'none' deploys no runner slices."""
    order: list[str] = []
    deployer = _deployer(
        tmp_path,
        prompt=FakePrompt(arch="none"),
        pipeline_runner=_recording_runner(order),
    )

    with caplog.at_level("INFO"):
        deployer.run()

    assert order == []
    assert "No GitHub Actions runner architectures selected" in caplog.text


def test_unknown_arch_defaults_to_both(tmp_path, caplog) -> None:
    """An unrecognized architecture answer falls back to both runners."""
    order: list[str] = []
    deployer = _deployer(
        tmp_path,
        prompt=FakePrompt(arch="risc-v"),
        pipeline_runner=_recording_runner(order),
    )

    with caplog.at_level("WARNING"):
        deployer.run()

    assert order == ["gha-runner-amd64/app.sh", "gha-runner-arm64/app.sh"]
    assert "defaulting to both" in caplog.text


def test_second_runner_not_run_when_first_fails(tmp_path) -> None:
    """A failing runner slice aborts before the next architecture."""
    order: list[str] = []
    deployer = _deployer(
        tmp_path,
        prompt=FakePrompt(arch="both"),
        pipeline_runner=_recording_runner(order, failures={"gha-runner-amd64/app.sh"}),
    )

    with pytest.raises(GhaRunnerError):
        deployer.run()

    assert order == ["gha-runner-amd64/app.sh"]


def test_backend_cache_cleared_but_lock_preserved(tmp_path) -> None:
    """Each deployed slice's .terraform is removed; lock files are kept."""
    order: list[str] = []
    deployer = _deployer(
        tmp_path,
        prompt=FakePrompt(arch="both"),
        pipeline_runner=_recording_runner(order),
    )

    slices = [
        tmp_path / "terraform/components/swarm/gha-runner-amd64/app",
        tmp_path / "terraform/components/swarm/gha-runner-arm64/app",
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
