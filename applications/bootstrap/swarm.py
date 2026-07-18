"""Provision the mandatory Docker Swarm control plane node (swarm-cp-0)."""

from __future__ import annotations

import logging
from collections.abc import Callable
from dataclasses import replace
from pathlib import Path

from bootstrap.paths import PROJECT_ROOT, display_path
from bootstrap.prompt import OperatorPrompt
from bootstrap.remote import (
    RemoteAuthError,
    RemoteClient,
    RemoteError,
    RemoteResult,
    RemoteTarget,
    connect,
    default_client_factory,
    ensure_docker,
    is_ip_address,
    node_hostname,
    parse_target,
    sudo_prefix,
    target_to_ssh,
)

logger = logging.getLogger(__name__)

# Swarm reuses the shared remote transport; these aliases keep the swarm-facing
# vocabulary while the primitives live in bootstrap.remote.
SwarmTarget = RemoteTarget
SwarmAuthError = RemoteAuthError

_CONTROL_PLANE_NAME = "swarm-cp-0"
_CONTROL_PLANE_DEFAULT_HOST = "swarm-cp-0.local"
_CONTROL_PLANE_DEFAULT_USER = "nodadyoushutup"
_CONTROL_PLANE_DEFAULT_TARGET = (
    f"{_CONTROL_PLANE_DEFAULT_USER}@{_CONTROL_PLANE_DEFAULT_HOST}"
)
_SWARM_MANAGER_PORT = 2377
# Default worker node hostnames used when the operator answers "default".
_WORKER_DEFAULT_NAMES = tuple(f"swarm-wk-{index}" for index in range(5))
_WORKER_DEFAULT_USER = _CONTROL_PLANE_DEFAULT_USER
# Placement labels use the node's own hostname as the key (value is a marker),
# enabling constraints like ``node.labels.<hostname> == true``.
_NODE_LABEL_VALUE = "true"
# Site config file that declares the swarm topology (config-id: docker/swarm).
_SWARM_FILE_RELATIVE = Path(".config") / "docker" / "swarm.yaml"
_SWARM_CONFIG_TAG = "# homelab-config: docker/swarm"


class SwarmError(RemoteError):
    """Raised when the Docker Swarm control plane cannot be provisioned."""


