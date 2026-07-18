"""Deploy Nginx Proxy Manager first so the rest of the stack has a domain.

Runs the existing Terraform pipelines (which handle ``terraform init`` on their
own, including a fresh, never-initialized slice): first the ``app`` slice to
bring the NPM service online, then — once the NPM admin API health-checks — the
``config`` slice to apply certificates and proxy hosts. Terraform reconciles
whatever state exists to match the tfvars, so this is safe to re-run.
"""

from __future__ import annotations

import logging
import re
import time
from collections.abc import Callable
from pathlib import Path

from bootstrap.paths import PROJECT_ROOT, display_path
from bootstrap.terraform_deploy import (
    HttpProbe,
    PipelineRunner,
    TerraformDeployError,
    clean_backend_cache,
    default_http_probe,
    default_pipeline_runner,
    run_pipeline,
    wait_healthy,
)

logger = logging.getLogger(__name__)

_COMPONENT = Path("terraform") / "components" / "swarm" / "nginx_proxy_manager"
_APP_DIR = _COMPONENT / "app"
_CONFIG_DIR = _COMPONENT / "config"
_APP_PIPELINE = _COMPONENT / "pipeline" / "app.sh"
_CONFIG_PIPELINE = _COMPONENT / "pipeline" / "config.sh"
_CONFIG_TFVARS = (
    Path(".config")
    / "terraform"
    / "components"
    / "swarm"
    / "nginx_proxy_manager"
    / "config.tfvars"
)
_HEALTH_ATTEMPTS = 60
_HEALTH_INTERVAL_SECONDS = 5


class NpmError(TerraformDeployError):
    """Raised when Nginx Proxy Manager cannot be deployed."""


class NpmDeployer:
    """Deploy the NPM app slice, health-check it, then the config slice."""

    def __init__(
        self,
        project_root: Path = PROJECT_ROOT,
        pipeline_runner: PipelineRunner | None = None,
        http_probe: HttpProbe | None = None,
        config_tfvars: Path | None = None,
        sleep: Callable[[float], None] = time.sleep,
        health_attempts: int = _HEALTH_ATTEMPTS,
        health_interval: float = _HEALTH_INTERVAL_SECONDS,
    ) -> None:
        """Initialize the deployer.

        Args:
            project_root: Repository root.
            pipeline_runner: Runs a pipeline script and returns its exit code.
            http_probe: Probes a URL and returns an HTTP status (or ``None``).
            config_tfvars: Path to the NPM config tfvars (for the admin URL).
            sleep: Sleep function (injectable for tests).
            health_attempts: Number of health poll attempts.
            health_interval: Seconds between health poll attempts.
        """
        self._project_root = project_root
        self._pipeline_runner = pipeline_runner or default_pipeline_runner(project_root)
        self._http_probe = http_probe or default_http_probe
        self._config_tfvars = (
            config_tfvars if config_tfvars is not None else project_root / _CONFIG_TFVARS
        )
        self._sleep = sleep
        self._health_attempts = health_attempts
        self._health_interval = health_interval

    def _rel(self, path: Path | str) -> str:
        """Format a path relative to the project root for display."""
        return display_path(path, root=self._project_root)

    def run(self) -> None:
        """Deploy NPM app, wait for its admin API, then apply NPM config.

        Raises:
            NpmError: If any stage fails.
        """
        logger.info(
            "Deploying Nginx Proxy Manager first so the rest of the stack can "
            "use real domains pointed at the swarm."
        )
        clean_backend_cache(self._project_root / _APP_DIR, rel=self._rel, logger=logger)
        run_pipeline(
            self._pipeline_runner,
            self._project_root / _APP_PIPELINE,
            label="Nginx Proxy Manager app",
            rel=self._rel,
            logger=logger,
            error_cls=NpmError,
        )

        admin_url = self._read_admin_url()
        wait_healthy(
            self._http_probe,
            f"{admin_url.rstrip('/')}/api/",
            label="Nginx Proxy Manager admin API",
            attempts=self._health_attempts,
            interval=self._health_interval,
            sleep=self._sleep,
            logger=logger,
            error_cls=NpmError,
        )

        clean_backend_cache(
            self._project_root / _CONFIG_DIR, rel=self._rel, logger=logger
        )
        run_pipeline(
            self._pipeline_runner,
            self._project_root / _CONFIG_PIPELINE,
            label="Nginx Proxy Manager config",
            rel=self._rel,
            logger=logger,
            error_cls=NpmError,
        )
        logger.info("Nginx Proxy Manager is deployed and configured")

    def _read_admin_url(self) -> str:
        """Read the NPM admin API URL from ``provider_config.url`` in the tfvars."""
        if not self._config_tfvars.is_file():
            raise NpmError(
                f"NPM config tfvars missing: {self._rel(self._config_tfvars)}"
            )
        text = self._config_tfvars.read_text(encoding="utf-8")
        block = re.search(r"provider_config\s*=\s*\{(.*?)\}", text, re.S)
        if not block:
            raise NpmError(
                "Could not find provider_config in "
                f"{self._rel(self._config_tfvars)}"
            )
        match = re.search(r'url\s*=\s*"([^"]*)"', block.group(1))
        if not match or not match.group(1):
            raise NpmError(
                "NPM admin url is not set in "
                f"{self._rel(self._config_tfvars)}"
            )
        return match.group(1)


__all__ = ["NpmDeployer", "NpmError"]
