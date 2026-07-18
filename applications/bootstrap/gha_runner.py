"""Deploy GitHub Actions self-hosted runners as per-arch standalone containers.

Like the Jenkins build agents, the runners are ``docker_container`` slices (not
Swarm services) so they can pass through ``/dev/kvm`` and bind the Docker socket,
and they are split by CPU architecture (``amd64``/``arm64``) so each variant is
pinned to the right pool host. There is no controller and nothing to
health-check — each runner container simply registers itself with GitHub — so the
operator's architecture choice is the only question (default: both; ``none``
deploys nothing).
"""

from __future__ import annotations

import logging
from pathlib import Path

from bootstrap.paths import PROJECT_ROOT, display_path
from bootstrap.prompt import OperatorPrompt
from bootstrap.terraform_deploy import (
    PipelineRunner,
    TerraformDeployError,
    clean_backend_cache,
    default_pipeline_runner,
    run_pipeline,
    select_architectures,
)

logger = logging.getLogger(__name__)

_SWARM = Path("terraform") / "components" / "swarm"


class GhaRunnerError(TerraformDeployError):
    """Raised when GitHub Actions runners cannot be deployed."""


def _runner_dir(arch: str) -> Path:
    """Return the runner app slice directory for a CPU ``arch``."""
    return _SWARM / f"gha-runner-{arch}" / "app"


def _runner_pipeline(arch: str) -> Path:
    """Return the runner app pipeline script for a CPU ``arch``."""
    return _SWARM / f"gha-runner-{arch}" / "pipeline" / "app.sh"


class GhaRunnerDeployer:
    """Deploy the selected per-arch GitHub Actions runner slices."""

    def __init__(
        self,
        project_root: Path = PROJECT_ROOT,
        prompt: OperatorPrompt | None = None,
        pipeline_runner: PipelineRunner | None = None,
    ) -> None:
        """Initialize the deployer.

        Args:
            project_root: Repository root.
            prompt: Operator prompt for the architecture question.
            pipeline_runner: Runs a pipeline script and returns its exit code.
        """
        self._project_root = project_root
        self._prompt = prompt or OperatorPrompt()
        self._pipeline_runner = pipeline_runner or default_pipeline_runner(project_root)

    def _rel(self, path: Path | str) -> str:
        """Format a path relative to the project root for display."""
        return display_path(path, root=self._project_root)

    def run(self) -> None:
        """Deploy the runner slices for the operator-selected architectures.

        Raises:
            GhaRunnerError: If any runner slice fails to deploy.
        """
        archs = select_architectures(
            self._prompt, "GitHub Actions runner", logger=logger
        )
        if not archs:
            logger.info("No GitHub Actions runner architectures selected; skipping")
            return

        logger.info(
            "Deploying GitHub Actions runner architectures: %s", ", ".join(archs)
        )
        for arch in archs:
            self._deploy_slice(
                _runner_dir(arch),
                _runner_pipeline(arch),
                f"GitHub Actions {arch} runner",
            )
        logger.info(
            "GitHub Actions runners deployed (%d architecture(s))", len(archs)
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
            error_cls=GhaRunnerError,
        )


__all__ = ["GhaRunnerDeployer", "GhaRunnerError"]
