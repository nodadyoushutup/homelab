"""In-memory working copy of the swarm topology, backed by swarm.tfvars on disk.

The on-disk file is the source of truth. This store holds an editable *working*
copy plus a *baseline* snapshot of what we last synced with disk, so we can
report:

- ``dirty``: the working copy has unsaved edits (differs from baseline).
- ``external_change``: the file on disk changed out of band (differs from
  baseline) - e.g. someone edited it by hand while the app was running.

Edits mutate the working copy only; nothing touches disk until :meth:`write` is
called. :meth:`reload` re-reads the file, discarding unsaved edits.
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

from homelab_config.paths import SWARM_TFVARS
from homelab_config.swarm_config import (
    NodeValidationError,
    canonical,
    normalize_node,
    order_nodes,
    read_swarm_tfvars,
    render_nodes,
    write_swarm_tfvars,
)

logger = logging.getLogger(__name__)


class StoreError(Exception):
    """Raised for store-level errors (missing/duplicate nodes)."""


class SwarmStore:
    """Thread-safe working copy of the swarm nodes."""

    def __init__(self, path: Path = SWARM_TFVARS) -> None:
        self._path = path
        self._lock = threading.RLock()
        self._working: list[dict] = []
        self._baseline: list[dict] = []
        self.reload()

    # -- reads -----------------------------------------------------------------

    def list_nodes(self) -> list[dict]:
        """Return the working nodes (managers first, then workers)."""
        with self._lock:
            return [dict(node) for node in order_nodes(self._working)]

    def render(self) -> str:
        """Return the rendered tfvars for the current working copy."""
        with self._lock:
            return render_nodes(self._working)

    def status(self) -> dict:
        """Return drift/status flags for the UI."""
        with self._lock:
            disk = read_swarm_tfvars(self._path) or []
            baseline = canonical(self._baseline)
            return {
                "dirty": canonical(self._working) != baseline,
                "external_change": canonical(disk) != baseline,
                "disk_present": self._path.is_file(),
                "count": len(self._working),
            }

    # -- mutations (working copy only) ----------------------------------------

    def add(self, data: dict) -> dict:
        """Add a new node to the working copy."""
        node = normalize_node(data)
        with self._lock:
            if self._find(node["name"]) is not None:
                raise StoreError(f"node '{node['name']}' already exists")
            self._working.append(node)
            return dict(node)

    def update(self, name: str, data: dict) -> dict:
        """Update the node named ``name`` in the working copy."""
        merged = {"name": name}
        merged.update(data)
        node = normalize_node(merged)
        with self._lock:
            current = self._find(name)
            if current is None:
                raise StoreError(f"node '{name}' not found")
            if node["name"] != name and self._find(node["name"]) is not None:
                raise StoreError(f"node '{node['name']}' already exists")
            current.update(node)
            return dict(current)

    def delete(self, name: str) -> None:
        """Delete the node named ``name`` from the working copy."""
        with self._lock:
            node = self._find(name)
            if node is None:
                raise StoreError(f"node '{name}' not found")
            self._working.remove(node)

    # -- disk sync -------------------------------------------------------------

    def write(self) -> Path:
        """Persist the working copy to disk and update the baseline."""
        with self._lock:
            path = write_swarm_tfvars(self._working, self._path)
            self._baseline = [dict(node) for node in self._working]
            return path

    def reload(self) -> None:
        """Reload the working copy from disk, discarding unsaved edits.

        A missing or unparsable file is treated as an empty topology (the boot
        scaffold writes an empty ``swarm.tfvars`` so a fresh checkout starts
        clean rather than with a fabricated default set of nodes).
        """
        with self._lock:
            nodes = read_swarm_tfvars(self._path) or []
            self._working = [dict(node) for node in nodes]
            self._baseline = [dict(node) for node in nodes]

    # -- internals -------------------------------------------------------------

    def _find(self, name: str) -> dict | None:
        for node in self._working:
            if node["name"] == name:
                return node
        return None


__all__ = ["StoreError", "SwarmStore", "NodeValidationError"]
