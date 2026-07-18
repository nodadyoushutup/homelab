"""Tests for Docker Swarm control-plane provisioning."""

from __future__ import annotations

from pathlib import Path

import pytest

from bootstrap.prompt import OperatorPrompt
from bootstrap.remote import RemoteError
from bootstrap.swarm import (
    RemoteResult,
    SwarmAuthError,
    SwarmError,
    SwarmManager,
    SwarmTarget,
    parse_target,
    target_to_ssh,
)


class FakeRemoteClient:
    """Scripted remote client keyed by command substrings."""

    def __init__(
        self,
        responses: list[tuple[str, RemoteResult]],
        hostname: str = "node-host",
    ) -> None:
        """Initialize with ordered (substring, result) pairs."""
        self._responses = responses
        self._hostname = hostname
        self.commands: list[str] = []
        self.stdin_scripts: list[str] = []
        self.closed = False

    def run(self, command: str, *, stdin: str | None = None) -> RemoteResult:
        """Return the first matching scripted result."""
        self.commands.append(command)
        if stdin is not None:
            self.stdin_scripts.append(stdin)
        for substring, result in self._responses:
            if substring in command:
                return result
        # Default: report a hostname; unmatched node label commands succeed.
        if command.strip() == "hostname":
            return RemoteResult(0, self._hostname, "")
        return RemoteResult(0, "", "")

    def close(self) -> None:
        """Mark the client closed."""
        self.closed = True


def _ok(stdout: str = "") -> RemoteResult:
    return RemoteResult(0, stdout, "")


def _prompt(inputs: list[str], secrets: list[str] | None = None) -> OperatorPrompt:
    input_iter = iter(inputs)
    secret_iter = iter(secrets or [])
    return OperatorPrompt(
        input_func=lambda _: next(input_iter),
        secret_func=lambda _: next(secret_iter),
    )


def _forbidden_prompt() -> OperatorPrompt:
    """A prompt that fails the test if any input is requested."""

    def _fail(_: str) -> str:
        raise AssertionError("prompt should not be called in file-driven mode")

    return OperatorPrompt(input_func=_fail, secret_func=_fail)


def _manager(
    tmp_path: Path,
    *,
    prompt: OperatorPrompt,
    client_factory,
    swarm_file: Path | None = None,
) -> SwarmManager:
    """Build a SwarmManager whose topology file defaults to a missing path.

    Interactive tests rely on the ``swarm.yaml`` file being absent so the
    manager prompts; file-driven tests pass an explicit ``swarm_file``.
    """
    return SwarmManager(
        prompt=prompt,
        client_factory=client_factory,
        swarm_file=swarm_file or (tmp_path / "missing" / "swarm.yaml"),
    )


def test_parse_target_variants() -> None:
    """parse_target handles user, password, and port forms."""
    assert parse_target("user@host") == SwarmTarget(
        hostname="host", username="user", password=None, port=22
    )
    assert parse_target("user:pw@host") == SwarmTarget(
        hostname="host", username="user", password="pw", port=22
    )
    assert parse_target("host") == SwarmTarget(
        hostname="host", username=None, password=None, port=22
    )
    assert parse_target("user@host:2222") == SwarmTarget(
        hostname="host", username="user", password=None, port=2222
    )


def test_parse_target_rejects_empty() -> None:
    """parse_target raises on empty input."""
    with pytest.raises(RemoteError):
        parse_target("   ")


def test_target_to_ssh_omits_password_and_default_port() -> None:
    """target_to_ssh renders user@host[:port] and never a password."""
    assert target_to_ssh(SwarmTarget("host", "user", "secret")) == "user@host"
    assert (
        target_to_ssh(SwarmTarget("host", "user", "secret", port=2222))
        == "user@host:2222"
    )
    assert target_to_ssh(SwarmTarget("host")) == "host"


