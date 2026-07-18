"""Tests for the MinIO docker-compose deployment step."""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from bootstrap.minio import MinioDeployer, MinioError
from bootstrap.prompt import OperatorPrompt
from bootstrap.remote import RemoteResult, RemoteTarget

_COMPOSE = (
    "name: minio\n"
    "services:\n"
    "  minio:\n"
    "    image: minio/minio:test\n"
    "    env_file:\n"
    "      - ../.config/docker/minio.env\n"
)

_ENV = (
    "# homelab-config: docker/minio\n"
    "MINIO_ROOT_USER=admin\n"
    "MINIO_ROOT_PASSWORD=secretpw\n"
)


class FakeRemoteClient:
    """Scripted remote client that records uploads and health polling."""

    def __init__(
        self,
        *,
        home: str = "/home/op",
        existing: set[str] | None = None,
        health: list[str] | None = None,
        docker_present: bool = True,
        container: str = "absent",
    ) -> None:
        """Initialize the fake client behavior.

        Args:
            container: Simulated container state (``running``/``stopped``/``absent``).
        """
        self._home = home
        self._existing = existing or set()
        self._health = iter(health or ["healthy"])
        self._last_health = "starting"
        self._docker_present = docker_present
        self._container = container
        self.commands: list[str] = []
        self.uploads: dict[str, str] = {}
        self.closed = False

    def run(self, command: str, *, stdin: str | None = None) -> RemoteResult:
        """Return a scripted result for ``command``."""
        self.commands.append(command)
        if command.strip() == "id -u":
            return RemoteResult(0, "0", "")
        if command == "command -v docker":
            return RemoteResult(0 if self._docker_present else 1, "", "")
        if command == "docker --version":
            return RemoteResult(0, "Docker version 27.0", "")
        if 'printf %s "$HOME"' in command:
            return RemoteResult(0, self._home, "")
        if command.startswith("mkdir -p"):
            return RemoteResult(0, "", "")
        if command.startswith("test -f "):
            path = _quoted(command)
            return RemoteResult(0 if path in self._existing else 1, "", "")
        if command.startswith("cat > ") and stdin is not None:
            self.uploads[_quoted(command)] = stdin
            return RemoteResult(0, "", "")
        if "State.Running" in command:
            if self._container == "absent":
                return RemoteResult(1, "", "No such object")
            running = "true" if self._container == "running" else "false"
            return RemoteResult(0, running, "")
        if command.endswith("docker start minio"):
            self._container = "running"
            return RemoteResult(0, "minio", "")
        if "compose" in command and "up -d" in command:
            self._container = "running"
            return RemoteResult(0, "", "")
        if "State.Health.Status" in command:
            try:
                self._last_health = next(self._health)
            except StopIteration:
                pass
            return RemoteResult(0, self._last_health, "")
        return RemoteResult(0, "", "")

    def close(self) -> None:
        """Mark the client closed."""
        self.closed = True


def _quoted(command: str) -> str:
    """Extract the first double-quoted path from a command."""
    match = re.search(r'"([^"]+)"', command)
    return match.group(1) if match else ""


def _prompt(inputs: list[str]) -> OperatorPrompt:
    it = iter(inputs)
    return OperatorPrompt(input_func=lambda _: next(it), secret_func=lambda _: "")


def _forbidden_prompt() -> OperatorPrompt:
    def _fail(_: str) -> str:
        raise AssertionError("prompt should not be called")

    return OperatorPrompt(input_func=_fail, secret_func=_fail)


def _deployer(
    tmp_path: Path,
    *,
    client: FakeRemoteClient,
    prompt: OperatorPrompt,
    env_text: str | None = _ENV,
) -> tuple[MinioDeployer, Path, list[RemoteTarget]]:
    """Build a MinioDeployer wired to fakes and temp config files."""
    minio_env = tmp_path / "minio.env"
    if env_text is not None:
        minio_env.write_text(env_text, encoding="utf-8")
    compose_source = tmp_path / "docker-compose.minio.yaml"
    compose_source.write_text(_COMPOSE, encoding="utf-8")
    seen: list[RemoteTarget] = []

    def factory(target: RemoteTarget):
        seen.append(target)
        return client

    deployer = MinioDeployer(
        project_root=tmp_path,
        prompt=prompt,
        client_factory=factory,
        minio_env=minio_env,
        compose_source=compose_source,
        sleep=lambda _: None,
        health_attempts=3,
        health_interval=0,
    )
    return deployer, minio_env, seen


