"""Deploy MinIO via docker compose onto the host named in ``minio.env``.

The target host is centralized in ``.config/docker/minio.env`` as
``MINIO_HOSTNAME``. When that key is missing the operator is prompted (defaulting
to ``swarm-cp-0.local``) and the answer is persisted back into ``minio.env`` so
future runs are non-interactive. The compose file and env are copied into a
self-contained ``~/minio`` directory on the target so the operator can manage the
stack themselves afterwards.
"""

from __future__ import annotations

import logging
import time
from collections.abc import Callable
from dataclasses import replace
from pathlib import Path

from bootstrap.paths import PROJECT_ROOT, display_path
from bootstrap.prompt import OperatorPrompt
from bootstrap.remote import (
    RemoteClient,
    RemoteError,
    RemoteTarget,
    connect,
    default_client_factory,
    ensure_docker,
    parse_target,
    sudo_prefix,
)

logger = logging.getLogger(__name__)

_MINIO_ENV_RELATIVE = Path(".config") / "docker" / "minio.env"
_MINIO_COMPOSE_SOURCE = Path("docker") / "docker-compose.minio.yaml"
_MINIO_CONFIG_TAG = "# homelab-config: docker/minio"
_MINIO_HOSTNAME_KEY = "MINIO_HOSTNAME"
_MINIO_DEFAULT_HOST = "swarm-cp-0.local"
_MINIO_DEFAULT_USER = "nodadyoushutup"
# Path the repo compose uses for its env_file; rewritten to a co-located file.
_COMPOSE_ENV_REF = "../.config/docker/minio.env"
_REMOTE_DIR_NAME = "minio"
_REMOTE_COMPOSE_NAME = "docker-compose.yaml"
_REMOTE_ENV_NAME = "minio.env"
_CONTAINER_NAME = "minio"
_HEALTH_ATTEMPTS = 30
_HEALTH_INTERVAL_SECONDS = 5


class MinioError(RemoteError):
    """Raised when MinIO cannot be deployed to the target host."""