def test_run_reuses_existing_manager(tmp_path, caplog) -> None:
    """When docker exists and node is a manager, reuse and grab tokens."""
    client = FakeRemoteClient(
        [
            ("id -u", _ok("1000")),
            ("command -v docker", _ok("/usr/bin/docker")),
            ("docker --version", _ok("Docker version 27.0")),
            ("LocalNodeState", _ok("active")),
            ("ControlAvailable", _ok("true")),
            ("join-token -q worker", _ok("SWMTKN-worker")),
            ("join-token -q manager", _ok("SWMTKN-manager")),
        ]
    )
    manager = _manager(
        tmp_path,
        prompt=_prompt(["user@host", "done"]),
        client_factory=lambda target: client,
    )

    with caplog.at_level("INFO"):
        manager.run()

    assert manager.worker_token == "SWMTKN-worker"
    assert manager.manager_token == "SWMTKN-manager"
    assert client.closed is True
    assert not any("swarm init" in cmd for cmd in client.commands)
    assert "already an active swarm manager" in caplog.text
    assert "Docker already installed" in caplog.text


def test_run_installs_docker_and_inits_swarm(tmp_path, caplog) -> None:
    """When docker is missing and no swarm exists, install and init."""
    client = FakeRemoteClient(
        [
            ("id -u", _ok("0")),
            ("command -v docker", RemoteResult(1, "", "not found")),
            ("LocalNodeState", _ok("inactive")),
            ("swarm init", _ok("Swarm initialized")),
            ("join-token -q worker", _ok("SWMTKN-worker")),
            ("join-token -q manager", _ok("SWMTKN-manager")),
        ]
    )
    manager = _manager(
        tmp_path,
        prompt=_prompt(["root@10.0.0.5", "done"]),
        client_factory=lambda target: client,
    )

    with caplog.at_level("INFO"):
        manager.run()

    # docker.sh streamed over stdin.
    assert client.stdin_scripts
    assert "docker" in client.stdin_scripts[0]
    # IP host means an explicit advertise address.
    assert any(
        "swarm init --advertise-addr 10.0.0.5" in cmd for cmd in client.commands
    )
    assert manager.worker_token == "SWMTKN-worker"


def test_run_falls_back_to_password_on_auth_error(tmp_path, caplog) -> None:
    """A key-auth failure triggers a password prompt and retry."""
    client = FakeRemoteClient(
        [
            ("id -u", _ok("0")),
            ("command -v docker", _ok("/usr/bin/docker")),
            ("docker --version", _ok("Docker version 27.0")),
            ("LocalNodeState", _ok("active")),
            ("ControlAvailable", _ok("true")),
            ("join-token -q worker", _ok("SWMTKN-worker")),
            ("join-token -q manager", _ok("SWMTKN-manager")),
        ]
    )
    seen: list[SwarmTarget] = []

    def factory(target: SwarmTarget):
        seen.append(target)
        if target.password is None:
            raise SwarmAuthError("key auth failed")
        return client

    manager = _manager(
        tmp_path,
        prompt=_prompt(["user@host", "done"], secrets=["hunter2"]),
        client_factory=factory,
    )

    with caplog.at_level("WARNING"):
        manager.run()

    assert [t.password for t in seen] == [None, "hunter2"]
    assert "falling back to password" in caplog.text


def test_run_errors_when_no_password_after_auth_failure(tmp_path) -> None:
    """No password after a failed key auth is a hard error."""

    def factory(target: SwarmTarget):
        raise SwarmAuthError("key auth failed")

    manager = _manager(
        tmp_path,
        prompt=_prompt(["user@host", "done"], secrets=[""]),
        client_factory=factory,
    )
    with pytest.raises(RemoteError):
        manager.run()


def test_run_errors_when_node_is_not_manager(tmp_path) -> None:
    """A node in a swarm but not a manager cannot be the control plane."""
    client = FakeRemoteClient(
        [
            ("id -u", _ok("0")),
            ("command -v docker", _ok("/usr/bin/docker")),
            ("docker --version", _ok("Docker version 27.0")),
            ("LocalNodeState", _ok("active")),
            ("ControlAvailable", _ok("false")),
        ]
    )
    manager = _manager(
        tmp_path,
        prompt=_prompt(["user@host", "done"]),
        client_factory=lambda target: client,
    )
    with pytest.raises(SwarmError):
        manager.run()


