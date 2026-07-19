"""Manage SSH key sets under ``.config/.ssh``.

Layout::

    .config/.ssh/
    ├── config              # shared client config (loose root file)
    ├── known_hosts         # shared known_hosts (loose root file)
    └── <set>/              # a named key set, e.g. "ca"
        ├── id_ed25519      # private key (never returned to the browser)
        ├── id_ed25519.pub  # public key
        └── id_ed25519-cert.pub

Each *subdirectory* of ``.config/.ssh`` is a key set (an independent key pair).
Loose files at the root (``config``/``known_hosts``) are treated as *shared*
client files. Operations write straight to disk - there is no staged working
copy. Private key material is never returned to the browser; only metadata
(name, size, mode, kind, and a public fingerprint where derivable).
"""

from __future__ import annotations

import logging
import os
import shutil
import stat
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from homelab_config.paths import HOST_SSH_DIR, SSH_DIR

logger = logging.getLogger(__name__)

_MODE_PRIVATE = 0o600
_MODE_PUBLIC = 0o644
_DIR_MODE = 0o700

# File kinds that make up a key set's key pair.
_KEYPAIR_KINDS = {"private_key", "public_key", "certificate"}
_PRIVATE_KINDS = {"private_key"}
# What "sync from host" pulls in / lists as syncable. Includes authorized_keys so
# a set also carries the public keys to authorize on managed machines.
_SYNC_KINDS = _KEYPAIR_KINDS | {"authorized_keys"}

_PUBLIC_PREFIXES = (
    "ssh-ed25519",
    "ssh-rsa",
    "ssh-dss",
    "ecdsa-sha2-",
    "sk-ssh-ed25519",
    "sk-ecdsa-sha2-",
)


class SSHError(Exception):
    """Raised for SSH management errors (bad name, missing file, bad content)."""


# --- helpers -----------------------------------------------------------------


def _ensure_root() -> None:
    SSH_DIR.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(SSH_DIR, _DIR_MODE)
    except OSError:
        pass


def safe_name(name: str) -> str:
    """Return a validated bare name (no path separators / traversal)."""
    cleaned = (name or "").strip()
    if not cleaned or cleaned in {".", ".."}:
        raise SSHError("a name is required")
    if os.path.basename(cleaned) != cleaned or "/" in cleaned or "\\" in cleaned:
        raise SSHError(f"invalid name: {name!r}")
    return cleaned


def _set_dir(set_name: str) -> Path:
    path = SSH_DIR / safe_name(set_name)
    if path.exists() and not path.is_dir():
        raise SSHError(f"{set_name!r} is not a key set")
    return path


def _classify(name: str, head: bytes) -> str:
    if name.endswith("-cert.pub"):
        return "certificate"
    if name.endswith(".pub"):
        return "public_key"
    if name == "config":
        return "config"
    if name.startswith("known_hosts"):
        return "known_hosts"
    if name == "authorized_keys":
        return "authorized_keys"
    text = head.decode("utf-8", "replace").lstrip()
    if "PRIVATE KEY" in text:
        return "private_key"
    if text.startswith(_PUBLIC_PREFIXES):
        return "public_key"
    return "other"