class MinioDeployer:
    """Deploy and health-check MinIO on the host declared in ``minio.env``."""

    def __init__(
        self,
        project_root: Path = PROJECT_ROOT,
        prompt: OperatorPrompt | None = None,
        client_factory: Callable[[RemoteTarget], RemoteClient] | None = None,
        minio_env: Path | None = None,
        compose_source: Path | None = None,
        sleep: Callable[[float], None] = time.sleep,
        health_attempts: int = _HEALTH_ATTEMPTS,
        health_interval: float = _HEALTH_INTERVAL_SECONDS,
    ) -> None:
        """Initialize the MinIO deployer.

        Args:
            project_root: Repository root (for relative log paths and scripts).
            prompt: Operator prompt collaborator.
            client_factory: Factory that connects and returns a remote client.
            minio_env: Path to ``minio.env``; defaults under ``project_root``.
            compose_source: Local compose file to deploy; defaults to the repo
                ``docker/docker-compose.minio.yaml``.
            sleep: Sleep function (injectable for tests).
            health_attempts: Number of health poll attempts.
            health_interval: Seconds between health poll attempts.
        """
        self._project_root = project_root
        self._prompt = prompt or OperatorPrompt()
        self._client_factory = client_factory or default_client_factory
        self._docker_script = project_root / "scripts" / "install" / "docker.sh"
        self._minio_env = (
            minio_env if minio_env is not None else project_root / _MINIO_ENV_RELATIVE
        )
        self._compose_source = (
            compose_source
            if compose_source is not None
            else project_root / _MINIO_COMPOSE_SOURCE
        )
        self._sleep = sleep
        self._health_attempts = health_attempts
        self._health_interval = health_interval

    def _rel(self, path: Path | str) -> str:
        """Format a path relative to the project root for display."""
        return display_path(path, root=self._project_root)

    def run(self) -> None:
        """Ensure MinIO is online on the configured host.

        If MinIO is already running it is left untouched. If it exists but is
        stopped it is started. Only when it is absent are the compose files
        deployed and the stack brought up. Existing remote files are never
        overwritten.

        Raises:
            MinioError: If MinIO cannot be brought online.
        """
        target = self._resolve_target()
        label = f"MinIO host {target.hostname}"
        logger.info("Ensuring MinIO is online on %s", target.hostname)
        client = connect(
            target,
            prompt=self._prompt,
            client_factory=self._client_factory,
            label=label,
        )
        try:
            ensure_docker(
                client,
                label=label,
                docker_script=self._docker_script,
                script_display=self._rel(self._docker_script),
            )
            sudo = sudo_prefix(client)
            state = self._container_state(client, sudo)
            if state == "running":
                logger.info(
                    "MinIO is already online on %s; leaving it as-is",
                    target.hostname,
                )
                return
            if state == "stopped":
                logger.info(
                    "MinIO container exists but is offline on %s; starting it",
                    target.hostname,
                )
                self._start_container(client, sudo)
                self._wait_healthy(client, sudo)
                return

            logger.info(
                "MinIO is not deployed on %s; deploying via docker compose",
                target.hostname,
            )
            remote_dir = f"{self._remote_home(client)}/{_REMOTE_DIR_NAME}"
            compose_path = f"{remote_dir}/{_REMOTE_COMPOSE_NAME}"
            env_path = f"{remote_dir}/{_REMOTE_ENV_NAME}"
            self._ensure_remote_dir(client, remote_dir)
            self._upload_if_absent(
                client, compose_path, self._compose_content(), "MinIO compose file"
            )
            self._upload_if_absent(
                client, env_path, self._env_content(), "MinIO env file"
            )
            self._compose_up(client, sudo, compose_path)
            self._wait_healthy(client, sudo)
        finally:
            client.close()

    def _container_state(self, client: RemoteClient, sudo: str) -> str:
        """Return the MinIO container state: ``running``/``stopped``/``absent``."""
        result = client.run(
            f"{sudo}docker inspect -f '{{{{.State.Running}}}}' {_CONTAINER_NAME}"
        )
        if result.exit_code != 0:
            return "absent"
        return "running" if result.stdout.strip() == "true" else "stopped"

    def _start_container(self, client: RemoteClient, sudo: str) -> None:
        """Start the existing (stopped) MinIO container without recreating it."""
        result = client.run(f"{sudo}docker start {_CONTAINER_NAME}")
        if result.exit_code != 0:
            raise MinioError(
                f"Could not start the MinIO container "
                f"(exit {result.exit_code}): {result.stderr.strip()}"
            )

    def _resolve_target(self) -> RemoteTarget:
        """Resolve the MinIO SSH target from ``minio.env`` (prompt+persist).

        Returns:
            The target host to deploy MinIO to.
        """
        hostname = self._read_hostname()
        if hostname:
            logger.info(
                "Using MinIO host %s from %s (%s)",
                hostname,
                self._rel(self._minio_env),
                _MINIO_HOSTNAME_KEY,
            )
        else:
            logger.warning(
                "%s not set in %s; asking which machine should run MinIO.",
                _MINIO_HOSTNAME_KEY,
                self._rel(self._minio_env),
            )
            answer = self._prompt.ask(
                "Which machine should run MinIO (SSH host or user@host)?",
                default=_MINIO_DEFAULT_HOST,
            )
            hostname = answer.strip() or _MINIO_DEFAULT_HOST
            self._persist_hostname(hostname)
        target = parse_target(hostname)
        if not target.username:
            target = replace(target, username=_MINIO_DEFAULT_USER)
        return target

    def _read_hostname(self) -> str | None:
        """Return ``MINIO_HOSTNAME`` from ``minio.env`` if present and set."""
        if not self._minio_env.is_file():
            return None
        for line in self._minio_env.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped.startswith("#") or "=" not in stripped:
                continue
            key, _, value = stripped.partition("=")
            if key.strip() == _MINIO_HOSTNAME_KEY:
                return value.strip().strip('"').strip("'") or None
        return None

    def _persist_hostname(self, hostname: str) -> None:
        """Append ``MINIO_HOSTNAME`` to ``minio.env`` (creating it if needed)."""
        if self._minio_env.is_file():
            text = self._minio_env.read_text(encoding="utf-8")
            if text and not text.endswith("\n"):
                text += "\n"
        else:
            self._minio_env.parent.mkdir(parents=True, exist_ok=True)
            text = f"{_MINIO_CONFIG_TAG}\n"
        text += f"{_MINIO_HOSTNAME_KEY}={hostname}\n"
        self._minio_env.write_text(text, encoding="utf-8")
        logger.info(
            "Persisted %s=%s to %s",
            _MINIO_HOSTNAME_KEY,
            hostname,
            self._rel(self._minio_env),
        )

    def _remote_home(self, client: RemoteClient) -> str:
        """Return the remote user's home directory (absolute)."""
        result = client.run('printf %s "$HOME"')
        home = result.stdout.strip()
        if not home:
            raise MinioError("Could not determine the remote home directory")
        return home

    def _ensure_remote_dir(self, client: RemoteClient, remote_dir: str) -> None:
        """Create the remote MinIO directory (idempotent)."""
        result = client.run(f'mkdir -p "{remote_dir}"')
        if result.exit_code != 0:
            raise MinioError(
                f"Could not create {remote_dir}: {result.stderr.strip()}"
            )

    def _upload_if_absent(
        self, client: RemoteClient, remote_path: str, content: str, label: str
    ) -> None:
        """Write ``content`` to ``remote_path`` unless the file already exists."""
        exists = client.run(f'test -f "{remote_path}"')
        if exists.exit_code == 0:
            logger.info("%s already present at %s; leaving it", label, remote_path)
            return
        result = client.run(f'cat > "{remote_path}"', stdin=content)
        if result.exit_code != 0:
            raise MinioError(
                f"Failed to write {label} to {remote_path}: {result.stderr.strip()}"
            )
        logger.info("Wrote %s to %s", label, remote_path)

    def _compose_content(self) -> str:
        """Return the compose file body adapted for a self-contained deploy."""
        if not self._compose_source.is_file():
            raise MinioError(
                f"MinIO compose file missing: {self._rel(self._compose_source)}"
            )
        text = self._compose_source.read_text(encoding="utf-8")
        # The env now lives beside the compose file inside ~/minio.
        return text.replace(_COMPOSE_ENV_REF, _REMOTE_ENV_NAME)

    def _env_content(self) -> str:
        """Return the MinIO env body (MINIO_HOSTNAME stripped for the container)."""
        if not self._minio_env.is_file():
            raise MinioError(
                f"MinIO env file missing: {self._rel(self._minio_env)}"
            )
        lines = [
            line
            for line in self._minio_env.read_text(encoding="utf-8").splitlines()
            if not line.strip().startswith(f"{_MINIO_HOSTNAME_KEY}=")
        ]
        return "\n".join(lines).strip() + "\n"

    def _compose_up(self, client: RemoteClient, sudo: str, compose_path: str) -> None:
        """Bring the MinIO stack up (idempotent; starts it if stopped)."""
        logger.info("Starting MinIO with docker compose (%s)", compose_path)
        result = client.run(f'{sudo}docker compose -f "{compose_path}" up -d')
        if result.exit_code != 0:
            raise MinioError(
                f"docker compose up failed for MinIO "
                f"(exit {result.exit_code}): {result.stderr.strip()}"
            )

    def _wait_healthy(self, client: RemoteClient, sudo: str) -> None:
        """Poll the MinIO container health until it reports healthy.

        Raises:
            MinioError: If MinIO does not become healthy in time.
        """
        health_cmd = (
            f"{sudo}docker inspect -f "
            f"'{{{{.State.Health.Status}}}}' {_CONTAINER_NAME}"
        )
        for attempt in range(1, self._health_attempts + 1):
            status = client.run(health_cmd).stdout.strip()
            if status == "healthy":
                logger.info("MinIO is healthy and ready")
                return
            logger.info(
                "Waiting for MinIO health (%s) [%d/%d]",
                status or "unknown",
                attempt,
                self._health_attempts,
            )
            if attempt < self._health_attempts:
                self._sleep(self._health_interval)
        raise MinioError(
            f"MinIO did not become healthy after {self._health_attempts} attempts"
        )


__all__ = ["MinioDeployer", "MinioError"]
