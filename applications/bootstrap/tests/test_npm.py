"""Tests for the Nginx Proxy Manager deployment step."""

from __future__ import annotations

from pathlib import Path

import pytest

from bootstrap.npm import NpmDeployer, NpmError

_CONFIG_TFVARS = (
    "# homelab-config: terraform/components/swarm/nginx_proxy_manager/config\n"
    "provider_config = {\n"
    '  url = "http://swarm-cp-0.local:81"\n'
    '  username = "admin@example.com"\n'
    '  password = "secret"\n'
    "  validate_tls = false\n"
    "}\n"
)


def _make_pipelines(tmp_path: Path) -> None:
    """Create placeholder pipeline scripts so is_file() checks pass."""
    base = tmp_path / "terraform/components/swarm/nginx_proxy_manager/pipeline"
    base.mkdir(parents=True, exist_ok=True)
    (base / "app.sh").write_text("#!/usr/bin/env bash\n", encoding="utf-8")
    (base / "config.sh").write_text("#!/usr/bin/env bash\n", encoding="utf-8")


def _config_file(tmp_path: Path, text: str = _CONFIG_TFVARS) -> Path:
    path = tmp_path / "config.tfvars"
    path.write_text(text, encoding="utf-8")
    return path


def _deployer(
    tmp_path: Path,
    *,
    pipeline_runner,
    http_probe,
    config_text: str = _CONFIG_TFVARS,
) -> NpmDeployer:
    _make_pipelines(tmp_path)
    return NpmDeployer(
        project_root=tmp_path,
        pipeline_runner=pipeline_runner,
        http_probe=http_probe,
        config_tfvars=_config_file(tmp_path, config_text),
        sleep=lambda _: None,
        health_attempts=3,
        health_interval=0,
    )


def test_deploys_app_then_config_after_healthcheck(tmp_path, caplog) -> None:
    """Happy path runs app, health-checks, then config, in order."""
    order: list[str] = []

    def runner(script: Path) -> int:
        order.append(script.name)
        return 0

    deployer = _deployer(tmp_path, pipeline_runner=runner, http_probe=lambda _: 200)

    with caplog.at_level("INFO"):
        deployer.run()

    assert order == ["app.sh", "config.sh"]
    assert "admin API is healthy" in caplog.text


def test_config_not_run_when_app_fails(tmp_path) -> None:
    """A failing app pipeline aborts before health check and config."""
    calls: list[str] = []

    def runner(script: Path) -> int:
        calls.append(script.name)
        return 1 if script.name == "app.sh" else 0

    probed = {"count": 0}

    def probe(_: str) -> int:
        probed["count"] += 1
        return 200

    deployer = _deployer(tmp_path, pipeline_runner=runner, http_probe=probe)

    with pytest.raises(NpmError):
        deployer.run()

    assert calls == ["app.sh"]
    assert probed["count"] == 0


def test_config_not_run_when_healthcheck_fails(tmp_path) -> None:
    """If the admin API never answers, config is not applied."""
    calls: list[str] = []

    def runner(script: Path) -> int:
        calls.append(script.name)
        return 0

    deployer = _deployer(tmp_path, pipeline_runner=runner, http_probe=lambda _: None)

    with pytest.raises(NpmError):
        deployer.run()

    assert calls == ["app.sh"]


def test_healthcheck_accepts_auth_required_response(tmp_path, caplog) -> None:
    """A 401 from the admin API counts as healthy (NPM is answering)."""
    order: list[str] = []

    def runner(script: Path) -> int:
        order.append(script.name)
        return 0

    deployer = _deployer(tmp_path, pipeline_runner=runner, http_probe=lambda _: 401)

    with caplog.at_level("INFO"):
        deployer.run()

    assert order == ["app.sh", "config.sh"]


def test_healthcheck_polls_until_ready(tmp_path) -> None:
    """The health check retries until the admin API responds."""
    statuses = iter([None, None, 200])
    order: list[str] = []

    def runner(script: Path) -> int:
        order.append(script.name)
        return 0

    deployer = _deployer(
        tmp_path,
        pipeline_runner=runner,
        http_probe=lambda _: next(statuses),
    )
    deployer.run()

    assert order == ["app.sh", "config.sh"]


def test_backend_cache_cleared_but_lock_and_state_preserved(tmp_path) -> None:
    """Each slice's .terraform is removed; lock file and state are kept."""
    order: list[str] = []

    def runner(script: Path) -> int:
        order.append(script.name)
        return 0

    deployer = _deployer(tmp_path, pipeline_runner=runner, http_probe=lambda _: 200)

    slices = [
        tmp_path / "terraform/components/swarm/nginx_proxy_manager/app",
        tmp_path / "terraform/components/swarm/nginx_proxy_manager/config",
    ]
    for slice_dir in slices:
        (slice_dir / ".terraform").mkdir(parents=True, exist_ok=True)
        (slice_dir / ".terraform" / "terraform.tfstate").write_text("{}", "utf-8")
        (slice_dir / ".terraform.lock.hcl").write_text("# lock", "utf-8")

    deployer.run()

    for slice_dir in slices:
        assert not (slice_dir / ".terraform").exists()
        assert (slice_dir / ".terraform.lock.hcl").exists()
    assert order == ["app.sh", "config.sh"]


def test_missing_admin_url_raises(tmp_path) -> None:
    """A blank provider_config url raises before deploying config."""
    config_text = (
        "provider_config = {\n"
        '  url = ""\n'
        '  username = "admin"\n'
        "}\n"
    )
    calls: list[str] = []

    def runner(script: Path) -> int:
        calls.append(script.name)
        return 0

    deployer = _deployer(
        tmp_path,
        pipeline_runner=runner,
        http_probe=lambda _: 200,
        config_text=config_text,
    )

    with pytest.raises(NpmError):
        deployer.run()

    assert calls == ["app.sh"]


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(pytest.main([__file__]))
