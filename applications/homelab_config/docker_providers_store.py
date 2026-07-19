"""In-memory working copy of the Docker provider catalog.

The catalog blends three sources:

- *Derived* swarm-node providers - read live from ``docker/swarm.tfvars`` on
  every render. Not editable here and never counted as drift.
- Editable *extra (non-swarm) hosts* - full machine definitions persisted to
  ``docker/extra_hosts.yaml`` (same shape as swarm nodes, minus role/labels).
- Editable *registry_auths* - persisted to the derived
  ``terraform/providers/docker.tfvars`` (the only editable state in that file).

Edits mutate the working copy only; :meth:`write` persists both editable stores
(re-deriving all providers into docker.tfvars), and :meth:`reload` re-reads them.
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

from homelab_config.docker_providers_config import (
    DockerConfigError,
    canonical_registry_auths,
    normalize_registry_auth,
    order_registry_auths,
    provider_from_machine,
    read_registry_auths,
    render_docker_tfvars,
    ssh_dir_abs,
    write_docker_tfvars,
)
from homelab_config.extra_hosts_config import (
    ExtraHostValidationError,
    canonical as canonical_extra_hosts,
    normalize_extra_host,
    order_extra_hosts,
    read_extra_hosts,
    write_extra_hosts,
)
from homelab_config.paths import DOCKER_TFVARS, EXTRA_HOSTS_YAML, SWARM_TFVARS
from homelab_config.swarm_config import order_nodes, read_swarm_tfvars

logger = logging.getLogger(__name__)


class StoreError(Exception):
    """Raised for store-level errors (missing/duplicate entries)."""


class DockerProvidersStore:
    """Thread-safe working copy of the editable Docker catalog state."""

    def __init__(
        self,
        path: Path = DOCKER_TFVARS,
        swarm_path: Path = SWARM_TFVARS,
        extra_hosts_path: Path = EXTRA_HOSTS_YAML,
    ) -> None:
        self._path = path
        self._swarm_path = swarm_path
        self._extra_hosts_path = extra_hosts_path
        self._lock = threading.RLock()
        self._extra_hosts: list[dict] = []
        self._registry_auths: list[dict] = []
        self._hosts_baseline: tuple = canonical_extra_hosts([])
        self._registry_baseline: tuple = canonical_registry_auths([])
        self.reload()

    # -- swarm (derived) -------------------------------------------------------

    def _nodes(self) -> list[dict]:
        return order_nodes(read_swarm_tfvars(self._swarm_path) or [])

    def _swarm_names(self) -> set[str]:
        return {node["name"] for node in self._nodes()}

    # -- reads -----------------------------------------------------------------

    def snapshot(self) -> dict:
        """Return derived providers + editable extra hosts + registry for the UI."""
        with self._lock:
            ssh_dir = ssh_dir_abs()
            derived = [
                {
                    "name": node["name"],
                    "role": node.get("role", ""),
                    **provider_from_machine(node, ssh_dir),
                }
                for node in self._nodes()
            ]
            extras = []
            for host in order_extra_hosts(self._extra_hosts):
                provider = provider_from_machine(host, ssh_dir)
                # Keep the raw host/user/port fields for the edit form; expose the
                # derived provider connection string separately (provider_host).
                extras.append(
                    {
                        **host,
                        "provider_host": provider["host"],
                        "ssh_opts": provider["ssh_opts"],
                    }
                )
            return {
                "derived": derived,
                "extra_hosts": extras,
                "registry_auths": order_registry_auths(self._registry_auths),
            }

    def render(self) -> str:
        """Return the rendered tfvars for the current working copy."""
        with self._lock:
            return render_docker_tfvars(
                self._nodes(), self._extra_hosts, self._registry_auths
            )

    def get_host(self, name: str) -> dict | None:
        """Return a copy of the working extra host, or ``None``."""
        with self._lock:
            host = self._find_host(name)
            return dict(host) if host is not None else None

    def status(self) -> dict:
        """Return drift/status flags for the UI (editable state only)."""
        with self._lock:
            disk_hosts = read_extra_hosts(self._extra_hosts_path)
            disk_auths = read_registry_auths(self._path)
            working_hosts = canonical_extra_hosts(self._extra_hosts)
            working_auths = canonical_registry_auths(self._registry_auths)
            disk_hosts_canonical = (
                canonical_extra_hosts(disk_hosts)
                if disk_hosts is not None
                else self._hosts_baseline
            )
            disk_auths_canonical = (
                canonical_registry_auths(disk_auths)
                if disk_auths is not None
                else self._registry_baseline
            )
            dirty = (
                working_hosts != self._hosts_baseline
                or working_auths != self._registry_baseline
            )
            external = (
                disk_hosts_canonical != self._hosts_baseline
                or disk_auths_canonical != self._registry_baseline
            )
            return {
                "dirty": dirty,
                "external_change": external,
                "disk_present": self._path.is_file(),
                "extra_host_count": len(self._extra_hosts),
                "registry_count": len(self._registry_auths),
            }

    # -- extra-host mutations (working copy only) ------------------------------

    def add_host(self, data: dict) -> dict:
        host = normalize_extra_host(data)
        with self._lock:
            if host["name"] in self._swarm_names():
                raise StoreError(
                    f"'{host['name']}' is a swarm node (managed on the Swarm page)"
                )
            if self._find_host(host["name"]) is not None:
                raise StoreError(f"host '{host['name']}' already exists")
            self._extra_hosts.append(host)
            return dict(host)

    def update_host(self, name: str, data: dict) -> dict:
        merged = {**data, "name": data.get("name", name)}
        host = normalize_extra_host(merged)
        with self._lock:
            current = self._find_host(name)
            if current is None:
                raise StoreError(f"host '{name}' not found")
            if host["name"] != name:
                if host["name"] in self._swarm_names():
                    raise StoreError(
                        f"'{host['name']}' is a swarm node (managed on the Swarm page)"
                    )
                if self._find_host(host["name"]) is not None:
                    raise StoreError(f"host '{host['name']}' already exists")
            current.clear()
            current.update(host)
            return dict(current)

    def delete_host(self, name: str) -> None:
        with self._lock:
            host = self._find_host(name)
            if host is None:
                raise StoreError(f"host '{name}' not found")
            self._extra_hosts.remove(host)

    # -- registry mutations (working copy only) --------------------------------

    def add_registry(self, data: dict) -> dict:
        auth = normalize_registry_auth(data)
        with self._lock:
            if self._find_registry(auth["address"]) is not None:
                raise StoreError(f"registry '{auth['address']}' already exists")
            self._registry_auths.append(auth)
            return dict(auth)

    def update_registry(self, address: str, data: dict) -> dict:
        merged = {**data, "address": data.get("address", address)}
        auth = normalize_registry_auth(merged)
        with self._lock:
            current = self._find_registry(address)
            if current is None:
                raise StoreError(f"registry '{address}' not found")
            if auth["address"] != address and self._find_registry(auth["address"]) is not None:
                raise StoreError(f"registry '{auth['address']}' already exists")
            current.clear()
            current.update(auth)
            return dict(current)

    def delete_registry(self, address: str) -> None:
        with self._lock:
            auth = self._find_registry(address)
            if auth is None:
                raise StoreError(f"registry '{address}' not found")
            self._registry_auths.remove(auth)

    # -- disk sync -------------------------------------------------------------

    def write(self) -> Path:
        """Persist both editable stores (re-deriving providers) and set baselines."""
        with self._lock:
            write_extra_hosts(self._extra_hosts, self._extra_hosts_path)
            path = write_docker_tfvars(
                self._nodes(), self._extra_hosts, self._registry_auths, self._path
            )
            self._hosts_baseline = canonical_extra_hosts(self._extra_hosts)
            self._registry_baseline = canonical_registry_auths(self._registry_auths)
            return path

    def refresh_derived(self) -> Path | None:
        """Re-render docker.tfvars to pick up swarm-node changes (derived portion).

        Returns the path when the on-disk file changed, else ``None``. Leaves the
        editable working copies and baselines untouched.
        """
        with self._lock:
            desired = self.render()
            try:
                current = self._path.read_text(encoding="utf-8")
            except (FileNotFoundError, OSError):
                current = None
            if current == desired:
                return None
            return write_docker_tfvars(
                self._nodes(), self._extra_hosts, self._registry_auths, self._path
            )

    def reload(self) -> None:
        """Reload both editable working copies from disk, discarding unsaved edits."""
        with self._lock:
            hosts = read_extra_hosts(self._extra_hosts_path) or []
            auths = read_registry_auths(self._path) or []
            self._extra_hosts = [dict(h) for h in hosts]
            self._registry_auths = [dict(a) for a in auths]
            self._hosts_baseline = canonical_extra_hosts(self._extra_hosts)
            self._registry_baseline = canonical_registry_auths(self._registry_auths)

    # -- internals -------------------------------------------------------------

    def _find_host(self, name: str) -> dict | None:
        for host in self._extra_hosts:
            if host["name"] == name:
                return host
        return None

    def _find_registry(self, address: str) -> dict | None:
        for auth in self._registry_auths:
            if auth["address"] == address:
                return auth
        return None


__all__ = ["DockerProvidersStore", "StoreError", "DockerConfigError", "ExtraHostValidationError"]
