"""CLI entry for the bootstrap application.

Bootstrap runs as an ordered list of indexed steps (see ``_STEPS``). Which steps
actually run is controlled by ``ENABLED_STEPS`` (or the ``BOOTSTRAP_STEPS``
environment variable), so a single stage can be exercised in isolation during
development instead of sitting through the whole flow. The virtualenv/logging
preflight always runs because everything else depends on it.
"""

from __future__ import annotations

import logging
import os
from collections.abc import Callable
from dataclasses import dataclass

from bootstrap.cloud_image_repository import (
    CloudImageRepositoryDeployer,
    CloudImageRepositoryError,
)
from bootstrap.config_ack import ConfigAcknowledger
from bootstrap.config_scaffold import ConfigScaffolder
from bootstrap.gha_runner import GhaRunnerDeployer, GhaRunnerError
from bootstrap.host_tooling import HostToolingError, HostToolingInstaller
from bootstrap.jenkins import JenkinsDeployer, JenkinsError
from bootstrap.logging_setup import configure_colored_logging, configure_logging
from bootstrap.minio import MinioDeployer
from bootstrap.minio_backend import MinioBackendProvisioner
from bootstrap.npm import NpmDeployer, NpmError
from bootstrap.remote import RemoteError
from bootstrap.ssh_copy import SshConfigCopier, SshCopyError
from bootstrap.swarm import SwarmManager
from bootstrap.venv import ProjectVenv, VenvEnsureError

logger = logging.getLogger(__name__)

# Conventional shell exit status for SIGINT (128 + signal number 2).
_EXIT_SIGINT = 130

# Environment override for the enabled step set, e.g. BOOTSTRAP_STEPS="1,5,9"
# or BOOTSTRAP_STEPS="all". Takes precedence over ENABLED_STEPS when set.
_STEPS_ENV_VAR = "BOOTSTRAP_STEPS"


@dataclass(frozen=True)
class _Step:
    """A single bootstrap stage.

    Attributes:
        index: Stable 1-based selector used by ``ENABLED_STEPS``/``BOOTSTRAP_STEPS``.
        name: Human-readable stage name for logs.
        factory: Builds the step object (resolved at call time so tests can patch).
        errors: Exception types that mean "this step failed" (abort with exit 1).
    """

    index: int
    name: str
    factory: Callable[[], object]
    errors: tuple[type[Exception], ...] = ()


# Ordered bootstrap stages. Factories reference the module-level classes by name
# so monkeypatching ``bootstrap.cli.<Class>`` in tests still takes effect.
_STEPS: tuple[_Step, ...] = (
    _Step(1, "Host tooling install", lambda: HostToolingInstaller(), (HostToolingError,)),
    _Step(2, "Config scaffold", lambda: ConfigScaffolder()),
    _Step(3, "Config acknowledge", lambda: ConfigAcknowledger()),
    _Step(4, "SSH config copy", lambda: SshConfigCopier(), (SshCopyError,)),
    _Step(5, "Docker Swarm setup", lambda: SwarmManager(), (RemoteError,)),
    _Step(6, "MinIO deploy", lambda: MinioDeployer(), (RemoteError,)),
    _Step(7, "MinIO Terraform backend", lambda: MinioBackendProvisioner(), (RemoteError,)),
    _Step(8, "Nginx Proxy Manager deploy", lambda: NpmDeployer(), (NpmError,)),
    _Step(
        9,
        "Cloud image repository deploy",
        lambda: CloudImageRepositoryDeployer(),
        (CloudImageRepositoryError,),
    ),
    _Step(10, "Jenkins deploy", lambda: JenkinsDeployer(), (JenkinsError,)),
    _Step(11, "GitHub Actions runners deploy", lambda: GhaRunnerDeployer(), (GhaRunnerError,)),
)

_ALL_STEP_INDICES: frozenset[int] = frozenset(step.index for step in _STEPS)

# Steps to run by default. Edit this while developing to focus on one stage, or
# set it to ``_ALL_STEP_INDICES`` to run the full bootstrap. Currently scoped to
# the cloud image repository only.
ENABLED_STEPS: set[int] = {9}


def main() -> int:
    """Run the bootstrap CLI.

    Returns:
        Process exit code.
    """
    try:
        return _run()
    except KeyboardInterrupt:
        # Prefer a clean log line over a traceback when the operator hits Ctrl+C.
        logger.warning("Interrupted by user; exiting")
        return _EXIT_SIGINT


def _resolve_enabled_steps() -> set[int]:
    """Return the set of step indices to run.

    Honors the ``BOOTSTRAP_STEPS`` environment variable (``all``/``*`` or a
    comma/space separated list of indices); otherwise falls back to
    ``ENABLED_STEPS``.

    Returns:
        Set of enabled step indices.
    """
    raw = os.environ.get(_STEPS_ENV_VAR)
    if raw is None:
        return set(ENABLED_STEPS)
    normalized = raw.strip().lower()
    if normalized in {"all", "*"}:
        return set(_ALL_STEP_INDICES)
    indices = {int(part) for part in normalized.replace(",", " ").split() if part.isdigit()}
    return indices or set(ENABLED_STEPS)


def _run() -> int:
    """Execute the enabled bootstrap steps.

    Returns:
        Process exit code.

    Raises:
        KeyboardInterrupt: Propagated when the operator cancels.
    """
    configure_logging()
    logger.info("Starting bootstrap")

    try:
        project_venv = ProjectVenv()
        project_venv.ensure()
        project_venv.activate()
        # Runs in the re-executed venv process; installs coloredlogs/paramiko/etc.
        project_venv.install_requirements()
    except VenvEnsureError as exc:
        logger.error("%s", exc)
        return 1

    # Safe only after activate (and re-exec into `.venv` when needed).
    configure_colored_logging()
    logger.info("Project virtualenv is ready and active")

    enabled = _resolve_enabled_steps()
    for step in _STEPS:
        marker = "on" if step.index in enabled else "off"
        logger.info("Step %d [%s]: %s", step.index, marker, step.name)

    for step in _STEPS:
        if step.index not in enabled:
            logger.info("Skipping step %d: %s (disabled)", step.index, step.name)
            continue
        logger.info("Running step %d: %s", step.index, step.name)
        try:
            step.factory().run()
        except step.errors as exc:
            logger.error("%s", exc)
            return 1

    logger.info("Bootstrap complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