def _fingerprint(path: Path) -> str | None:
    """Best-effort public fingerprint via ssh-keygen; None if unavailable."""
    try:
        result = subprocess.run(
            ["ssh-keygen", "-lf", str(path)],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    for part in result.stdout.strip().split():
        if part.startswith(("SHA256:", "MD5:")):
            return part
    return None


def _describe(path: Path) -> dict:
    st = path.stat()
    try:
        with path.open("rb") as handle:
            head = handle.read(256)
    except OSError:
        head = b""
    kind = _classify(path.name, head)
    return {
        "name": path.name,
        "size": st.st_size,
        "mode": stat.filemode(st.st_mode),
        "octal": format(stat.S_IMODE(st.st_mode), "04o"),
        "modified": datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat(),
        "kind": kind,
        "sensitive": kind in _PRIVATE_KINDS,
        "fingerprint": (
            _fingerprint(path) if kind in _KEYPAIR_KINDS else None
        ),
    }


def _describe_set(path: Path) -> dict:
    files = [
        _describe(entry)
        for entry in sorted(path.iterdir(), key=lambda p: p.name)
        if entry.is_file()
    ]
    kinds = {f["kind"] for f in files}
    fingerprint = next(
        (
            f["fingerprint"]
            for f in files
            if f["kind"] == "public_key" and f["fingerprint"]
        ),
        None,
    )
    return {
        "name": path.name,
        "files": files,
        "has_private": "private_key" in kinds,
        "has_public": "public_key" in kinds,
        "has_certificate": "certificate" in kinds,
        "fingerprint": fingerprint,
    }


# --- reads -------------------------------------------------------------------


def list_sets() -> list[dict]:
    """Return every key set (subdirectory) under ``.config/.ssh``."""
    if not SSH_DIR.is_dir():
        return []
    return [
        _describe_set(entry)
        for entry in sorted(SSH_DIR.iterdir(), key=lambda p: p.name)
        if entry.is_dir()
    ]


def list_shared() -> list[dict]:
    """Return loose (non-set) files at the root of ``.config/.ssh``."""
    if not SSH_DIR.is_dir():
        return []
    return [
        _describe(entry)
        for entry in sorted(SSH_DIR.iterdir(), key=lambda p: p.name)
        if entry.is_file()
    ]


def host_files() -> list[dict]:
    """Return keypair files present in the host's ~/.ssh (for syncing)."""
    if not HOST_SSH_DIR.is_dir():
        return []
    out: list[dict] = []
    for entry in sorted(HOST_SSH_DIR.iterdir(), key=lambda p: p.name):
        if not entry.is_file():
            continue
        try:
            with entry.open("rb") as handle:
                head = handle.read(256)
        except OSError:
            continue
        kind = _classify(entry.name, head)
        if kind in _SYNC_KINDS:
            out.append({"name": entry.name, "kind": kind})
    return out


def snapshot() -> dict:
    """Return the full view used by the UI/socket broadcast."""
    return {
        "sets": list_sets(),
        "shared": list_shared(),
        "host": host_files(),
    }


def read_public(set_name: str, name: str) -> str:
    """Return the text of a non-sensitive file within a set."""
    path = _set_dir(set_name) / safe_name(name)
    if not path.is_file():
        raise SSHError(f"file not found: {name}")
    with path.open("rb") as handle:
        head = handle.read(256)
    if _classify(path.name, head) in _PRIVATE_KINDS:
        raise SSHError("refusing to return private key material")
    return path.read_text(encoding="utf-8", errors="replace")


# --- mutations ---------------------------------------------------------------


def _apply_mode(path: Path, kind: str) -> None:
    mode = _MODE_PRIVATE if kind in {"private_key", "config"} else _MODE_PUBLIC
    try:
        os.chmod(path, mode)
    except OSError:
        pass


def create_set(name: str) -> dict:
    """Create a new (empty) key set directory."""
    safe = safe_name(name)
    _ensure_root()
    path = SSH_DIR / safe
    if path.exists():
        raise SSHError(f"key set {safe!r} already exists")
    path.mkdir(mode=_DIR_MODE)
    logger.info("Created SSH key set %s", path)
    return _describe_set(path)


def delete_set(name: str) -> None:
    """Delete a key set directory and everything in it."""
    path = _set_dir(name)
    if not path.is_dir():
        raise SSHError(f"key set not found: {name}")
    shutil.rmtree(path)
    logger.info("Deleted SSH key set %s", path)


def sync_from_host(set_name: str) -> list[str]:
    """Copy the host ~/.ssh key pair (private/public/cert) into a set."""
    if not HOST_SSH_DIR.is_dir():
        raise SSHError(f"host SSH directory not found: {HOST_SSH_DIR}")
    dest_dir = _set_dir(set_name)
    dest_dir.mkdir(mode=_DIR_MODE, parents=True, exist_ok=True)
    copied: list[str] = []
    for entry in sorted(HOST_SSH_DIR.iterdir(), key=lambda p: p.name):
        if not entry.is_file():
            continue
        try:
            with entry.open("rb") as handle:
                head = handle.read(256)
        except OSError:
            continue
        kind = _classify(entry.name, head)
        if kind not in _SYNC_KINDS:
            continue
        dest = dest_dir / entry.name
        shutil.copyfile(entry, dest)
        _apply_mode(dest, kind)
        copied.append(entry.name)
    if not copied:
        raise SSHError(f"no key pair files found in {HOST_SSH_DIR}")
    logger.info("Synced %d key file(s) from %s into set %s", len(copied), HOST_SSH_DIR, set_name)
    return copied


def save_key(set_name: str, kind: str, name: str, content: bytes) -> dict:
    """Write an uploaded private or public key into a set.

    ``kind`` must be ``"private"`` or ``"public"``. Content is validated so a
    public key is not stored as a private key (or vice versa).
    """
    if kind not in {"private", "public"}:
        raise SSHError(f"unknown key kind: {kind!r}")
    safe = safe_name(name)
    text = content.decode("utf-8", "replace").strip()
    if not text:
        raise SSHError("uploaded file is empty")

    if kind == "private":
        if "PRIVATE KEY" not in text:
            raise SSHError(
                "that does not look like a private key "
                "(expected a '-----BEGIN ... PRIVATE KEY-----' block)"
            )
        file_kind = "private_key"
    else:
        if not text.startswith(_PUBLIC_PREFIXES):
            raise SSHError(
                "that does not look like a public key "
                "(expected it to start with e.g. 'ssh-ed25519' or 'ssh-rsa')"
            )
        file_kind = "certificate" if safe.endswith("-cert.pub") else "public_key"

    dest_dir = _set_dir(set_name)
    dest_dir.mkdir(mode=_DIR_MODE, parents=True, exist_ok=True)
    dest = dest_dir / safe
    dest.write_bytes(content if content.endswith(b"\n") else content + b"\n")
    _apply_mode(dest, file_kind)
    logger.info("Saved %s key %s to set %s", kind, safe, set_name)
    return _describe(dest)


def save_authorized_keys(set_name: str, content: str) -> dict:
    """Write (overwrite) the ``authorized_keys`` file in a set.

    The content is the list of public keys that should be authorized on machines
    this set bootstraps. Stored world-readable (public material only). Pass empty
    content to remove it (use the per-file delete for the same effect).
    """
    dest_dir = _set_dir(set_name)
    if not dest_dir.is_dir():
        raise SSHError(f"key set not found: {set_name}")
    text = (content or "").strip()
    dest = dest_dir / "authorized_keys"
    if not text:
        raise SSHError("authorized_keys content is empty")
    dest.write_text(text + "\n", encoding="utf-8")
    _apply_mode(dest, "authorized_keys")
    logger.info("Saved authorized_keys to set %s", set_name)
    return _describe(dest)


def delete_file(set_name: str, name: str) -> None:
    """Delete a single file from a key set."""
    path = _set_dir(set_name) / safe_name(name)
    if not path.is_file():
        raise SSHError(f"file not found: {name}")
    path.unlink()
    logger.info("Deleted %s from set %s", name, set_name)


__all__ = [
    "SSHError",
    "create_set",
    "delete_file",
    "delete_set",
    "host_files",
    "list_sets",
    "list_shared",
    "read_public",
    "safe_name",
    "save_authorized_keys",
    "save_key",
    "snapshot",
    "sync_from_host",
]
