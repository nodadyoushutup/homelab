"""SSH into swarm nodes for reconcile actions.

We shell out to the system ``ssh``/``scp`` binaries rather than a Python SSH
library because this homelab authenticates with **SSH certificates** (each key
set carries an ``id_ed25519-cert.pub`` signed by our CA). OpenSSH automatically
presents the ``<key>-cert.pub`` sitting next to the ``-i`` identity file, exactly
like the rest of the repo's tooling; that's the auth the nodes actually accept.

Auth strategy mirrors the "sync SSH" intent: try the node's key set first, then
fall back to the node's password (via ``sshpass``) when one is set - so a machine
that doesn't have our key yet can still be reached by password and later aligned
via ``sync_ssh``.

Host keys use ``accept-new``: this is a homelab reconcile tool talking to nodes
the operator declared, not an untrusted network client.
"""

from __future__ import annotations

import logging
import shlex
import shutil
import socket
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

from homelab_config.paths import SSH_DIR

logger = logging.getLogger(__name__)

# Preferred private-key basenames inside a key set, in order.
_KEY_BASENAMES = ("id_ed25519", "id_ecdsa", "id_rsa")

# mDNS (.local) lookups over WiFi are flaky - the first query often times out
# with EAI_AGAIN. Resolve in Python with a few retries, then hand ssh/scp the
# resolved IP so a single transient failure doesn't kill the whole operation.
_RESOLVE_ATTEMPTS = 6
_RESOLVE_DELAY = 0.7

# Shared known_hosts for reconcile connections (auto-populated via accept-new).
KNOWN_HOSTS = SSH_DIR / "known_hosts"


class SSHError(Exception):
    """Raised when connecting to or running a command on a node fails."""


@dataclass
class RemoteResult:
    """Result of a single remote command."""

    command: str
    exit_code: int
    stdout: str
    stderr: str

    @property
    def ok(self) -> bool:
        return self.exit_code == 0

    def output(self) -> str:
        """Combined stdout/stderr, trimmed - handy for error messages."""
        parts = [self.stdout.strip(), self.stderr.strip()]
        return "\n".join(p for p in parts if p)


@dataclass
class SSHSession:
    """A validated way to reach a node (system ssh/scp, chosen auth mode)."""

    node: dict
    host: str  # configured hostname (used as HostKeyAlias)
    address: str  # pre-resolved IP we actually dial
    port: int
    user: str
    key_path: Path | None
    password: str
    auth: str  # "key" | "password"

    @property
    def target(self) -> str:
        return f"{self.user}@{self.host}:{self.port}"

    def close(self) -> None:  # parity with the old paramiko client interface
        pass


def private_key_path(key_set: str) -> Path | None:
    """Return the private key file for a key set under ``.config/.ssh``.

    Prefers the conventional ``id_ed25519``/``id_ecdsa``/``id_rsa`` names, then
    falls back to any file whose contents look like a private key.
    """
    if not key_set:
        return None
    set_dir = SSH_DIR / key_set
    if not set_dir.is_dir():
        return None
    for name in _KEY_BASENAMES:
        candidate = set_dir / name
        if candidate.is_file():
            return candidate
    for entry in sorted(set_dir.iterdir()):
        if not entry.is_file() or entry.name.endswith((".pub", "-cert.pub")):
            continue
        try:
            head = entry.read_text(encoding="utf-8", errors="replace")[:80]
        except OSError:
            continue
        if "PRIVATE KEY" in head:
            return entry
    return None


# --- resolution --------------------------------------------------------------


def resolve_host(host: str) -> str:
    """Resolve ``host`` to an IPv4 address, retrying transient mDNS failures.

    IP literals are returned as-is. Raises :class:`SSHError` if resolution keeps
    failing (e.g. the name genuinely doesn't exist or mDNS never answers).
    """
    # IP literal? Return unchanged (no lookup needed).
    try:
        socket.getaddrinfo(host, None, family=socket.AF_INET, flags=socket.AI_NUMERICHOST)
        return host
    except socket.gaierror:
        pass

    last = ""
    for attempt in range(_RESOLVE_ATTEMPTS):
        try:
            infos = socket.getaddrinfo(
                host, None, family=socket.AF_INET, type=socket.SOCK_STREAM
            )
            if infos:
                return infos[0][4][0]
        except socket.gaierror as exc:
            last = str(exc)
        if attempt < _RESOLVE_ATTEMPTS - 1:
            time.sleep(_RESOLVE_DELAY)
    raise SSHError(f"could not resolve {host} ({last or 'no address returned'})")


# --- command construction ----------------------------------------------------


def _common_opts(timeout: int) -> list[str]:
    return [
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", f"UserKnownHostsFile={KNOWN_HOSTS}",
        "-o", f"ConnectTimeout={timeout}",
        "-o", "ServerAliveInterval=5",
        "-o", "ServerAliveCountMax=3",
    ]


def _auth_opts(session: SSHSession) -> list[str]:
    if session.auth == "password":
        return [
            "-o", "PubkeyAuthentication=no",
            "-o", "PreferredAuthentications=password,keyboard-interactive",
            "-o", "NumberOfPasswordPrompts=1",
        ]
    # key auth: OpenSSH auto-loads <key>-cert.pub next to the identity file.
    return [
        "-o", "BatchMode=yes",
        "-o", "PasswordAuthentication=no",
        "-o", "PreferredAuthentications=publickey",
        "-i", str(session.key_path),
    ]


