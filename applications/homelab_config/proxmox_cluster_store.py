"""In-memory working copy of the Proxmox cluster config (images + machines),
backed by ``.config/terraform/components/cluster/proxmox/app.tfvars`` on disk.

The on-disk file is the source of truth. This store holds an editable *working*
copy plus a *baseline* snapshot of what we last synced with disk, so we can
report:

- ``dirty``: the working copy has unsaved edits (differs from baseline).
- ``external_change``: the file on disk changed out of band (differs from
  baseline).

Edits mutate the working copy only; nothing touches disk until :meth:`write` is
called. :meth:`reload` re-reads the file, discarding unsaved edits.
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

from homelab_config.paths import PROXMOX_APP_TFVARS
from homelab_config.proxmox_cluster_config import (
    ImageValidationError,
    MachineValidationError,
    canonical,
    normalize_image,
    normalize_machine,
    order_images,
    order_machines,
    read_proxmox_app_tfvars,
    render_config,
    write_proxmox_app_tfvars,
)

logger = logging.getLogger(__name__)


class StoreError(Exception):
    """Raised for store-level errors (missing/duplicate/referenced entries)."""


class ProxmoxClusterStore:
    """Thread-safe working copy of the Proxmox images + machines."""

    def __init__(self, path: Path = PROXMOX_APP_TFVARS) -> None:
        self._path = path
        self._lock = threading.RLock()
        self._images: list[dict] = []
        self._machines: list[dict] = []
        self._baseline_images: list[dict] = []
        self._baseline_machines: list[dict] = []
        self.reload()

    # -- reads -----------------------------------------------------------------

    def list_images(self) -> list[dict]:
        with self._lock:
            return [dict(image) for image in order_images(self._images)]

    def list_machines(self) -> list[dict]:
        with self._lock:
            return [dict(machine) for machine in order_machines(self._machines)]

    def snapshot(self) -> dict:
        """Return both lists for the UI in one payload."""
        with self._lock:
            return {
                "images": [dict(i) for i in order_images(self._images)],
                "machines": [dict(m) for m in order_machines(self._machines)],
            }

    def render(self) -> str:
        with self._lock:
            return render_config(self._images, self._machines)

    def status(self) -> dict:
        with self._lock:
            disk = read_proxmox_app_tfvars(self._path) or {"images": [], "machines": []}
            baseline = canonical(self._baseline_images, self._baseline_machines)
            return {
                "dirty": canonical(self._images, self._machines) != baseline,
                "external_change": canonical(disk["images"], disk["machines"])
                != baseline,
                "disk_present": self._path.is_file(),
                "images": len(self._images),
                "machines": len(self._machines),
            }

    # -- image mutations (working copy only) ----------------------------------

    def add_image(self, data: dict) -> dict:
        image = normalize_image(data)
        with self._lock:
            if self._find_image(image["key"]) is not None:
                raise StoreError(f"image '{image['key']}' already exists")
            self._images.append(image)
            return dict(image)

    def update_image(self, key: str, data: dict) -> dict:
        merged = dict(data)
        merged["key"] = data.get("key") or key
        image = normalize_image(merged)
        with self._lock:
            current = self._find_image(key)
            if current is None:
                raise StoreError(f"image '{key}' not found")
            if image["key"] != key and self._find_image(image["key"]) is not None:
                raise StoreError(f"image '{image['key']}' already exists")
            if image["key"] != key:
                self._rekey_image_refs(key, image["key"])
            current.clear()
            current.update(image)
            return dict(current)

    def delete_image(self, key: str) -> None:
        with self._lock:
            image = self._find_image(key)
            if image is None:
                raise StoreError(f"image '{key}' not found")
            users = [
                m["name"]
                for m in self._machines
                if m.get("disk_image") == key or m.get("cdrom_image") == key
            ]
            if users:
                raise StoreError(
                    f"image '{key}' is used by machine(s): {', '.join(sorted(users))}"
                )
            self._images.remove(image)

    # -- machine mutations (working copy only) --------------------------------

    def add_machine(self, data: dict) -> dict:
        with self._lock:
            machine = normalize_machine(data, image_keys=self._image_keys())
            if self._find_machine(machine["name"]) is not None:
                raise StoreError(f"machine '{machine['name']}' already exists")
            self._machines.append(machine)
            return dict(machine)

    def update_machine(self, name: str, data: dict) -> dict:
        merged = dict(data)
        merged["name"] = data.get("name") or name
        with self._lock:
            machine = normalize_machine(merged, image_keys=self._image_keys())
            current = self._find_machine(name)
            if current is None:
                raise StoreError(f"machine '{name}' not found")
            if machine["name"] != name and self._find_machine(machine["name"]) is not None:
                raise StoreError(f"machine '{machine['name']}' already exists")
            current.clear()
            current.update(machine)
            return dict(current)

    def delete_machine(self, name: str) -> None:
        with self._lock:
            machine = self._find_machine(name)
            if machine is None:
                raise StoreError(f"machine '{name}' not found")
            self._machines.remove(machine)

    # -- disk sync -------------------------------------------------------------

    def write(self) -> Path:
        with self._lock:
            path = write_proxmox_app_tfvars(self._images, self._machines, self._path)
            self._baseline_images = [dict(i) for i in self._images]
            self._baseline_machines = [dict(m) for m in self._machines]
            return path

    def reload(self) -> None:
        with self._lock:
            data = read_proxmox_app_tfvars(self._path) or {"images": [], "machines": []}
            self._images = [dict(i) for i in data["images"]]
            self._machines = [dict(m) for m in data["machines"]]
            self._baseline_images = [dict(i) for i in data["images"]]
            self._baseline_machines = [dict(m) for m in data["machines"]]

    # -- internals -------------------------------------------------------------

    def _image_keys(self) -> list[str]:
        return [image["key"] for image in self._images]

    def _find_image(self, key: str) -> dict | None:
        for image in self._images:
            if image["key"] == key:
                return image
        return None

    def _find_machine(self, name: str) -> dict | None:
        for machine in self._machines:
            if machine["name"] == name:
                return machine
        return None

    def _rekey_image_refs(self, old_key: str, new_key: str) -> None:
        for machine in self._machines:
            if machine.get("disk_image") == old_key:
                machine["disk_image"] = new_key
            if machine.get("cdrom_image") == old_key:
                machine["cdrom_image"] = new_key


__all__ = [
    "ProxmoxClusterStore",
    "StoreError",
    "ImageValidationError",
    "MachineValidationError",
]
