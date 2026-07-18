"""Provision the Terraform state backend on MinIO via the ``mc`` client.

Runs locally on the bootstrap host (where ``mc`` is installed) against the MinIO
endpoint declared in ``minio.env``. It ensures a ``terraform`` bucket exists,
ensures a MinIO access key named ``terraform`` exists (creating it once, or
rotating its secret only when the backend is out of sync), and writes the
credentials into the live ``.config/terraform/minio.backend.hcl``.
"""

from __future__ import annotations

import json
import logging
import re
import secrets
import socket
import string
import subprocess
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from bootstrap.minio import MinioError
from bootstrap.paths import PROJECT_ROOT, display_path
from bootstrap.remote import is_ip_address, parse_target

logger = logging.getLogger(__name__)

_MINIO_ENV_RELATIVE = Path(".config") / "docker" / "minio.env"
_BACKEND_RELATIVE = Path(".config") / "terraform" / "minio.backend.hcl"
_BUCKET = "terraform"
_SVCACCT_NAME = "terraform"
# Transient mc alias name; credentials are passed via MC_HOST_<alias> env so
# nothing is written to the operator's ~/.mc config.
_ALIAS = "homelab-bootstrap"
_API_PORT = 9000
_DEFAULT_HOST = "swarm-cp-0.local"
_DEFAULT_REGION = "us-east-1"
_BACKEND_TAG = "# homelab-config: terraform/minio.backend"
_AUTO_COMMENT = (
    "# access_key/secret_key auto-populate when MinIO is initialized by bootstrap."
)


@dataclass(frozen=True)
class CommandResult:
    """Result of a local command invocation."""

    returncode: int
    stdout: str
    stderr: str


McRunner = Callable[[list[str]], CommandResult]
KeyFactory = Callable[[], tuple[str, str]]
HostResolver = Callable[[str], str]


def _resolve_host(hostname: str) -> str:
    """Resolve ``hostname`` to an IP address using the system resolver.

    ``mc`` and Terraform are Go binaries that ignore nss/mDNS, so ``.local``
    names they receive fail to resolve. Python's ``getaddrinfo`` goes through
    glibc/avahi and can resolve them, so we resolve here and hand Go tools a
    literal IP instead.

    Args:
        hostname: Host or IP to resolve.

    Returns:
        A literal IP address (IPv4 preferred).

    Raises:
        MinioError: When the host cannot be resolved.
    """
    if is_ip_address(hostname):
        return hostname
    try:
        infos = socket.getaddrinfo(hostname, _API_PORT, type=socket.SOCK_STREAM)
    except OSError as exc:
        raise MinioError(
            f"Could not resolve MinIO host {hostname!r}: {exc}"
        ) from exc
    for family in (socket.AF_INET, socket.AF_INET6):
        for info in infos:
            if info[0] == family:
                return str(info[4][0])
    raise MinioError(f"No usable address found for MinIO host {hostname!r}")


def _default_key_factory() -> tuple[str, str]:
    """Generate a MinIO ``(access_key, secret_key)`` pair."""
    alphabet = string.ascii_uppercase + string.digits
    access_key = "".join(secrets.choice(alphabet) for _ in range(20))
    secret_key = secrets.token_urlsafe(30)
    return access_key, secret_key


def _default_mc_runner() -> McRunner:
    """Build an ``mc`` runner that shells out to the local ``mc`` binary."""

    def run(args: list[str]) -> CommandResult:
        try:
            proc = subprocess.run(
                ["mc", *args],
                capture_output=True,
                text=True,
                check=False,
            )
        except FileNotFoundError as exc:
            raise MinioError(
                "mc (MinIO client) not found; run scripts/install/minio_client.sh"
            ) from exc
        return CommandResult(proc.returncode, proc.stdout, proc.stderr)

    return run