def test_run_prompts_for_username_when_missing(tmp_path) -> None:
    """A target without a username triggers a username prompt."""
    client = FakeRemoteClient(
        [
            ("id -u", _ok("0")),
            ("command -v docker", _ok("/usr/bin/docker")),
            ("docker --version", _ok("Docker version 27.0")),
            ("LocalNodeState", _ok("active")),
            ("ControlAvailable", _ok("true")),
            ("join-token -q worker", _ok("SWMTKN-worker")),
            ("join-token -q manager", _ok("SWMTKN-manager")),
        ]
    )
    seen: list[SwarmTarget] = []

    def factory(target: SwarmTarget):
        seen.append(target)
        return client

    manager = _manager(
        tmp_path,
        prompt=_prompt(["host", "admin", "done"]),
        client_factory=factory,
    )
    manager.run()

    assert seen[0].username == "admin"
    assert seen[0].hostname == "host"


def test_run_defaults_hostname_on_empty_target(tmp_path) -> None:
    """Pressing enter accepts the default swarm-cp-0.local host."""
    client = FakeRemoteClient(
        [
            ("id -u", _ok("0")),
            ("command -v docker", _ok("/usr/bin/docker")),
            ("docker --version", _ok("Docker version 27.0")),
            ("LocalNodeState", _ok("active")),
            ("ControlAvailable", _ok("true")),
            ("join-token -q worker", _ok("SWMTKN-worker")),
            ("join-token -q manager", _ok("SWMTKN-manager")),
        ]
    )
    seen: list[SwarmTarget] = []

    def factory(target: SwarmTarget):
        seen.append(target)
        return client

    # Empty target accepts the default nodadyoushutup@swarm-cp-0.local.
    manager = _manager(
        tmp_path,
        prompt=_prompt(["", "done"]),
        client_factory=factory,
    )
    manager.run()

    assert seen[0].hostname == "swarm-cp-0.local"
    assert seen[0].username == "nodadyoushutup"


def _manager_client(
    hostname: str = "swarm-cp-0", label: str = ""
) -> FakeRemoteClient:
    """Build a control-plane client that is an active manager with tokens."""
    return FakeRemoteClient(
        [
            ("id -u", _ok("0")),
            ("command -v docker", _ok("/usr/bin/docker")),
            ("docker --version", _ok("Docker version 27.0")),
            ("NodeAddr", _ok("192.168.1.120")),
            ("LocalNodeState", _ok("active")),
            ("ControlAvailable", _ok("true")),
            ("join-token -q worker", _ok("SWMTKN-worker")),
            ("join-token -q manager", _ok("SWMTKN-manager")),
            ("docker node inspect", _ok(label)),
        ],
        hostname=hostname,
    )


def _worker_client(
    state: str = "inactive", join_exit: int = 0, hostname: str = "wk1"
) -> FakeRemoteClient:
    """Build a worker client with a given swarm state and join outcome."""
    return FakeRemoteClient(
        [
            ("id -u", _ok("0")),
            ("command -v docker", _ok("/usr/bin/docker")),
            ("docker --version", _ok("Docker version 27.0")),
            ("LocalNodeState", _ok(state)),
            ("swarm join --token", RemoteResult(join_exit, "", "boom")),
        ],
        hostname=hostname,
    )


def test_capture_worker_joins_single_node(tmp_path, caplog) -> None:
    """A single worker SSH target is joined using the captured token/address."""
    cp = _manager_client()
    worker = _worker_client()

    def factory(target: SwarmTarget):
        return cp if target.hostname == "swarm-cp-0.local" else worker

    manager = _manager(
        tmp_path,
        prompt=_prompt(["nodadyoushutup@swarm-cp-0.local", "user@wk1", "done"]),
        client_factory=factory,
    )
    with caplog.at_level("INFO"):
        manager.run()

    assert manager.manager_addr == "192.168.1.120"
    assert any(
        "swarm join --token SWMTKN-worker 192.168.1.120:2377" in cmd
        for cmd in worker.commands
    )
    assert worker.closed is True
    assert "Worker user@wk1 joined the swarm" in caplog.text


