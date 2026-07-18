"""Deploy the cloud image repository Swarm service right after NPM.

This is a single ``app`` slice (a replicated ``docker_service``) with no config
slice, no per-architecture split, and no operator question — it simply runs its
Terraform pipeline. The slice's ``.terraform/`` cache is cleared first so init
re-pulls remote state cleanly, exactly like the other Terraform deploy steps.
"""

from __future__ import annotations

import logging
from pathlib import Path

from bootstrap.paths import PROJECT_ROOT, display_path
from bootstrap.terraform_deploy import (
    PipelineRunner,
    TerraformDeployError,
    clean_backend_cache,
    default_pipeline_runner,
    run_pipeline,
)

logger = logging.getLogger(__name__)

_COMPONENT = Path("terraform") / "components" / "swarm" / "cloud-image-repository"
_APP_DIR = _COMPONENT / "app"
_APP_PIPELINE = _COMPONENT / "pipeline" / "app.sh"


class CloudImageRepositoryError(TerraformDeployError):
    """Raised when the cloud image repository cannot be deployed."""


class CloudImageRepositoryDeployer:
    """Deploy the cloud image repository ``app`` slice."""

    def __init__(
        self,
        project_root: Path = PROJECT_ROOT,
        pipeline_runner: PipelineRunner | None = None,
    ) -> None:
        """Initialize the deployer.

        Args:
            project_root: Repository root.
            pipeline_runner: Runs a pipeline script and returns its exit code.
        """
        self._project_root = project_root
        self._pipeline_runner = pipeline_runner or default_pipeline_runner(project_root)

    def _rel(self, path: Path | str) -> str:
        """Format a path relative to the project root for display."""
        return display_path(path, root=self._project_root)

    def run(self) -> None:
        """Deploy the cloud image repository service.

        Raises:
            CloudImageRepositoryError: If the deploy fails.
        """
        logger.info("Deploying the cloud image repository")
        clean_backend_cache(
            self._project_root / _APP_DIR, rel=self._rel, logger=logger
        )
        run_pipeline(
            self._pipeline_runner,
            self._project_root / _APP_PIPELINE,
            label="Cloud image repository app",
            rel=self._rel,
            logger=logger,
            error_cls=CloudImageRepositoryError,
        )
        logger.info("Cloud image repository is deployed")


__all__ = ["CloudImageRepositoryDeployer", "CloudImageRepositoryError"]
