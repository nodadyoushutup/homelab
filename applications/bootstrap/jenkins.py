"""Deploy Jenkins: the controller (normal placement) then per-arch build agents.

The controller ``config`` slice talks to the Jenkins API, so we bring the
controller ``app`` online and health-check it before applying ``config``. Build
agents are standalone ``docker_container`` slices (not Swarm services) so they
can pass through ``/dev/kvm`` and bind the Docker socket, and they are split by
CPU architecture because a single service cannot guarantee one replica per
architecture. The operator chooses which agent architectures to run (default:
both; ``none`` deploys just the controller) — that answer is the only question,
since Jenkins is always set up when this step is enabled. Each agent pipeline
self-validates the controller state and image architecture, so this only decides
which agent pipelines execute.
"""

from __future__ import annotations

import logging
import re
import time
from collections.abc import Callable
from pathlib import Path

from bootstrap.paths import PROJECT_ROOT, display_path
from bootstrap.prompt import OperatorPrompt
from bootstrap.terraform_deploy import (
    HttpProbe,
    PipelineRunner,
    TerraformDeployError,
    clean_backend_cache,
    default_http_probe,
    default_pipeline_runner,
    run_pipeline,
    select_architectures,
    wait_healthy,
)

logger = logging.getLogger(__name__)

_SWARM = Path("terraform") / "components" / "swarm"
_CONTROLLER = _SWARM / "jenkins-controller"
_CONTROLLER_APP_DIR = _CONTROLLER / "app"
_CONTROLLER_CONFIG_DIR = _CONTROLLER / "config"
_CONTROLLER_APP_PIPELINE = _CONTROLLER / "pipeline" / "app.sh"
_CONTROLLER_CONFIG_PIPELINE = _CONTROLLER / "pipeline" / "config.sh"
_CONFIG_TFVARS = (
    Path(".config")
    / "terraform"
    / "components"
    / "swarm"
    / "jenkins-controller"
    / "config.tfvars"
)

_HEALTH_ATTEMPTS = 90
_HEALTH_INTERVAL_SECONDS = 5


class JenkinsError(TerraformDeployError):
    """Raised when Jenkins cannot be deployed."""


def _agent_dir(arch: str) -> Path:
    """Return the agent app slice directory for a CPU ``arch``."""
    return _SWARM / f"jenkins-agent-{arch}" / "app"


def _agent_pipeline(arch: str) -> Path:
    """Return the agent app pipeline script for a CPU ``arch``."""
    return _SWARM / f"jenkins-agent-{arch}" / "pipeline" / "app.sh"


class JenkinsDeployer:
    """Deploy the Jenkins controller (app + config) and selected build agents."""

    def __init__(
        self,
        project_root: Path = PROJECT_ROOT,
        prompt: OperatorPrompt | None = None,
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
            prompt: Operator prompt for the confirm + architecture questions.
            pipeline_runner: Runs a pipeline script and returns its exit code.
            http_probe: Probes a URL and returns an HTTP status (or ``None``).
            config_tfvars: Path to the controller config tfvars (for the API URL).
            sleep: Sleep function (injectable for tests).
            health_attempts: Number of health poll attempts.
            health_interval: Seconds between health poll attempts.
        """
        self._project_root = project_root
        self._prompt = prompt or OperatorPrompt()
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
        """Deploy the controller, health-check it, then apply selected agents.

        The agent-architecture question is the only prompt: Jenkins (controller +
        config) always deploys when this step is enabled; the answer only selects
        which build-agent slices run (``none`` deploys just the controller).

        Raises:
            JenkinsError: If any deploy stage fails.
        """
        archs = select_architectures(
            self._prompt, "Jenkins build agent", logger=logger
        )
        logger.info(
            "Deploying Jenkins controller, then agent architectures: %s",
            ", ".join(archs) if archs else "none",
        )

        self._deploy_slice(
            _CONTROLLER_APP_DIR, _CONTROLLER_APP_PIPELINE, "Jenkins controller app"
        )

        server_url = self._read_server_url()
        wait_healthy(
            self._http_probe,
            f"{server_url.rstrip('/')}/login",
            label="Jenkins controller",
            attempts=self._health_attempts,
            interval=self._health_interval,
            sleep=self._sleep,
            logger=logger,
            error_cls=JenkinsError,
        )

        self._deploy_slice(
            _CONTROLLER_CONFIG_DIR,
            _CONTROLLER_CONFIG_PIPELINE,
            "Jenkins controller config",
        )

        for arch in archs:
            self._deploy_slice(
                _agent_dir(arch), _agent_pipeline(arch), f"Jenkins {arch} agent"
            )

        logger.info(
            "Jenkins is deployed (controller + %d agent architecture(s))", len(archs)
        )

    def _deploy_slice(self, slice_dir: Path, pipeline: Path, label: str) -> None:
        """Clear a slice's backend cache, then run its pipeline."""
        clean_backend_cache(
            self._project_root / slice_dir, rel=self._rel, logger=logger
        )
        run_pipeline(
            self._pipeline_runner,
            self._project_root / pipeline,
            label=label,
            rel=self._rel,
            logger=logger,
            error_cls=JenkinsError,
        )

    def _read_server_url(self) -> str:
        """Read the Jenkins API URL from ``provider_config.jenkins.server_url``."""
        if not self._config_tfvars.is_file():
            raise JenkinsError(
                f"Jenkins config tfvars missing: {self._rel(self._config_tfvars)}"
            )
        text = self._config_tfvars.read_text(encoding="utf-8")
        match = re.search(r'server_url\s*=\s*"([^"]*)"', text)
        if not match or not match.group(1):
            raise JenkinsError(
                "Jenkins server_url is not set in "
                f"{self._rel(self._config_tfvars)}"
            )
        return match.group(1)


__all__ = ["JenkinsDeployer", "JenkinsError"]