class MinioBackendProvisioner:
    """Create the Terraform bucket + access key and wire the backend hcl."""

    def __init__(
        self,
        project_root: Path = PROJECT_ROOT,
        minio_env: Path | None = None,
        backend_file: Path | None = None,
        runner: McRunner | None = None,
        key_factory: KeyFactory | None = None,
        resolver: HostResolver | None = None,
    ) -> None:
        """Initialize the provisioner.

        Args:
            project_root: Repository root (for relative log paths).
            minio_env: Path to ``minio.env``; defaults under ``project_root``.
            backend_file: Path to the backend hcl; defaults under ``project_root``.
            runner: ``mc`` command runner (injectable for tests).
            key_factory: Access/secret key generator (injectable for tests).
            resolver: Hostname-to-IP resolver (injectable for tests).
        """
        self._project_root = project_root
        self._minio_env = (
            minio_env if minio_env is not None else project_root / _MINIO_ENV_RELATIVE
        )
        self._backend_file = (
            backend_file
            if backend_file is not None
            else project_root / _BACKEND_RELATIVE
        )
        self._runner = runner
        self._key_factory = key_factory or _default_key_factory
        self._resolver = resolver or _resolve_host

    def _rel(self, path: Path | str) -> str:
        """Format a path relative to the project root for display."""
        return display_path(path, root=self._project_root)

    def run(self) -> None:
        """Ensure the bucket, access key, and backend config are in place.

        Raises:
            MinioError: If provisioning fails.
        """
        env = self._read_env()
        root_user = env.get("MINIO_ROOT_USER")
        root_pass = env.get("MINIO_ROOT_PASSWORD")
        if not root_user or not root_pass:
            raise MinioError(
                "MINIO_ROOT_USER/MINIO_ROOT_PASSWORD missing from "
                f"{self._rel(self._minio_env)}"
            )
        hostname = parse_target(
            env.get("MINIO_HOSTNAME") or _DEFAULT_HOST
        ).hostname
        address = self._resolver(hostname)
        if address != hostname:
            logger.info("Resolved MinIO host %s to %s", hostname, address)
        region = env.get("MINIO_REGION_NAME") or _DEFAULT_REGION
        endpoint = f"http://{address}:{_API_PORT}"

        runner = self._runner or _default_mc_runner()
        self._configure_alias(runner, endpoint, root_user, root_pass)
        try:
            self._ensure_bucket(runner)
            access_key, secret_key = self._ensure_access_key(runner, root_user)
            self._write_backend(access_key, secret_key, region, endpoint)
        finally:
            # Best-effort cleanup so root creds don't linger in ~/.mc/config.json.
            runner(["alias", "rm", _ALIAS])

    def _configure_alias(
        self, runner: McRunner, endpoint: str, access: str, secret: str
    ) -> None:
        """Register the transient ``mc`` alias for the MinIO endpoint.

        Uses ``mc alias set`` with explicit arguments (rather than a
        ``MC_HOST_*`` URL) so credentials with special characters authenticate
        correctly.

        Raises:
            MinioError: When the alias cannot be configured.
        """
        result = runner(
            ["alias", "set", _ALIAS, endpoint, access, secret, "--api", "s3v4"]
        )
        if result.returncode != 0:
            raise MinioError(
                "Could not configure mc alias for MinIO: "
                f"{result.stderr.strip() or result.stdout.strip()}"
            )

    def _read_env(self) -> dict[str, str]:
        """Parse ``minio.env`` into a key/value mapping."""
        if not self._minio_env.is_file():
            raise MinioError(
                f"MinIO env file missing: {self._rel(self._minio_env)}"
            )
        values: dict[str, str] = {}
        for line in self._minio_env.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or "=" not in stripped:
                continue
            key, _, value = stripped.partition("=")
            values[key.strip()] = value.strip().strip('"').strip("'")
        return values

    def _ensure_bucket(self, runner: McRunner) -> None:
        """Create the ``terraform`` bucket unless it already exists."""
        listing = runner(["ls", _ALIAS, "--json"])
        if listing.returncode != 0:
            raise MinioError(
                "Could not list MinIO buckets: "
                f"{listing.stderr.strip() or listing.stdout.strip()}"
            )
        buckets = {
            str(obj.get("key", "")).rstrip("/")
            for obj in _iter_json(listing.stdout)
        }
        if _BUCKET in buckets:
            logger.info("MinIO bucket %r already exists", _BUCKET)
            return
        created = runner(["mb", f"{_ALIAS}/{_BUCKET}"])
        if created.returncode != 0:
            raise MinioError(
                f"Could not create MinIO bucket {_BUCKET!r}: "
                f"{created.stderr.strip() or created.stdout.strip()}"
            )
        logger.info("Created MinIO bucket %r", _BUCKET)

    def _ensure_access_key(
        self, runner: McRunner, root_user: str
    ) -> tuple[str, str]:
        """Ensure a ``terraform``-named access key exists; return its creds.

        When the key already exists and the backend is in sync, the existing
        credentials are reused. When the backend is out of sync (or the key is
        missing) the secret is created or rotated so the backend can be updated.

        Returns:
            The ``(access_key, secret_key)`` to write to the backend.
        """
        backend_text = self._read_backend_text()
        backend_access = _read_hcl_value(backend_text, "access_key")
        backend_secret = _read_hcl_value(backend_text, "secret_key")

        existing = self._find_named_access_key(runner, root_user)
        if existing:
            if existing == backend_access and backend_secret:
                logger.info(
                    "MinIO access key %r already exists and the backend is "
                    "in sync; leaving it",
                    _SVCACCT_NAME,
                )
                return existing, backend_secret
            _, new_secret = self._key_factory()
            self._rotate_secret(runner, existing, new_secret)
            logger.info(
                "Reconciled backend with existing MinIO access key %r "
                "(rotated secret)",
                _SVCACCT_NAME,
            )
            return existing, new_secret

        access_key, secret_key = self._key_factory()
        self._create_access_key(runner, root_user, access_key, secret_key)
        logger.info(
            "Created MinIO access key %r for Terraform", _SVCACCT_NAME
        )
        return access_key, secret_key

    def _find_named_access_key(
        self, runner: McRunner, root_user: str
    ) -> str | None:
        """Return the access key of the ``terraform``-named service account."""
        listing = runner(
            ["admin", "user", "svcacct", "ls", _ALIAS, root_user, "--json"]
        )
        if listing.returncode != 0:
            raise MinioError(
                "Could not list MinIO access keys: "
                f"{listing.stderr.strip() or listing.stdout.strip()}"
            )
        candidates: list[str] = []
        for obj in _iter_json(listing.stdout):
            access_key = obj.get("accessKey") or obj.get("access_key")
            if not access_key:
                continue
            if obj.get("name") == _SVCACCT_NAME:
                return access_key
            candidates.append(access_key)
        # Older mc list output may omit the name; fall back to per-key info.
        for access_key in candidates:
            info = runner(
                ["admin", "user", "svcacct", "info", _ALIAS, access_key, "--json"]
            )
            if info.returncode != 0:
                continue
            for obj in _iter_json(info.stdout):
                if obj.get("name") == _SVCACCT_NAME:
                    return access_key
        return None

    def _create_access_key(
        self, runner: McRunner, root_user: str, access_key: str, secret_key: str
    ) -> None:
        """Create the named service account with explicit credentials."""
        result = runner(
            [
                "admin", "user", "svcacct", "add", _ALIAS, root_user,
                "--access-key", access_key,
                "--secret-key", secret_key,
                "--name", _SVCACCT_NAME,
            ]
        )
        if result.returncode != 0:
            raise MinioError(
                "Could not create MinIO access key: "
                f"{result.stderr.strip() or result.stdout.strip()}"
            )

    def _rotate_secret(
        self, runner: McRunner, access_key: str, secret_key: str
    ) -> None:
        """Rotate the secret of an existing service account (same access key)."""
        result = runner(
            [
                "admin", "user", "svcacct", "edit", _ALIAS, access_key,
                "--secret-key", secret_key,
            ]
        )
        if result.returncode != 0:
            raise MinioError(
                "Could not update MinIO access key secret: "
                f"{result.stderr.strip() or result.stdout.strip()}"
            )

    def _read_backend_text(self) -> str:
        """Read the backend hcl, returning a fresh template when absent."""
        if self._backend_file.is_file():
            return self._backend_file.read_text(encoding="utf-8")
        return (
            f"{_BACKEND_TAG}\n"
            "# Terraform S3 backend configuration for MinIO.\n"
            'bucket = ""\n'
            'region = ""\n'
            'access_key = ""\n'
            'secret_key = ""\n'
            "\n"
            'endpoints = { s3 = "" }\n'
            "\n"
            "skip_credentials_validation = true\n"
            "skip_metadata_api_check     = true\n"
            "skip_requesting_account_id  = true\n"
            "use_path_style              = true\n"
        )

    def _write_backend(
        self, access_key: str, secret_key: str, region: str, endpoint: str
    ) -> None:
        """Write credentials/endpoint into the backend hcl (only on a delta)."""
        original = self._read_backend_text()
        text = _ensure_comment(original)
        text = _set_hcl_value(text, "access_key", access_key)
        text = _set_hcl_value(text, "secret_key", secret_key)
        text = _fill_if_empty(text, "bucket", _BUCKET)
        text = _fill_if_empty(text, "region", region)
        text = _fill_endpoint_if_empty(text, endpoint)

        if text == original and self._backend_file.is_file():
            logger.info(
                "Terraform backend already up to date at %s",
                self._rel(self._backend_file),
            )
            return
        self._backend_file.parent.mkdir(parents=True, exist_ok=True)
        self._backend_file.write_text(text, encoding="utf-8")
        logger.info(
            "Wrote Terraform backend credentials to %s",
            self._rel(self._backend_file),
        )


