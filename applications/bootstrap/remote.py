"""Shared SSH transport and remote host helpers for bootstrap steps.

This module owns the low-level remote primitives reused by the swarm and MinIO
provisioning steps: SSH targets, a paramiko-backed client, connect with a
password fallback, and idempotent Docker installation.
"""

from __future__ import annotations

import ipaddress
import logging
from collections.abc import Callable
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Protocol

from bootstrap.prompt import OperatorPrompt

logger = logging.getLogger(__name__)

_SSH_DEFAULT_PORT = 22


class RemoteError(RuntimeError):
    """Raised when a remote host operation fails."""


class RemoteAuthError(RemoteError):
    """Raised when SSH authentication to a remote host fails."""


@dataclass(frozen=True)
class RemoteTarget:
    """SSH connection target for a remote host.

    Attributes:
        hostname: Remote host or IP address.
        username: SSH username, or ``None`` when not yet known.
        password: Optional SSH password (never logged).
        port: SSH port.
    """

    hostname: str
    username: str | None = None
    password: str | None = None
    port: int = _SSH_DEFAULT_PORT


@dataclass(frozen=True)
class RemoteResult:
    """Result of a remote command.

    Attributes:
        exit_code: Process exit status.
        stdout: Captured standard output.
        stderr: Captured standard error.
    """

    exit_code: int
    stdout: str
    stderr: str


class RemoteClient(Protocol):
    """Minimal remote command execution interface."""

    def run(self, command: str, *, stdin: str | None = None) -> RemoteResult:
        """Run a command on the remote host and return its result."""
        ...

    def close(self) -> None:
        """Close the remote connection."""
        ...


def parse_target(raw: str) -> RemoteTarget:
    """Parse an SSH target string into a :class:`RemoteTarget`.

    Accepts ``host``, ``user@host``, ``user:password@host``, and an optional
    trailing ``:port`` on the host portion (for example ``user@host:2222``).

    Args:
        raw: Raw operator-entered SSH target.

    Returns:
        Parsed target.

    Raises:
        RemoteError: When no hostname can be determined.
    """
    text = raw.strip()
    if not text:
        raise RemoteError("SSH target is empty")

    username: str | None = None
    password: str | None = None
    hostpart = text
    if "@" in text:
        userinfo, hostpart = text.rsplit("@", 1)
        if ":" in userinfo:
            username, password = userinfo.split(":", 1)
        else:
            username = userinfo
        username = username or None
        password = password or None

    port = _SSH_DEFAULT_PORT
    hostname = hostpart
    # Only treat a trailing ":<digits>" as a port (avoid IPv6 ambiguity here).
    if hostpart.count(":") == 1:
        host_candidate, port_candidate = hostpart.rsplit(":", 1)
        if port_candidate.isdigit():
            hostname = host_candidate
            port = int(port_candidate)

    if not hostname:
        raise RemoteError(f"Could not determine hostname from SSH target: {raw!r}")

    return RemoteTarget(
        hostname=hostname, username=username, password=password, port=port
    )


def target_to_ssh(target: RemoteTarget) -> str:
    """Render a target as an ``user@host[:port]`` SSH string (no password).

    Passwords are intentionally omitted so serialized targets never contain
    secrets.

    Args:
        target: Target to render.

    Returns:
        SSH string suitable for persisting to config.
    """
    user = f"{target.username}@" if target.username else ""
    port = f":{target.port}" if target.port != _SSH_DEFAULT_PORT else ""
    return f"{user}{target.hostname}{port}"


def is_ip_address(value: str) -> bool:
    """Return whether ``value`` is a literal IPv4/IPv6 address.

    Args:
        value: Host string to test.

    Returns:
        ``True`` when ``value`` parses as an IP address.
    """
    try:
        ipaddress.ip_address(value)
    except ValueError:
        return False
    return True


class ParamikoRemoteClient:
    """Remote client backed by paramiko SSH."""

    def __init__(self, target: RemoteTarget) -> None:
        """Connect to ``target`` over SSH.

        Args:
            target: Connection target.

        Raises:
            RemoteAuthError: On authentication failure.
            RemoteError: On other connection or dependency errors.
        """
        try:
            import paramiko
        except ImportError as exc:  # pragma: no cover - depends on environment
            raise RemoteError(
                "paramiko is required for remote setup but is not installed"
            ) from exc

        client = paramiko.SSHClient()
        client.load_system_host_keys()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        try:
            client.connect(
                hostname=target.hostname,
                port=target.port,
                username=target.username,
                password=target.password,
                look_for_keys=True,
                allow_agent=True,
                timeout=30,
            )
        except paramiko.AuthenticationException as exc:
            raise RemoteAuthError(
                f"SSH authentication failed for {target.username}@{target.hostname}"
            ) from exc
        except (paramiko.SSHException, OSError) as exc:
            raise RemoteError(
                f"Could not connect to {target.username}@{target.hostname}: {exc}"
            ) from exc
        self._client = client

    def run(self, command: str, *, stdin: str | None = None) -> RemoteResult:
        """Execute ``command`` on the remote host.

        Args:
            command: Command line to run.
            stdin: Optional data to write to the command's standard input.

        Returns:
            Captured remote result.
        """
        stdin_stream, stdout_stream, stderr_stream = self._client.exec_command(command)
        if stdin is not None:
            stdin_stream.write(stdin)
            stdin_stream.channel.shutdown_write()
        stdout = stdout_stream.read().decode("utf-8", "replace")
        stderr = stderr_stream.read().decode("utf-8", "replace")
        exit_code = stdout_stream.channel.recv_exit_status()
        return RemoteResult(exit_code=exit_code, stdout=stdout, stderr=stderr)

    def close(self) -> None:
        """Close the SSH connection."""
        self._client.close()


