"""In-memory working copy of the Vault KV config, backed by config.tfvars.

The on-disk file is the source of truth. This store holds an editable *working*
copy (mount path + secrets, plus any hand-authored ``secret_files`` round-tripped
verbatim) alongside a *baseline* of what was last synced with disk so it can
report ``dirty`` (unsaved edits) and ``external_change`` (out-of-band file edits).
Edits mutate the working copy only; nothing touches disk until :meth:`write`.
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

from homelab_config.paths import VAULT_CONFIG_TFVARS
from homelab_config.vault_config import (
    DEFAULT_MOUNT_PATH,
    SecretValidationError,
    canonical,
    normalize_mount_path,
    normalize_secret,
    order_secrets,
    read_vault_tfvars,
    render_config,
    write_vault_tfvars,
)

logger = logging.getLogger(__name__)


class StoreError(Exception):
    """Raised for store-level errors (missing/duplicate secrets)."""


class VaultConfigStore:
    """Thread-safe working copy of the Vault mount path + KV secrets."""

    def __init__(self, path: Path = VAULT_CONFIG_TFVARS) -> None:
        self._path = path
        self._lock = threading.RLock()
        self._mount_path: str = DEFAULT_MOUNT_PATH
        self._secrets: list[dict] = []
        self._secret_files: dict = {}
        self._baseline_mount: str = DEFAULT_MOUNT_PATH
        self._baseline_secrets: list[dict] = []
        self._baseline_files: dict = {}
        self.reload()

    # -- reads -----------------------------------------------------------------

    def get(self) -> dict:
        """Return the working mount path and secrets (secrets ordered)."""
        with self._lock:
            return {
                "mount_path": self._mount_path,
                "secrets": [self._copy(s) for s in order_secrets(self._secrets)],
            }

    def render(self) -> str:
        """Return the rendered tfvars for the current working copy."""
        with self._lock:
            return render_config(self._mount_path, self._secrets, self._secret_files)

    def status(self) -> dict:
        """Return drift/status flags for the UI."""
        with self._lock:
            disk = read_vault_tfvars(self._path) or {
                "mount_path": DEFAULT_MOUNT_PATH,
                "secrets": [],
                "secret_files": {},
            }
            baseline = canonical(
                self._baseline_mount, self._baseline_secrets, self._baseline_files
            )
            return {
                "dirty": canonical(self._mount_path, self._secrets, self._secret_files)
                != baseline,
                "external_change": canonical(
                    disk["mount_path"], disk["secrets"], disk["secret_files"]
                )
                != baseline,
                "disk_present": self._path.is_file(),
                "count": len(self._secrets),
            }

    # -- mutations (working copy only) ----------------------------------------

    def set_mount_path(self, value: str) -> str:
        """Replace the working KV mount path."""
        with self._lock:
            self._mount_path = normalize_mount_path(value)
            return self._mount_path

    def add(self, data: dict) -> dict:
        """Add a new secret to the working copy."""
        secret = normalize_secret(data)
        with self._lock:
            if self._find(secret["key"]) is not None:
                raise StoreError(f"secret '{secret['key']}' already exists")
            self._secrets.append(secret)
            return self._copy(secret)

    def update(self, key: str, data: dict) -> dict:
        """Update the secret with ``key`` in the working copy."""
        with self._lock:
            current = self._find(key)
            if current is None:
                raise StoreError(f"secret '{key}' not found")
            merged = dict(data)
            merged.setdefault("group", current["group"])
            merged.setdefault("name", current["name"])
            if "fields" not in merged:
                merged["fields"] = current["fields"]
            secret = normalize_secret(merged)
            if secret["key"] != key and self._find(secret["key"]) is not None:
                raise StoreError(f"secret '{secret['key']}' already exists")
            current.update(secret)
            return self._copy(current)

    def delete(self, key: str) -> None:
        """Delete the secret with ``key`` from the working copy."""
        with self._lock:
            secret = self._find(key)
            if secret is None:
                raise StoreError(f"secret '{key}' not found")
            self._secrets.remove(secret)

    # -- disk sync -------------------------------------------------------------

    def write(self) -> Path:
        """Persist the working copy to disk and update the baseline."""
        with self._lock:
            path = write_vault_tfvars(
                self._mount_path, self._secrets, self._secret_files, self._path
            )
            self._baseline_mount = self._mount_path
            self._baseline_secrets = [self._copy(s) for s in self._secrets]
            self._baseline_files = self._copy_files(self._secret_files)
            return path

    def reload(self) -> None:
        """Reload the working copy from disk, discarding unsaved edits."""
        with self._lock:
            data = read_vault_tfvars(self._path) or {
                "mount_path": DEFAULT_MOUNT_PATH,
                "secrets": [],
                "secret_files": {},
            }
            self._mount_path = data["mount_path"]
            self._secrets = [self._copy(s) for s in data["secrets"]]
            self._secret_files = self._copy_files(data["secret_files"])
            self._baseline_mount = self._mount_path
            self._baseline_secrets = [self._copy(s) for s in self._secrets]
            self._baseline_files = self._copy_files(self._secret_files)

    # -- internals -------------------------------------------------------------

    @staticmethod
    def _copy(secret: dict) -> dict:
        return {
            "key": secret["key"],
            "group": secret["group"],
            "name": secret["name"],
            "fields": dict(secret.get("fields", {})),
        }

    @staticmethod
    def _copy_files(files: dict) -> dict:
        return {
            group: {name: dict(fields) for name, fields in (names or {}).items()}
            for group, names in (files or {}).items()
        }

    def _find(self, key: str) -> dict | None:
        for secret in self._secrets:
            if secret["key"] == key:
                return secret
        return None


__all__ = ["VaultConfigStore", "StoreError", "SecretValidationError"]