class SwarmManager:
    """Set up the mandatory ``swarm-cp-0`` Docker Swarm control plane node."""

    def __init__(
        self,
        project_root: Path = PROJECT_ROOT,
        prompt: OperatorPrompt | None = None,
        client_factory: Callable[[RemoteTarget], RemoteClient] | None = None,
        swarm_file: Path | None = None,
    ) -> None:
        """Initialize the swarm manager.

        Args:
            project_root: Repository root (for relative log paths and scripts).
            prompt: Operator prompt collaborator.
            client_factory: Factory that connects and returns a remote client.
            swarm_file: Swarm topology file; defaults to
                ``<project_root>/.config/docker/swarm.yaml``.
        """
        self._project_root = project_root
        self._prompt = prompt or OperatorPrompt()
        self._client_factory = client_factory or default_client_factory
        self._docker_script = project_root / "scripts" / "install" / "docker.sh"
        self._swarm_file = (
            swarm_file
            if swarm_file is not None
            else project_root / _SWARM_FILE_RELATIVE
        )
        self.worker_token: str | None = None
        self.manager_token: str | None = None
        self.manager_addr: str | None = None

    def _rel(self, path: Path | str) -> str:
        """Format a path relative to the project root for display.

        Args:
            path: Path to render.

        Returns:
            Repo-relative display string.
        """
        return display_path(path, root=self._project_root)

    def _connect(self, target: RemoteTarget, label: str) -> RemoteClient:
        """Connect to ``target`` with the shared password fallback."""
        return connect(
            target,
            prompt=self._prompt,
            client_factory=self._client_factory,
            label=label,
        )

    def _ensure_docker(self, client: RemoteClient, label: str) -> None:
        """Ensure Docker is installed on ``client`` (idempotent)."""
        ensure_docker(
            client,
            label=label,
            docker_script=self._docker_script,
            script_display=self._rel(self._docker_script),
        )

    def run(self) -> None:
        """Provision the swarm from ``swarm.yaml`` (or interactive capture).

        When ``swarm.yaml`` declares a control plane, the topology is used as-is
        with no prompts. Otherwise the operator is prompted for the control plane
        and worker targets, and the collected topology is written back to
        ``swarm.yaml`` for future runs.

        Raises:
            SwarmError: If the control plane cannot be provisioned.
        """
        cp_target, worker_targets = self._resolve_topology()
        manager = self._connect(cp_target, _CONTROL_PLANE_NAME)
        try:
            self._ensure_docker(manager, _CONTROL_PLANE_NAME)
            manager_sudo = sudo_prefix(manager)
            self._ensure_swarm(manager, cp_target, manager_sudo)
            # Label the control plane node itself for placement.
            cp_hostname = node_hostname(manager)
            self._ensure_node_label(manager, manager_sudo, cp_hostname)
            logger.info(
                "Docker Swarm control plane %s is ready", _CONTROL_PLANE_NAME
            )
            for worker in worker_targets:
                self._try_join_worker(worker, manager, manager_sudo)
            logger.info(
                "Finished joining %d swarm worker node(s)", len(worker_targets)
            )
        finally:
            manager.close()

    def _resolve_topology(self) -> tuple[RemoteTarget, list[RemoteTarget]]:
        """Resolve the control plane and worker targets for provisioning.

        Prefers a control plane declared in ``swarm.yaml``; otherwise prompts the
        operator and persists the collected topology.

        Returns:
            The control-plane target and the list of worker targets.

        Raises:
            SwarmError: When no control-plane target can be determined.
        """
        config = self._read_swarm_config()
        cp_raw = str(config.get("control_plane") or "").strip() if config else ""
        if cp_raw:
            cp_target = self._ensure_username(
                parse_target(cp_raw), _CONTROL_PLANE_DEFAULT_USER
            )
            worker_targets = [
                self._ensure_username(
                    parse_target(str(entry).strip()), _WORKER_DEFAULT_USER
                )
                for entry in (config.get("workers") or [])
                if str(entry).strip()
            ]
            logger.info(
                "Loaded swarm topology from %s (control plane %s, %d worker(s))",
                self._rel(self._swarm_file),
                target_to_ssh(cp_target),
                len(worker_targets),
            )
            return cp_target, worker_targets

        logger.warning(
            "No control plane defined in %s; capturing swarm topology "
            "interactively for the mandatory node %s.",
            self._rel(self._swarm_file),
            _CONTROL_PLANE_NAME,
        )
        cp_target = self._prompt_target()
        worker_targets = self._prompt_worker_targets()
        self._write_swarm_config(cp_target, worker_targets)
        return cp_target, worker_targets

    def _read_swarm_config(self) -> dict | None:
        """Read and parse the swarm topology file, if present.

        Returns:
            The parsed mapping, or ``None`` when the file is missing/empty/invalid.
        """
        if not self._swarm_file.is_file():
            logger.info(
                "No swarm topology file at %s", self._rel(self._swarm_file)
            )
            return None
        import yaml

        try:
            data = yaml.safe_load(self._swarm_file.read_text(encoding="utf-8"))
        except yaml.YAMLError as exc:
            raise SwarmError(
                f"Could not parse swarm topology {self._rel(self._swarm_file)}: {exc}"
            ) from exc
        if not isinstance(data, dict):
            logger.warning(
                "Swarm topology %s is not a mapping; ignoring",
                self._rel(self._swarm_file),
            )
            return None
        return data

    def _write_swarm_config(
        self, cp_target: RemoteTarget, worker_targets: list[RemoteTarget]
    ) -> None:
        """Persist the captured topology to ``swarm.yaml`` (no secrets).

        Args:
            cp_target: Control-plane target.
            worker_targets: Worker targets.
        """
        import yaml

        payload = {
            "control_plane": target_to_ssh(cp_target),
            "workers": [target_to_ssh(worker) for worker in worker_targets],
        }
        body = yaml.safe_dump(payload, sort_keys=False, default_flow_style=False)
        self._swarm_file.parent.mkdir(parents=True, exist_ok=True)
        self._swarm_file.write_text(
            f"{_SWARM_CONFIG_TAG}\n{body}", encoding="utf-8"
        )
        logger.info(
            "Wrote swarm topology to %s for future runs",
            self._rel(self._swarm_file),
        )

    def _ensure_username(self, target: RemoteTarget, default: str) -> RemoteTarget:
        """Return a target guaranteed to carry a username (no prompting).

        Args:
            target: Target that may lack a username.
            default: Username applied when none is present.

        Returns:
            A target with a username set.
        """
        if target.username:
            return target
        return replace(target, username=default)

    def _prompt_target(self) -> RemoteTarget:
        """Ask the operator for the control-plane SSH target.

        Returns:
            A target with at least a hostname and username.

        Raises:
            SwarmError: When the operator provides no target or username.
        """
        raw = self._prompt.ask(
            f"Enter the SSH target for {_CONTROL_PLANE_NAME} "
            "(e.g. user@hostname or user:password@hostname)",
            default=_CONTROL_PLANE_DEFAULT_TARGET,
        )
        if not raw:
            raise SwarmError(f"No SSH target provided for {_CONTROL_PLANE_NAME}")

        target = parse_target(raw)
        if not target.username:
            username = self._prompt.ask(
                f"SSH username for {target.hostname}",
                default=_CONTROL_PLANE_DEFAULT_USER,
            )
            if not username:
                raise SwarmError(f"No SSH username provided for {target.hostname}")
            target = replace(target, username=username)
        return target

    def _ensure_swarm(
        self, client: RemoteClient, target: RemoteTarget, sudo: str
    ) -> None:
        """Ensure the node is an active swarm manager and capture join tokens.

        Args:
            client: Connected remote client.
            target: Connection target (used for the advertise address).
            sudo: Command prefix for docker commands.

        Raises:
            SwarmError: When swarm state cannot be established.
        """
        state = client.run(
            f"{sudo}docker info --format '{{{{.Swarm.LocalNodeState}}}}'"
        ).stdout.strip()

        if state == "active":
            control = client.run(
                f"{sudo}docker info --format '{{{{.Swarm.ControlAvailable}}}}'"
            ).stdout.strip()
            if control == "true":
                logger.info(
                    "%s is already an active swarm manager; reusing existing swarm",
                    _CONTROL_PLANE_NAME,
                )
                self._collect_tokens(client, sudo)
                self._capture_manager_address(client, sudo, target)
                return
            raise SwarmError(
                f"{_CONTROL_PLANE_NAME} is part of a swarm but is not a manager; "
                "cannot manage the control plane"
            )

        logger.info(
            "%s is not in a swarm; initializing a new swarm", _CONTROL_PLANE_NAME
        )
        init_cmd = f"{sudo}docker swarm init"
        if is_ip_address(target.hostname):
            init_cmd += f" --advertise-addr {target.hostname}"
        result = client.run(init_cmd)
        if result.exit_code != 0:
            raise SwarmError(
                f"docker swarm init failed on {_CONTROL_PLANE_NAME} "
                f"(exit {result.exit_code}): {result.stderr.strip()}"
            )
        logger.info("Initialized a new Docker Swarm on %s", _CONTROL_PLANE_NAME)
        self._collect_tokens(client, sudo)
        self._capture_manager_address(client, sudo, target)

    def _capture_manager_address(
        self, client: RemoteClient, sudo: str, target: RemoteTarget
    ) -> None:
        """Record the manager address workers use to join the swarm.

        Prefers the manager's advertised ``Swarm.NodeAddr``; falls back to the
        SSH target host when it is an IP literal.

        Args:
            client: Connected remote client.
            sudo: Command prefix for docker commands.
            target: Control-plane connection target.
        """
        node_addr = client.run(
            f"{sudo}docker info --format '{{{{.Swarm.NodeAddr}}}}'"
        ).stdout.strip()
        if not node_addr and is_ip_address(target.hostname):
            node_addr = target.hostname
        if not node_addr:
            logger.warning(
                "Could not determine the swarm manager address; worker joins "
                "may fail. Re-run with an IP target for %s if needed.",
                _CONTROL_PLANE_NAME,
            )
            self.manager_addr = None
            return
        self.manager_addr = node_addr
        logger.info("Swarm manager address for worker joins: %s", node_addr)

    def _collect_tokens(self, client: RemoteClient, sudo: str) -> None:
        """Capture worker and manager join tokens (values are never logged).

        Args:
            client: Connected remote client.
            sudo: Command prefix for docker commands.

        Raises:
            SwarmError: When either join token cannot be read.
        """
        worker = client.run(f"{sudo}docker swarm join-token -q worker")
        manager = client.run(f"{sudo}docker swarm join-token -q manager")
        if worker.exit_code != 0 or manager.exit_code != 0:
            raise SwarmError(
                f"Failed to read swarm join tokens from {_CONTROL_PLANE_NAME}"
            )
        self.worker_token = worker.stdout.strip()
        self.manager_token = manager.stdout.strip()
        logger.info(
            "Captured swarm join tokens from %s for future nodes "
            "(token values not logged)",
            _CONTROL_PLANE_NAME,
        )

    def _ensure_node_label(
        self, manager: RemoteClient, sudo: str, node: str
    ) -> None:
        """Ensure a swarm node carries a placement label keyed by its hostname.

        Idempotent: the label is only added when absent. Must be run against a
        manager node.

        Args:
            manager: Connected manager client.
            sudo: Command prefix for docker commands.
            node: Swarm node hostname (used as both the node id and label key).

        Raises:
            SwarmError: When the node cannot be inspected or updated.
        """
        inspect = manager.run(
            f"{sudo}docker node inspect {node} "
            f"--format '{{{{ index .Spec.Labels \"{node}\" }}}}'"
        )
        if inspect.exit_code != 0:
            raise SwarmError(
                f"Could not inspect swarm node {node}: {inspect.stderr.strip()}"
            )
        if inspect.stdout.strip() == _NODE_LABEL_VALUE:
            logger.info(
                "Node %s already has placement label %s=%s",
                node,
                node,
                _NODE_LABEL_VALUE,
            )
            return
        result = manager.run(
            f"{sudo}docker node update "
            f"--label-add {node}={_NODE_LABEL_VALUE} {node}"
        )
        if result.exit_code != 0:
            raise SwarmError(
                f"Failed to add placement label to node {node} "
                f"(exit {result.exit_code}): {result.stderr.strip()}"
            )
        logger.info(
            "Added placement label %s=%s to node %s",
            node,
            _NODE_LABEL_VALUE,
            node,
        )

    def _prompt_worker_targets(self) -> list[RemoteTarget]:
        """Prompt for worker node targets, returning the collected list.

        The operator may type an SSH target, ``default`` to expand to the
        ``swarm-wk-0``..``swarm-wk-4`` hosts, or ``done`` to finish.

        Returns:
            The collected worker targets (possibly empty).
        """
        logger.warning(
            "Docker Swarm setup: add worker nodes. Enter an SSH target "
            "(user@hostname), 'default' for %s, or 'done' to finish.",
            ", ".join(f"{name}.local" for name in _WORKER_DEFAULT_NAMES),
        )
        targets: list[RemoteTarget] = []
        while True:
            raw = self._prompt.ask(
                "Worker SSH target ('default' = "
                f"{_WORKER_DEFAULT_NAMES[0]}..{_WORKER_DEFAULT_NAMES[-1]}, "
                "'done' to finish)",
                default="done",
            )
            answer = raw.strip()
            if not answer or answer.lower() == "done":
                logger.info("Captured %d swarm worker node(s)", len(targets))
                return targets
            if answer.lower() == "default":
                targets.extend(
                    RemoteTarget(
                        hostname=f"{name}.local", username=_WORKER_DEFAULT_USER
                    )
                    for name in _WORKER_DEFAULT_NAMES
                )
                continue
            target = parse_target(answer)
            if not target.username:
                username = self._prompt.ask(
                    f"SSH username for {target.hostname}",
                    default=_WORKER_DEFAULT_USER,
                )
                if not username:
                    logger.error(
                        "No SSH username provided for %s; skipping",
                        target.hostname,
                    )
                    continue
                target = replace(target, username=username)
            targets.append(target)

    def _try_join_worker(
        self, target: RemoteTarget, manager: RemoteClient, manager_sudo: str
    ) -> None:
        """Join a single worker node, logging and swallowing worker failures.

        Args:
            target: Worker connection target.
            manager: Connected manager client (used to apply placement labels).
            manager_sudo: Command prefix for docker commands on the manager.
        """
        label = f"{target.username}@{target.hostname}"
        try:
            self._join_worker(target, label, manager, manager_sudo)
        except RemoteError as exc:
            logger.error("Failed to add worker %s: %s", label, exc)

    def _join_worker(
        self,
        target: RemoteTarget,
        label: str,
        manager: RemoteClient,
        manager_sudo: str,
    ) -> None:
        """Connect to a worker, ensure Docker, join it, and apply its label.

        The placement label is ensured even when the node was already in the
        swarm.

        Args:
            target: Worker connection target.
            label: Human-readable node label for logs.
            manager: Connected manager client (used to apply placement labels).
            manager_sudo: Command prefix for docker commands on the manager.

        Raises:
            SwarmError: When the worker cannot be provisioned or joined.
        """
        if not self.worker_token or not self.manager_addr:
            raise SwarmError(
                "Missing worker join token or manager address; "
                "cannot join worker nodes"
            )
        logger.info("Adding swarm worker node %s", label)
        client = self._connect(target, label)
        try:
            self._ensure_docker(client, label)
            self._join_swarm(client, label)
            worker_hostname = node_hostname(client)
        finally:
            client.close()
        # Labels are applied from the manager and kept idempotent even for
        # nodes that were already members of the swarm.
        self._ensure_node_label(manager, manager_sudo, worker_hostname)
        logger.info("Worker node %s is ready", label)

    def _join_swarm(self, client: RemoteClient, label: str) -> None:
        """Join the remote node to the swarm as a worker (idempotent).

        Args:
            client: Connected remote client.
            label: Human-readable node label for logs.

        Raises:
            SwarmError: When the join command fails.
        """
        sudo = sudo_prefix(client)
        state = client.run(
            f"{sudo}docker info --format '{{{{.Swarm.LocalNodeState}}}}'"
        ).stdout.strip()
        if state == "active":
            logger.info("%s is already part of a swarm; skipping join", label)
            return
        # Token is passed on the command line but never written to the logs.
        join_cmd = (
            f"{sudo}docker swarm join --token {self.worker_token} "
            f"{self.manager_addr}:{_SWARM_MANAGER_PORT}"
        )
        result = client.run(join_cmd)
        if result.exit_code != 0:
            raise SwarmError(
                f"docker swarm join failed on {label} "
                f"(exit {result.exit_code}): {result.stderr.strip()}"
            )
        logger.info("Worker %s joined the swarm", label)


__all__ = [
    "RemoteResult",
    "SwarmAuthError",
    "SwarmError",
    "SwarmManager",
    "SwarmTarget",
    "parse_target",
    "target_to_ssh",
]