def test_deploys_using_hostname_from_env(tmp_path, caplog) -> None:
    """MINIO_HOSTNAME in minio.env drives deploy with no prompt."""
    client = FakeRemoteClient()
    env_text = _ENV + "MINIO_HOSTNAME=minio.example\n"
    deployer, _, seen = _deployer(
        tmp_path, client=client, prompt=_forbidden_prompt(), env_text=env_text
    )

    with caplog.at_level("INFO"):
        deployer.run()

    assert seen[0].hostname == "minio.example"
    assert seen[0].username == "nodadyoushutup"
    # Compose uploaded with the env_file rewritten to a co-located file.
    compose = client.uploads["/home/op/minio/docker-compose.yaml"]
    assert "minio.env" in compose
    assert "../.config/docker/minio.env" not in compose
    # Env uploaded without the bootstrap-only MINIO_HOSTNAME key.
    env = client.uploads["/home/op/minio/minio.env"]
    assert "MINIO_ROOT_PASSWORD=secretpw" in env
    assert "MINIO_HOSTNAME" not in env
    assert any("compose" in c and "up -d" in c for c in client.commands)
    assert client.closed is True
    assert "MinIO is healthy and ready" in caplog.text


def test_prompts_and_persists_hostname_when_missing(tmp_path) -> None:
    """A missing MINIO_HOSTNAME prompts and persists the answer."""
    client = FakeRemoteClient()
    deployer, minio_env, seen = _deployer(
        tmp_path, client=client, prompt=_prompt(["box.example"])
    )

    deployer.run()

    assert seen[0].hostname == "box.example"
    persisted = minio_env.read_text(encoding="utf-8")
    assert "MINIO_HOSTNAME=box.example" in persisted


def test_default_host_used_on_empty_answer(tmp_path) -> None:
    """Pressing enter accepts the swarm-cp-0.local default and persists it."""
    client = FakeRemoteClient()
    deployer, minio_env, seen = _deployer(
        tmp_path, client=client, prompt=_prompt([""])
    )

    deployer.run()

    assert seen[0].hostname == "swarm-cp-0.local"
    assert "MINIO_HOSTNAME=swarm-cp-0.local" in minio_env.read_text(encoding="utf-8")


def test_existing_files_are_not_overwritten(tmp_path, caplog) -> None:
    """Existing remote compose/env files are left untouched."""
    client = FakeRemoteClient(
        existing={
            "/home/op/minio/docker-compose.yaml",
            "/home/op/minio/minio.env",
        }
    )
    env_text = _ENV + "MINIO_HOSTNAME=minio.example\n"
    deployer, _, _ = _deployer(
        tmp_path, client=client, prompt=_forbidden_prompt(), env_text=env_text
    )

    with caplog.at_level("INFO"):
        deployer.run()

    assert client.uploads == {}
    assert "already present" in caplog.text
    # Still brings the stack up and health-checks it.
    assert any("compose" in c and "up -d" in c for c in client.commands)


def test_waits_for_health_then_succeeds(tmp_path, caplog) -> None:
    """Deployment polls until the container reports healthy."""
    client = FakeRemoteClient(health=["starting", "starting", "healthy"])
    env_text = _ENV + "MINIO_HOSTNAME=minio.example\n"
    deployer, _, _ = _deployer(
        tmp_path, client=client, prompt=_forbidden_prompt(), env_text=env_text
    )

    with caplog.at_level("INFO"):
        deployer.run()

    assert "MinIO is healthy and ready" in caplog.text


def test_running_container_is_left_untouched(tmp_path, caplog) -> None:
    """An already-online MinIO is not uploaded, restarted, or recreated."""
    client = FakeRemoteClient(container="running")
    env_text = _ENV + "MINIO_HOSTNAME=minio.example\n"
    deployer, _, _ = _deployer(
        tmp_path, client=client, prompt=_forbidden_prompt(), env_text=env_text
    )

    with caplog.at_level("INFO"):
        deployer.run()

    assert client.uploads == {}
    assert not any("up -d" in c for c in client.commands)
    assert not any(c.endswith("docker start minio") for c in client.commands)
    assert "already online" in caplog.text


def test_stopped_container_is_started_without_recreate(tmp_path, caplog) -> None:
    """A stopped MinIO container is started (not recreated) and health-checked."""
    client = FakeRemoteClient(container="stopped")
    env_text = _ENV + "MINIO_HOSTNAME=minio.example\n"
    deployer, _, _ = _deployer(
        tmp_path, client=client, prompt=_forbidden_prompt(), env_text=env_text
    )

    with caplog.at_level("INFO"):
        deployer.run()

    assert client.uploads == {}
    assert any(c.endswith("docker start minio") for c in client.commands)
    assert not any("up -d" in c for c in client.commands)
    assert "MinIO is healthy and ready" in caplog.text


def test_health_timeout_raises(tmp_path) -> None:
    """A never-healthy container raises MinioError after the retries."""
    client = FakeRemoteClient(health=["starting", "starting", "starting"])
    env_text = _ENV + "MINIO_HOSTNAME=minio.example\n"
    deployer, _, _ = _deployer(
        tmp_path, client=client, prompt=_forbidden_prompt(), env_text=env_text
    )

    with pytest.raises(MinioError):
        deployer.run()


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(pytest.main([__file__]))