def _prefix(session: SSHSession) -> list[str]:
    if session.auth == "password":
        return ["sshpass", "-p", session.password]
    return []


def run(client: SSHSession, command: str, *, timeout: int = 120) -> RemoteResult:
    """Run a command over the session and capture its result."""
    argv = (
        _prefix(client)
        + ["ssh"]
        + _common_opts(min(timeout, 30))
        + ["-o", f"HostKeyAlias={client.host}"]
        + _auth_opts(client)
        + ["-p", str(client.port), f"{client.user}@{client.address}", command]
    )
    try:
        proc = subprocess.run(
            argv, capture_output=True, text=True, timeout=timeout + 10
        )
    except subprocess.TimeoutExpired:
        return RemoteResult(command, 124, "", f"timed out after {timeout}s")
    except FileNotFoundError as exc:
        raise SSHError(f"required binary missing ({exc.filename})") from exc
    return RemoteResult(command, proc.returncode, proc.stdout, proc.stderr)


def _scp(session: SSHSession, local: Path, remote_path: str, *, timeout: int = 60) -> RemoteResult:
    argv = (
        _prefix(session)
        + ["scp"]
        + _common_opts(min(timeout, 30))
        + ["-o", f"HostKeyAlias={session.host}"]
        + _auth_opts(session)
        + ["-P", str(session.port), str(local), f"{session.user}@{session.address}:{remote_path}"]
    )
    try:
        proc = subprocess.run(
            argv, capture_output=True, text=True, timeout=timeout + 10
        )
    except subprocess.TimeoutExpired:
        return RemoteResult(f"scp {local}", 124, "", f"timed out after {timeout}s")
    except FileNotFoundError as exc:
        raise SSHError(f"required binary missing ({exc.filename})") from exc
    return RemoteResult(f"scp {local.name}", proc.returncode, proc.stdout, proc.stderr)


def _looks_like_auth_failure(res: RemoteResult) -> bool:
    text = (res.stderr or "").lower()
    return any(
        s in text
        for s in ("permission denied", "authentication failed", "too many authentication")
    )


def _probe(session: SSHSession, timeout: int) -> str | None:
    """Return None if the session works, else a short failure reason."""
    res = run(session, "true", timeout=timeout)
    if res.ok:
        return None
    detail = (res.stderr or res.stdout).strip().splitlines()
    return detail[-1].strip() if detail else f"exit {res.exit_code}"


def connect(node: dict, *, timeout: int = 12) -> SSHSession:
    """Open (and validate) an SSH session to a node - key first, password fallback.

    Args:
        node: Normalized node dict (name/host/ssh_user/ssh_port/ssh_key/ssh_password).
        timeout: Per-attempt connect timeout in seconds.

    Raises:
        SSHError: When no credentials exist or every attempt fails.
    """
    key_path = private_key_path(node.get("ssh_key") or "")
    password = node.get("ssh_password") or ""
    host = node["host"]
    port = int(node.get("ssh_port") or 22)
    user = node["ssh_user"]
    label = f"{node['name']} ({user}@{host}:{port})"

    if key_path is None and not password:
        raise SSHError(
            f"{label}: no usable SSH key set "
            f"({node.get('ssh_key') or 'none'!r}) and no password set"
        )

    # Resolve up front (with retries) so a flaky mDNS lookup doesn't sink the run;
    # every subsequent ssh/scp dials this IP directly.
    try:
        address = resolve_host(host)
    except SSHError as exc:
        raise SSHError(f"{label}: unreachable ({exc})") from exc

    reasons: list[str] = []

    if key_path is not None:
        session = SSHSession(node, host, address, port, user, key_path, password, "key")
        reason = _probe(session, timeout)
        if reason is None:
            return session
        reasons.append(f"key: {reason}")
        # A connection-level failure (refused/timeout) won't be fixed by a
        # password, so surface it as unreachable right away.
        if not _looks_like_auth_failure(run(session, "true", timeout=timeout)):
            raise SSHError(f"{label}: unreachable ({reason})")

    if password:
        if shutil.which("sshpass") is None:
            reasons.append("password: sshpass not installed")
        else:
            session = SSHSession(node, host, address, port, user, key_path, password, "password")
            reason = _probe(session, timeout)
            if reason is None:
                return session
            reasons.append(f"password: {reason}")

    raise SSHError(f"{label}: authentication failed ({'; '.join(reasons)})")


def put_files(
    client: SSHSession,
    files: list[tuple[Path, str, int]],
    remote_dir: str,
) -> list[str]:
    """Upload files into ``remote_dir`` (created 0700), returning basenames.

    ``files`` is a list of ``(local_path, remote_basename, mode)`` tuples.
    """
    quoted_dir = shlex.quote(remote_dir)
    mk = run(client, f"mkdir -p {quoted_dir} && chmod 700 {quoted_dir}")
    if not mk.ok:
        raise SSHError(f"could not prepare {remote_dir}: {mk.output()}")

    pushed: list[str] = []
    for local_path, basename, mode in files:
        remote_path = f"{remote_dir.rstrip('/')}/{basename}"
        res = _scp(client, local_path, remote_path)
        if not res.ok:
            raise SSHError(f"failed to copy {basename}: {res.output()}")
        run(client, f"chmod {mode:o} {shlex.quote(remote_path)}")
        pushed.append(basename)
    return pushed


__all__ = [
    "KNOWN_HOSTS",
    "RemoteResult",
    "SSHError",
    "SSHSession",
    "connect",
    "private_key_path",
    "put_files",
    "resolve_host",
    "run",
]