def default_client_factory(target: RemoteTarget) -> RemoteClient:
    """Create and connect a :class:`ParamikoRemoteClient`.

    Args:
        target: Connection target.

    Returns:
        A connected remote client.
    """
    return ParamikoRemoteClient(target)


def connect(
    target: RemoteTarget,
    *,
    prompt: OperatorPrompt,
    client_factory: Callable[[RemoteTarget], RemoteClient],
    label: str,
) -> RemoteClient:
    """Connect to ``target``, falling back to a password on auth failure.

    Args:
        target: Connection target (may carry an embedded password).
        prompt: Operator prompt used for the password fallback.
        client_factory: Factory that connects and returns a remote client.
        label: Human-readable node label for logs.

    Returns:
        A connected remote client.

    Raises:
        RemoteError: When authentication ultimately fails.
    """
    try:
        client = client_factory(target)
        logger.info(
            "Connected to %s at %s@%s", label, target.username, target.hostname
        )
        return client
    except RemoteAuthError:
        logger.warning(
            "Key-based SSH auth failed for %s@%s; falling back to password",
            target.username,
            target.hostname,
        )

    password = prompt.ask_secret(
        f"SSH password for {target.username}@{target.hostname}"
    )
    if not password:
        raise RemoteError("SSH authentication failed and no password was provided")
    target = replace(target, password=password)
    try:
        client = client_factory(target)
    except RemoteAuthError as exc:
        raise RemoteError(
            f"SSH authentication failed for {target.username}@{target.hostname}"
        ) from exc
    logger.info(
        "Connected to %s at %s@%s (password auth)",
        label,
        target.username,
        target.hostname,
    )
    return client


def sudo_prefix(client: RemoteClient) -> str:
    """Return ``""`` when the remote is root, else ``"sudo "``.

    Args:
        client: Connected remote client.

    Returns:
        Command prefix to gain root for privileged commands.
    """
    result = client.run("id -u")
    return "" if result.stdout.strip() == "0" else "sudo "


def ensure_docker(
    client: RemoteClient,
    *,
    label: str,
    docker_script: Path,
    script_display: str,
) -> None:
    """Ensure Docker is installed on the remote node (idempotent).

    Args:
        client: Connected remote client.
        label: Human-readable node label for logs.
        docker_script: Local path to the Docker install script.
        script_display: Repo-relative rendering of ``docker_script`` for logs.

    Raises:
        RemoteError: When the remote install fails or the script is missing.
    """
    present = client.run("command -v docker")
    if present.exit_code == 0:
        version = client.run("docker --version")
        logger.info(
            "Docker already installed on %s (%s); skipping install",
            label,
            version.stdout.strip() or "version unknown",
        )
        return

    if not docker_script.is_file():
        raise RemoteError(f"Docker install script missing: {script_display}")

    logger.info("Docker not found on %s; running %s remotely", label, script_display)
    script = docker_script.read_text(encoding="utf-8")
    result = client.run("bash -s", stdin=script)
    if result.exit_code != 0:
        raise RemoteError(
            f"Remote Docker install failed on {label} "
            f"(exit {result.exit_code}): {result.stderr.strip()}"
        )
    logger.info("Docker install complete on %s", label)


def node_hostname(client: RemoteClient) -> str:
    """Return the OS hostname of the remote node.

    Args:
        client: Connected remote client.

    Returns:
        The node's hostname.

    Raises:
        RemoteError: When the hostname cannot be determined.
    """
    name = client.run("hostname").stdout.strip()
    if not name:
        raise RemoteError("Could not determine the remote node hostname")
    return name


__all__ = [
    "ParamikoRemoteClient",
    "RemoteAuthError",
    "RemoteClient",
    "RemoteError",
    "RemoteResult",
    "RemoteTarget",
    "connect",
    "default_client_factory",
    "ensure_docker",
    "is_ip_address",
    "node_hostname",
    "parse_target",
    "sudo_prefix",
    "target_to_ssh",
]
