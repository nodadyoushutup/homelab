"""Tests for the MinIO Terraform backend provisioner."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from bootstrap.minio import MinioError
from bootstrap.minio_backend import CommandResult, MinioBackendProvisioner

_ENV = (
    "# homelab-config: docker/minio\n"
    "MINIO_ROOT_USER=admin\n"
    "MINIO_ROOT_PASSWORD=secretpw\n"
    "MINIO_REGION_NAME=us-east-1\n"
    "MINIO_HOSTNAME=minio.example\n"
)

_BACKEND_EMPTY = (
    "# homelab-config: terraform/minio.backend\n"
    'bucket = ""\n'
    'region = ""\n'
    'access_key = ""\n'
    'secret_key = ""\n'
    "\n"
    'endpoints = { s3 = "" }\n'
    "use_path_style = true\n"
)


class FakeRunner:
    """Scripted ``mc`` runner recording calls and simulating server state."""

    def __init__(
        self,
        *,
        buckets: set[str] | None = None,
        svcaccts: dict[str, str] | None = None,
    ) -> None:
        """Initialize simulated buckets and service accounts (access_key->name)."""
        self.buckets = set(buckets or set())
        self.svcaccts = dict(svcaccts or {})
        self.calls: list[list[str]] = []

    def __call__(self, args: list[str]) -> CommandResult:
        """Return a scripted result for an ``mc`` invocation."""
        self.calls.append(args)
        if args[0] == "ls":
            out = "\n".join(json.dumps({"key": f"{b}/"}) for b in self.buckets)
            return CommandResult(0, out, "")
        if args[0] == "mb":
            self.buckets.add(args[1].split("/", 1)[1])
            return CommandResult(0, "", "")
        if args[:4] == ["admin", "user", "svcacct", "ls"]:
            out = "\n".join(
                json.dumps({"accessKey": ak, "name": nm})
                for ak, nm in self.svcaccts.items()
            )
            return CommandResult(0, out, "")
        if args[:4] == ["admin", "user", "svcacct", "info"]:
            ak = args[5]
            name = self.svcaccts.get(ak)
            payload = json.dumps({"accessKey": ak, "name": name}) if name else ""
            return CommandResult(0, payload, "")
        if args[:4] == ["admin", "user", "svcacct", "add"]:
            ak = args[args.index("--access-key") + 1]
            name = args[args.index("--name") + 1]
            self.svcaccts[ak] = name
            return CommandResult(0, "", "")
        if args[:4] == ["admin", "user", "svcacct", "edit"]:
            return CommandResult(0, "", "")
        return CommandResult(0, "", "")


def _fixed_keys(access: str, secret: str):
    return lambda: (access, secret)


def _provisioner(
    tmp_path: Path,
    runner: FakeRunner,
    *,
    backend_text: str = _BACKEND_EMPTY,
    keys=("AKTERRAFORM0000TEST0", "supersecretvalue"),
    resolver=lambda host: host,
) -> tuple[MinioBackendProvisioner, Path]:
    minio_env = tmp_path / "minio.env"
    minio_env.write_text(_ENV, encoding="utf-8")
    backend = tmp_path / "minio.backend.hcl"
    backend.write_text(backend_text, encoding="utf-8")
    provisioner = MinioBackendProvisioner(
        project_root=tmp_path,
        minio_env=minio_env,
        backend_file=backend,
        runner=runner,
        key_factory=_fixed_keys(*keys),
        resolver=resolver,
    )
    return provisioner, backend


def test_creates_bucket_and_key_when_absent(tmp_path, caplog) -> None:
    """A fresh MinIO gets the bucket, a named key, and a populated backend."""
    runner = FakeRunner()
    provisioner, backend = _provisioner(tmp_path, runner)

    with caplog.at_level("INFO"):
        provisioner.run()

    assert "terraform" in runner.buckets
    add = next(c for c in runner.calls if c[:4] == ["admin", "user", "svcacct", "add"])
    assert "--name" in add and add[add.index("--name") + 1] == "terraform"

    text = backend.read_text(encoding="utf-8")
    assert 'access_key = "AKTERRAFORM0000TEST0"' in text
    assert 'secret_key = "supersecretvalue"' in text
    assert 'bucket = "terraform"' in text
    assert 'region = "us-east-1"' in text
    assert 'endpoints = { s3 = "http://minio.example:9000" }' in text
    assert "auto-populate when MinIO is initialized" in text


def test_existing_bucket_is_acknowledged(tmp_path, caplog) -> None:
    """An existing bucket is not recreated."""
    runner = FakeRunner(buckets={"terraform"})
    provisioner, _ = _provisioner(tmp_path, runner)

    with caplog.at_level("INFO"):
        provisioner.run()

    assert not any(c[0] == "mb" for c in runner.calls)
    assert "already exists" in caplog.text


def test_existing_key_in_sync_is_left_alone(tmp_path, caplog) -> None:
    """When the backend already matches the named key, nothing is rewritten."""
    runner = FakeRunner(svcaccts={"AKEXISTING": "terraform"})
    backend_text = _BACKEND_EMPTY.replace(
        'access_key = ""', 'access_key = "AKEXISTING"'
    ).replace('secret_key = ""', 'secret_key = "alreadyset"')
    provisioner, backend = _provisioner(tmp_path, runner, backend_text=backend_text)

    with caplog.at_level("INFO"):
        provisioner.run()

    assert not any(
        c[:4] == ["admin", "user", "svcacct", "add"] for c in runner.calls
    )
    assert not any(
        c[:4] == ["admin", "user", "svcacct", "edit"] for c in runner.calls
    )
    # The key lines are preserved (bucket/region/endpoint may fill on first run).
    after = backend.read_text(encoding="utf-8")
    assert 'access_key = "AKEXISTING"' in after
    assert 'secret_key = "alreadyset"' in after
    assert "in sync" in caplog.text


def test_existing_key_with_backend_delta_rotates_secret(tmp_path, caplog) -> None:
    """A named key present but out of sync triggers a secret rotation."""
    runner = FakeRunner(svcaccts={"AKEXISTING": "terraform"})
    provisioner, backend = _provisioner(
        tmp_path, runner, keys=("UNUSED", "rotatedsecret")
    )

    with caplog.at_level("INFO"):
        provisioner.run()

    edits = [c for c in runner.calls if c[:4] == ["admin", "user", "svcacct", "edit"]]
    assert len(edits) == 1
    assert edits[0][edits[0].index("--secret-key") + 1] == "rotatedsecret"

    text = backend.read_text(encoding="utf-8")
    assert 'access_key = "AKEXISTING"' in text
    assert 'secret_key = "rotatedsecret"' in text
    assert "rotated secret" in caplog.text


def test_finds_named_key_via_info_fallback(tmp_path) -> None:
    """The name is discovered via svcacct info when ls omits it."""

    class NoNameLsRunner(FakeRunner):
        def __call__(self, args: list[str]) -> CommandResult:
            if args[:4] == ["admin", "user", "svcacct", "ls"]:
                self.calls.append(args)
                out = "\n".join(json.dumps({"accessKey": ak}) for ak in self.svcaccts)
                return CommandResult(0, out, "")
            return super().__call__(args)

    runner = NoNameLsRunner(svcaccts={"AKEXISTING": "terraform"})
    provisioner, backend = _provisioner(
        tmp_path, runner, keys=("UNUSED", "rotated2")
    )

    provisioner.run()

    assert any(
        c[:4] == ["admin", "user", "svcacct", "info"] for c in runner.calls
    )
    assert 'access_key = "AKEXISTING"' in backend.read_text(encoding="utf-8")


def test_mdns_hostname_is_resolved_to_ip(tmp_path, caplog) -> None:
    """A .local hostname is resolved to an IP for mc and the backend endpoint."""
    runner = FakeRunner()
    provisioner, backend = _provisioner(
        tmp_path, runner, resolver=lambda host: "192.168.1.120"
    )

    with caplog.at_level("INFO"):
        provisioner.run()

    text = backend.read_text(encoding="utf-8")
    assert 'endpoints = { s3 = "http://192.168.1.120:9000" }' in text
    assert "Resolved MinIO host minio.example to 192.168.1.120" in caplog.text


def test_missing_credentials_raises(tmp_path) -> None:
    """Missing root credentials raise a MinioError."""
    minio_env = tmp_path / "minio.env"
    minio_env.write_text("# homelab-config: docker/minio\n", encoding="utf-8")
    backend = tmp_path / "minio.backend.hcl"
    backend.write_text(_BACKEND_EMPTY, encoding="utf-8")
    provisioner = MinioBackendProvisioner(
        project_root=tmp_path,
        minio_env=minio_env,
        backend_file=backend,
        runner=FakeRunner(),
    )

    with pytest.raises(MinioError):
        provisioner.run()


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(pytest.main([__file__]))