def test_capture_worker_default_expands_to_five(tmp_path) -> None:
    """The 'default' keyword joins swarm-wk-0..swarm-wk-4 as nodadyoushutup."""
    cp = _manager_client()
    workers: list[tuple[SwarmTarget, FakeRemoteClient]] = []

    def factory(target: SwarmTarget):
        if target.hostname == "swarm-cp-0.local":
            return cp
        client = _worker_client()
        workers.append((target, client))
        return client

    manager = _manager(
        tmp_path,
        prompt=_prompt(["nodadyoushutup@swarm-cp-0.local", "default", "done"]),
        client_factory=factory,
    )
    manager.run()

    hostnames = [t.hostname for t, _ in workers]
    assert hostnames == [f"swarm-wk-{i}.local" for i in range(5)]
    assert all(t.username == "nodadyoushutup" for t, _ in workers)
    assert all(
        any("swarm join --token" in cmd for cmd in client.commands)
        for _, client in workers
    )


def test_capture_worker_skips_when_already_in_swarm(tmp_path, caplog) -> None:
    """A worker already in a swarm is not re-joined."""
    cp = _manager_client()
    worker = _worker_client(state="active")

    def factory(target: SwarmTarget):
        return cp if target.hostname == "swarm-cp-0.local" else worker

    manager = _manager(
        tmp_path,
        prompt=_prompt(["nodadyoushutup@swarm-cp-0.local", "user@wk1", "done"]),
        client_factory=factory,
    )
    with caplog.at_level("INFO"):
        manager.run()

    assert not any("swarm join --token" in cmd for cmd in worker.commands)
    assert "already part of a swarm" in caplog.text


def test_capture_worker_failure_is_non_fatal(tmp_path, caplog) -> None:
    """A worker join failure is logged and does not abort the stage."""
    cp = _manager_client()
    worker = _worker_client(join_exit=1)

    def factory(target: SwarmTarget):
        return cp if target.hostname == "swarm-cp-0.local" else worker

    manager = _manager(
        tmp_path,
        prompt=_prompt(["nodadyoushutup@swarm-cp-0.local", "user@wk1", "done"]),
        client_factory=factory,
    )
    with caplog.at_level("ERROR"):
        manager.run()  # does not raise

    assert "Failed to add worker user@wk1" in caplog.text


def test_control_plane_gets_placement_label(tmp_path, caplog) -> None:
    """The control plane node is labeled with its own hostname."""
    cp = _manager_client(hostname="swarm-cp-0")

    manager = _manager(
        tmp_path,
        prompt=_prompt(["nodadyoushutup@swarm-cp-0.local", "done"]),
        client_factory=lambda target: cp,
    )
    with caplog.at_level("INFO"):
        manager.run()

    assert any(
        "docker node update --label-add swarm-cp-0=true swarm-cp-0" in cmd
        for cmd in cp.commands
    )
    assert "Added placement label swarm-cp-0=true to node swarm-cp-0" in caplog.text


def test_worker_gets_placement_label_via_manager(tmp_path) -> None:
    """A worker's hostname label is applied from the manager connection."""
    cp = _manager_client(hostname="swarm-cp-0")
    worker = _worker_client(hostname="wk1")

    def factory(target: SwarmTarget):
        return cp if target.hostname == "swarm-cp-0.local" else worker

    manager = _manager(
        tmp_path,
        prompt=_prompt(["nodadyoushutup@swarm-cp-0.local", "user@wk1", "done"]),
        client_factory=factory,
    )
    manager.run()

    # The label-add for the worker runs on the manager client, not the worker.
    assert any(
        "docker node update --label-add wk1=true wk1" in cmd
        for cmd in cp.commands
    )
    assert not any("node update --label-add wk1" in cmd for cmd in worker.commands)


def test_label_ensured_for_already_joined_worker(tmp_path) -> None:
    """A worker already in the swarm still gets its label ensured."""
    cp = _manager_client(hostname="swarm-cp-0")
    worker = _worker_client(state="active", hostname="wk1")

    def factory(target: SwarmTarget):
        return cp if target.hostname == "swarm-cp-0.local" else worker

    manager = _manager(
        tmp_path,
        prompt=_prompt(["nodadyoushutup@swarm-cp-0.local", "user@wk1", "done"]),
        client_factory=factory,
    )
    manager.run()

    assert not any("swarm join --token" in cmd for cmd in worker.commands)
    assert any(
        "docker node update --label-add wk1=true wk1" in cmd
        for cmd in cp.commands
    )


