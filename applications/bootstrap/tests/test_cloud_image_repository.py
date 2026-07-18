"""Tests for the cloud image repository deployment step."""

from __future__ import annotations

from pathlib import Path

import pytest

from bootstrap.cloud_image_repository import (
    CloudImageRepositoryDeployer,
    CloudImageRepositoryError,
)

_PIPELINE = "terraform/components/swarm/cloud-image-repository/pipeline/app.sh"
_APP_DIR = "terraform/components/swarm/cloud-image-repository/app"


def _make_pipeline(tmp_path: Path) -> None:
    """Create the placeholder pipeline script so is_file() checks pass."""
    script = tmp_path / _PIPELINE
    script.parent.mkdir(parents=True, exist_ok=True)
    script.write_text("#!/usr/bin/env bash\n", encoding="utf-8")


def _deployer(tmp_path: Path, *, pipeline_runner) -> CloudImageRepositoryDeployer:
    _make_pipeline(tmp_path)
    return CloudImageRepositoryDeployer(
        project_root=tmp_path,
        pipeline_runner=pipeline_runner,
    )


def test_deploys_app_slice(tmp_path, caplog) -> None:
    """The happy path runs the app pipeline once."""
    order: list[str] = []

    def runner(script: Path) -> int:
        order.append(script.name)
        return 0

    deployer = _deployer(tmp_path, pipeline_runner=runner)

    with caplog.at_level("INFO"):
        deployer.run()

    assert order == ["app.sh"]
    assert "Cloud image repository is deployed" in caplog.text


def test_pipeline_failure_raises(tmp_path) -> None:
    """A non-zero pipeline exit raises."""
    deployer = _deployer(tmp_path, pipeline_runner=lambda _: 1)

    with pytest.raises(CloudImageRepositoryError):
        deployer.run()


def test_missing_pipeline_raises(tmp_path) -> None:
    """A missing pipeline script raises before running anything."""
    deployer = CloudImageRepositoryDeployer(
        project_root=tmp_path,
        pipeline_runner=lambda _: 0,
    )

    with pytest.raises(CloudImageRepositoryError):
        deployer.run()


def test_backend_cache_cleared_but_lock_preserved(tmp_path) -> None:
    """The slice's .terraform is removed; the lock file is kept."""
    deployer = _deployer(tmp_path, pipeline_runner=lambda _: 0)

    slice_dir = tmp_path / _APP_DIR
    (slice_dir / ".terraform").mkdir(parents=True, exist_ok=True)
    (slice_dir / ".terraform" / "terraform.tfstate").write_text("{}", "utf-8")
    (slice_dir / ".terraform.lock.hcl").write_text("# lock", "utf-8")

    deployer.run()

    assert not (slice_dir / ".terraform").exists()
    assert (slice_dir / ".terraform.lock.hcl").exists()


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(pytest.main([__file__]))