def _iter_json(payload: str):
    """Yield parsed JSON objects from newline-delimited ``mc --json`` output."""
    for line in payload.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict):
            yield obj


def _read_hcl_value(text: str, key: str) -> str:
    """Return the quoted value of ``key = "..."`` (empty when unset)."""
    match = re.search(rf'(?m)^\s*{re.escape(key)}\s*=\s*"([^"]*)"', text)
    return match.group(1) if match else ""


def _set_hcl_value(text: str, key: str, value: str) -> str:
    """Set ``key = "value"``, appending the line when it is missing."""
    pattern = rf'(?m)^(\s*{re.escape(key)}\s*=\s*")[^"]*(")'
    new_text, count = re.subn(
        pattern, lambda m: f"{m.group(1)}{value}{m.group(2)}", text
    )
    if count == 0:
        return text.rstrip("\n") + f'\n{key} = "{value}"\n'
    return new_text


def _fill_if_empty(text: str, key: str, value: str) -> str:
    """Set ``key`` only when it currently has no value."""
    if _read_hcl_value(text, key):
        return text
    return _set_hcl_value(text, key, value)


def _fill_endpoint_if_empty(text: str, endpoint: str) -> str:
    """Fill ``endpoints = { s3 = "" }`` only when the s3 endpoint is empty."""
    pattern = r'(endpoints\s*=\s*\{\s*s3\s*=\s*")([^"]*)(")'

    def repl(match: re.Match[str]) -> str:
        if match.group(2):
            return match.group(0)
        return f"{match.group(1)}{endpoint}{match.group(3)}"

    new_text, count = re.subn(pattern, repl, text)
    if count == 0:
        return text.rstrip("\n") + f'\nendpoints = {{ s3 = "{endpoint}" }}\n'
    return new_text


def _ensure_comment(text: str) -> str:
    """Insert the auto-populate comment above ``access_key`` if absent."""
    if _AUTO_COMMENT in text:
        return text
    lines = text.splitlines()
    out: list[str] = []
    inserted = False
    for line in lines:
        if not inserted and re.match(r"\s*access_key\s*=", line):
            out.append(_AUTO_COMMENT)
            inserted = True
        out.append(line)
    if not inserted:
        out.append(_AUTO_COMMENT)
    return "\n".join(out) + "\n"


__all__ = ["MinioBackendProvisioner"]