def test_label_skipped_when_already_present(tmp_path, caplog) -> None:
    """No label-add is issued when the node already carries the label."""
    cp = _manager_client(hostname="swarm-cp-0", label="true")

    manager = _manager(
        tmp_path,
        prompt=_prompt(["nodadyoushutup@swarm-cp-0.local", "done"]),
        client_factory=lambda target: cp,
    )
    with caplog.at_level("INFO"):
        manager.run()

    assert not any("node update --label-add" in cmd for cmd in cp.commands)
    assert "already has placement label swarm-cp-0=true" in caplog.text


def test_topology_loaded_from_swarm_file(tmp_path, caplog) -> None:
    """A swarm.yaml with nodes drives provisioning without prompts."""
    swarm_file = tmp_path / "swarm.yaml"
    swarm_file.write_text(
        "# homelab-config: docker/swarm\n"
        "nodes:\n"
        "  - name: swarm-cp-0\n"
        "    host: swarm-cp-0.local\n"
        "    user: nodadyoushutup\n"
        "    role: manager\n"
        "  - name: wk1\n"
        "    host: wk1\n"
        "    user: operator\n"
        "    role: worker\n",
        encoding="utf-8",
    )
    cp = _manager_client(hostname="swarm-cp-0")
    worker = _worker_client(hostname="wk1")

    def factory(target: SwarmTarget):
        return cp if target.hostname == "swarm-cp-0.local" else worker

    manager = SwarmManager(
        prompt=_forbidden_prompt(),
        client_factory=factory,
        swarm_file=swarm_file,
    )
    with caplog.at_level("INFO"):
        manager.run()

    assert "Loaded swarm topology from" in caplog.text
    assert any(
        "swarm join --token SWMTKN-worker 192.168.1.120:2377" in cmd
        for cmd in worker.commands
    )


def test_topology_file_worker_defaults_username(tmp_path) -> None:
    """A worker entry without a user defaults to the standard user."""
    swarm_file = tmp_path / "swarm.yaml"
    swarm_file.write_text(
        "nodes:\n"
        "  - host: swarm-cp-0.local\n"
        "    role: manager\n"
        "  - host: wk1\n"
        "    role: worker\n",
        encoding="utf-8",
    )
    cp = _manager_client(hostname="swarm-cp-0")
    seen: list[SwarmTarget] = []

    def factory(target: SwarmTarget):
        if target.hostname == "swarm-cp-0.local":
            return cp
        seen.append(target)
        return _worker_client(hostname="wk1")

    SwarmManager(
        prompt=_forbidden_prompt(),
        client_factory=factory,
        swarm_file=swarm_file,
    ).run()

    assert seen and seen[0].username == "nodadyoushutup"


def test_interactive_capture_persists_swarm_file(tmp_path) -> None:
    """Interactive capture writes the topology back to swarm.yaml (no secrets)."""
    swarm_file = tmp_path / "docker" / "swarm.yaml"
    cp = _manager_client(hostname="swarm-cp-0")
    worker = _worker_client(hostname="wk1")

    def factory(target: SwarmTarget):
        return cp if target.hostname == "swarm-cp-0.local" else worker

    SwarmManager(
        prompt=_prompt(
            ["admin:secret@swarm-cp-0.local", "operator@wk1", "done"]
        ),
        client_factory=factory,
        swarm_file=swarm_file,
    ).run()

    assert swarm_file.is_file()
    written = swarm_file.read_text(encoding="utf-8")
    assert "# homelab-config: docker/swarm" in written
    assert "nodes:" in written
    assert "name: swarm-cp-0" in written
    assert "host: swarm-cp-0.local" in written
    assert "user: admin" in written
    assert "role: manager" in written
    assert "host: wk1" in written
    assert "user: operator" in written
    # Password from the SSH string must never be persisted.
    assert "secret" not in written
