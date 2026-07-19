"""Proxmox cluster (images + machines) helpers and read/write for
``.config/terraform/components/cluster/proxmox/app.tfvars``.

The file is the source of truth. It carries two maps consumed by the Proxmox
cluster Terraform slice (``terraform/components/cluster/proxmox/app``):

- ``proxmox_images``: cloud images / ISOs to download onto Proxmox, keyed by an
  image key (e.g. ``ubuntu_24``). Each machine disk/cdrom references an image by
  this key.
- ``proxmox_machines``: VMs and their cloud-init snippets, keyed by machine name
  (e.g. ``k8s-wk-0``). Constant fields (bios, machine type, cpu type, efi disk,
  network bridge/model, ...) default in the slice ``locals.tf`` so the rendered
  tfvars stay readable.

This app does not talk to Proxmox; it only records the desired images/machines
and renders them to HCL. The file lives under ``.config`` (git-ignored) and is
NOT the provider credentials (those live in
``.config/terraform/providers/proxmox.tfvars``).
"""

from __future__ import annotations

import logging
from collections.abc import Iterable
from pathlib import Path

import hcl2

from homelab_config.hcl_util import atomic_write, coerce_bool, coerce_str, hcl_escape
from homelab_config.paths import PROXMOX_APP_TFVARS

logger = logging.getLogger(__name__)

_CONFIG_TAG = "# homelab-config: terraform/components/cluster/proxmox/app"
_HEADER = (
    f"{_CONFIG_TAG}\n"
    "# Proxmox cloud images and VMs (machines), managed by the homelab-config\n"
    "# web app (applications/homelab_config).\n"
    "# Generated file: edit images/machines in the UI (or by hand) then write it back.\n"
    "#\n"
    "# Consumed by the Proxmox cluster Terraform slice\n"
    "# (terraform/components/cluster/proxmox/app) as its slice -var-file. Provider\n"
    "# login credentials are separate (config-id terraform/providers/proxmox).\n"
    "# This file lives under .config (git-ignored) - do not commit it.\n"
)

# --- image model -----------------------------------------------------------
_IMAGE_STR_FIELDS = ("node_name", "datastore_id", "content_type", "file_name", "url")
_IMAGE_BOOL_FIELDS = ("verify", "overwrite", "overwrite_unmanaged")
_IMAGE_INT_FIELDS = ("upload_timeout",)
_IMAGE_FIELDS = ("key",) + _IMAGE_STR_FIELDS + _IMAGE_BOOL_FIELDS + _IMAGE_INT_FIELDS

_IMAGE_STR_DEFAULTS = {
    "node_name": "pve",
    "datastore_id": "local",
    "content_type": "iso",
}
_IMAGE_BOOL_DEFAULTS = {"verify": False, "overwrite": True, "overwrite_unmanaged": True}
_IMAGE_INT_DEFAULTS = {"upload_timeout": 1800}

# --- machine model ---------------------------------------------------------
_MACHINE_STR_DEFAULTS = {
    "node_name": "pve",
    "bios": "ovmf",
    "machine": "q35",
    "os_type": "l26",
    "cpu_type": "host",
    "efi_datastore_id": "local-lvm",
    "efi_type": "4m",
    "disk_datastore_id": "virtualization",
    "disk_interface": "scsi0",
    "init_datastore_id": "local-lvm",
    "init_interface": "ide2",
    "net_bridge": "vmbr0",
    "net_model": "virtio",
}
_MACHINE_BOOL_DEFAULTS = {"started": True, "on_boot": True, "efi_pre_enrolled_keys": False}
_MACHINE_INT_DEFAULTS = {"cores": 2}
# Fields with no default (required or optional-with-empty).
_MACHINE_REQUIRED_INT = ("vm_id", "memory", "disk_size")
_MACHINE_REQUIRED_STR = ("net_mac_address", "user_config_path", "network_config_path")
_MACHINE_OPTIONAL_STR = ("disk_image", "cdrom_interface", "cdrom_image")
_MACHINE_LIST_FIELDS = ("tags", "boot_order")

# Canonical field order for drift comparison (must be stable/hashable).
_MACHINE_FIELDS = (
    ("name",)
    + tuple(_MACHINE_STR_DEFAULTS)
    + tuple(_MACHINE_BOOL_DEFAULTS)
    + tuple(_MACHINE_INT_DEFAULTS)
    + _MACHINE_REQUIRED_INT
    + _MACHINE_REQUIRED_STR
    + _MACHINE_OPTIONAL_STR
    + _MACHINE_LIST_FIELDS
)


class ImageValidationError(ValueError):
    """Raised when an image payload fails validation."""


class MachineValidationError(ValueError):
    """Raised when a machine payload fails validation."""


def _valid_key(value: str) -> bool:
    return bool(value) and all(ch.isalnum() or ch in "_-" for ch in value)


def _coerce_int(value: object, *, default: int | None = None) -> int | None:
    if value is None or value == "":
        return default
    if isinstance(value, bool):
        raise ValueError("expected an integer, got a boolean")
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    text = coerce_str(value).strip()
    if text == "":
        return default
    return int(text)


def _coerce_str_list(value: object) -> list[str]:
    if value is None or value == "":
        return []
    if isinstance(value, str):
        parts = [part.strip() for part in value.split(",")]
        return [coerce_str(part) for part in parts if part.strip()]
    if isinstance(value, (list, tuple)):
        out: list[str] = []
        for item in value:
            text = coerce_str(item).strip()
            if text:
                out.append(text)
        return out
    return [coerce_str(value)]


# --- images ----------------------------------------------------------------


def normalize_image(data: dict) -> dict:
    """Validate and normalize a raw image payload into canonical shape."""
    key = coerce_str(data.get("key") or data.get("name") or "").strip()
    if not key:
        raise ImageValidationError("image key is required")
    if not _valid_key(key):
        raise ImageValidationError(
            "image key may only contain letters, digits, '-' and '_'"
        )

    record: dict = {"key": key}
    for field in _IMAGE_STR_FIELDS:
        default = _IMAGE_STR_DEFAULTS.get(field, "")
        record[field] = coerce_str(data.get(field, default)).strip() or default
    if not record["file_name"]:
        raise ImageValidationError("file_name is required")
    if not record["url"]:
        raise ImageValidationError("url is required")
    for field in _IMAGE_BOOL_FIELDS:
        record[field] = coerce_bool(
            data.get(field, _IMAGE_BOOL_DEFAULTS[field]),
            default=_IMAGE_BOOL_DEFAULTS[field],
        )
    for field in _IMAGE_INT_FIELDS:
        try:
            record[field] = _coerce_int(
                data.get(field, _IMAGE_INT_DEFAULTS[field]),
                default=_IMAGE_INT_DEFAULTS[field],
            )
        except ValueError as exc:
            raise ImageValidationError(f"{field} must be an integer") from exc
    return record


def order_images(images: Iterable[dict]) -> list[dict]:
    """Return images sorted alphabetically by key."""
    return sorted(images, key=lambda image: image.get("key", ""))


# --- machines --------------------------------------------------------------


def normalize_machine(data: dict, *, image_keys: Iterable[str] | None = None) -> dict:
    """Validate and normalize a raw machine payload into canonical shape.

    Args:
        data: Raw machine mapping (from the API or a parsed tfvars entry).
        image_keys: When provided, ``disk_image``/``cdrom_image`` must reference
            one of these image keys.

    Raises:
        MachineValidationError: When required fields are missing or invalid.
    """
    name = coerce_str(data.get("name") or data.get("key") or "").strip()
    if not name:
        raise MachineValidationError("machine name is required")
    if not _valid_key(name):
        raise MachineValidationError(
            "machine name may only contain letters, digits, '-' and '_'"
        )

    record: dict = {"name": name}
    for field, default in _MACHINE_STR_DEFAULTS.items():
        record[field] = coerce_str(data.get(field, default)).strip() or default
    for field, default in _MACHINE_BOOL_DEFAULTS.items():
        record[field] = coerce_bool(data.get(field, default), default=default)
    for field, default in _MACHINE_INT_DEFAULTS.items():
        try:
            record[field] = _coerce_int(data.get(field, default), default=default)
        except ValueError as exc:
            raise MachineValidationError(f"{field} must be an integer") from exc

    for field in _MACHINE_REQUIRED_INT:
        try:
            value = _coerce_int(data.get(field))
        except ValueError as exc:
            raise MachineValidationError(f"{field} must be an integer") from exc
        if value is None:
            raise MachineValidationError(f"{field} is required")
        record[field] = value

    for field in _MACHINE_REQUIRED_STR:
        value = coerce_str(data.get(field, "")).strip()
        if not value:
            raise MachineValidationError(f"{field} is required")
        record[field] = value

    for field in _MACHINE_OPTIONAL_STR:
        record[field] = coerce_str(data.get(field, "")).strip()

    for field in _MACHINE_LIST_FIELDS:
        record[field] = _coerce_str_list(data.get(field))

    # cdrom is all-or-nothing: an image needs an interface and vice versa.
    if record["cdrom_image"] and not record["cdrom_interface"]:
        raise MachineValidationError("cdrom_interface is required when cdrom_image is set")
    if record["cdrom_interface"] and not record["cdrom_image"]:
        raise MachineValidationError("cdrom_image is required when cdrom_interface is set")

    if image_keys is not None:
        known = set(image_keys)
        for field in ("disk_image", "cdrom_image"):
            ref = record[field]
            if ref and ref not in known:
                raise MachineValidationError(
                    f"{field} '{ref}' does not match any defined image"
                )

    return record


def order_machines(machines: Iterable[dict]) -> list[dict]:
    """Return machines sorted alphabetically by name."""
    return sorted(machines, key=lambda machine: machine.get("name", ""))


# --- drift -----------------------------------------------------------------


def _image_tuple(image: dict) -> tuple:
    return tuple(image.get(field, "") for field in _IMAGE_FIELDS)


def _machine_tuple(machine: dict) -> tuple:
    out: list[object] = []
    for field in _MACHINE_FIELDS:
        value = machine.get(field, "")
        if isinstance(value, list):
            value = tuple(value)
        out.append(value)
    return tuple(out)


def canonical(images: Iterable[dict], machines: Iterable[dict]) -> tuple:
    """Return an order-insensitive, hashable form for equality/drift checks."""
    return (
        tuple(_image_tuple(image) for image in order_images(images)),
        tuple(_machine_tuple(machine) for machine in order_machines(machines)),
    )


# --- rendering -------------------------------------------------------------


def _q(value: object) -> str:
    return f'"{hcl_escape(value)}"'


def _bool(value: object) -> str:
    return "true" if value else "false"


def _list(values: Iterable[str]) -> str:
    return "[" + ", ".join(_q(v) for v in values) + "]"


def _render_image_block(image: dict) -> str:
    return (
        f"  {_q(image['key'])} = {{\n"
        f"    node_name           = {_q(image['node_name'])}\n"
        f"    datastore_id        = {_q(image['datastore_id'])}\n"
        f"    content_type        = {_q(image['content_type'])}\n"
        f"    file_name           = {_q(image['file_name'])}\n"
        f"    url                 = {_q(image['url'])}\n"
        f"    verify              = {_bool(image['verify'])}\n"
        f"    overwrite           = {_bool(image['overwrite'])}\n"
        f"    overwrite_unmanaged = {_bool(image['overwrite_unmanaged'])}\n"
        f"    upload_timeout      = {image['upload_timeout']}\n"
        f"  }}\n"
    )


def _render_machine_block(machine: dict) -> str:
    lines = [f"  {_q(machine['name'])} = {{"]
    lines.append(f"    vm_id     = {machine['vm_id']}")
    lines.append(f"    node_name = {_q(machine['node_name'])}")
    lines.append(f"    bios      = {_q(machine['bios'])}")
    lines.append(f"    machine   = {_q(machine['machine'])}")
    lines.append(f"    started   = {_bool(machine['started'])}")
    lines.append(f"    on_boot   = {_bool(machine['on_boot'])}")
    lines.append(f"    os_type   = {_q(machine['os_type'])}")
    lines.append(f"    cores     = {machine['cores']}")
    lines.append(f"    cpu_type  = {_q(machine['cpu_type'])}")
    lines.append(f"    memory    = {machine['memory']}")
    lines.append(f"    tags      = {_list(machine['tags'])}")
    if machine["boot_order"]:
        lines.append(f"    boot_order = {_list(machine['boot_order'])}")
    lines.append("")
    lines.append("    efi = {")
    lines.append(f"      datastore_id      = {_q(machine['efi_datastore_id'])}")
    lines.append(f"      type              = {_q(machine['efi_type'])}")
    lines.append(f"      pre_enrolled_keys = {_bool(machine['efi_pre_enrolled_keys'])}")
    lines.append("    }")
    lines.append("")
    lines.append("    disk = {")
    lines.append(f"      datastore_id = {_q(machine['disk_datastore_id'])}")
    lines.append(f"      interface    = {_q(machine['disk_interface'])}")
    lines.append(f"      size         = {machine['disk_size']}")
    if machine["disk_image"]:
        lines.append(f"      image        = {_q(machine['disk_image'])}")
    lines.append("    }")
    if machine["cdrom_image"]:
        lines.append("")
        lines.append("    cdrom = {")
        lines.append(f"      interface = {_q(machine['cdrom_interface'])}")
        lines.append(f"      image     = {_q(machine['cdrom_image'])}")
        lines.append("    }")
    lines.append("")
    lines.append("    initialization = {")
    lines.append(f"      datastore_id        = {_q(machine['init_datastore_id'])}")
    lines.append(f"      interface           = {_q(machine['init_interface'])}")
    lines.append(f"      user_config_path    = {_q(machine['user_config_path'])}")
    lines.append(f"      network_config_path = {_q(machine['network_config_path'])}")
    lines.append("    }")
    lines.append("")
    lines.append("    network = {")
    lines.append(f"      bridge      = {_q(machine['net_bridge'])}")
    lines.append(f"      model       = {_q(machine['net_model'])}")
    lines.append(f"      mac_address = {_q(machine['net_mac_address'])}")
    lines.append("    }")
    lines.append("  }")
    return "\n".join(lines) + "\n"


def render_config(images: Iterable[dict], machines: Iterable[dict]) -> str:
    """Render the Proxmox cluster tfvars document (including the config-id header)."""
    ordered_images = order_images(images)
    ordered_machines = order_machines(machines)
    body = "proxmox_images = {\n"
    body += "".join(_render_image_block(image) for image in ordered_images)
    body += "}\n\n"
    body += "proxmox_machines = {\n"
    body += "\n".join(_render_machine_block(m) for m in ordered_machines)
    if ordered_machines:
        body += "\n"
    body += "}\n"
    return f"{_HEADER}{body}"


# --- reading ---------------------------------------------------------------


def _read_images(raw: object) -> list[dict]:
    images: list[dict] = []
    if not isinstance(raw, dict):
        return images
    for key, entry in raw.items():
        if not isinstance(entry, dict):
            continue
        payload = {field: entry.get(field) for field in entry}
        payload["key"] = coerce_str(key)
        try:
            images.append(normalize_image(payload))
        except ImageValidationError as exc:
            logger.warning("Skipping invalid Proxmox image '%s': %s", key, exc)
    return images


def _read_machines(raw: object) -> list[dict]:
    machines: list[dict] = []
    if not isinstance(raw, dict):
        return machines
    for key, entry in raw.items():
        if not isinstance(entry, dict):
            continue
        efi = entry.get("efi") if isinstance(entry.get("efi"), dict) else {}
        disk = entry.get("disk") if isinstance(entry.get("disk"), dict) else {}
        cdrom = entry.get("cdrom") if isinstance(entry.get("cdrom"), dict) else {}
        init = (
            entry.get("initialization")
            if isinstance(entry.get("initialization"), dict)
            else {}
        )
        net = entry.get("network") if isinstance(entry.get("network"), dict) else {}
        payload = {
            "name": coerce_str(key),
            "vm_id": entry.get("vm_id"),
            "node_name": entry.get("node_name"),
            "bios": entry.get("bios"),
            "machine": entry.get("machine"),
            "started": entry.get("started"),
            "on_boot": entry.get("on_boot"),
            "os_type": entry.get("os_type"),
            "cores": entry.get("cores"),
            "cpu_type": entry.get("cpu_type"),
            "memory": entry.get("memory"),
            "tags": entry.get("tags"),
            "boot_order": entry.get("boot_order"),
            "efi_datastore_id": efi.get("datastore_id"),
            "efi_type": efi.get("type"),
            "efi_pre_enrolled_keys": efi.get("pre_enrolled_keys"),
            "disk_datastore_id": disk.get("datastore_id"),
            "disk_interface": disk.get("interface"),
            "disk_size": disk.get("size"),
            "disk_image": disk.get("image"),
            "cdrom_interface": cdrom.get("interface"),
            "cdrom_image": cdrom.get("image"),
            "init_datastore_id": init.get("datastore_id"),
            "init_interface": init.get("interface"),
            "user_config_path": init.get("user_config_path"),
            "network_config_path": init.get("network_config_path"),
            "net_bridge": net.get("bridge"),
            "net_model": net.get("model"),
            "net_mac_address": net.get("mac_address"),
        }
        # Drop None so per-field defaults apply during normalization.
        payload = {k: v for k, v in payload.items() if v is not None}
        try:
            machines.append(normalize_machine(payload))
        except MachineValidationError as exc:
            logger.warning("Skipping invalid Proxmox machine '%s': %s", key, exc)
    return machines


def read_proxmox_app_tfvars(path: Path = PROXMOX_APP_TFVARS) -> dict | None:
    """Parse the Proxmox cluster tfvars into ``{"images": [...], "machines": [...]}``.

    Returns ``None`` when the file is missing or unparsable, or when it has
    neither a ``proxmox_images`` nor a ``proxmox_machines`` key.
    """
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse Proxmox cluster config %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        return None
    if "proxmox_images" not in data and "proxmox_machines" not in data:
        return None
    return {
        "images": _read_images(data.get("proxmox_images")),
        "machines": _read_machines(data.get("proxmox_machines")),
    }


def write_proxmox_app_tfvars(
    images: Iterable[dict],
    machines: Iterable[dict],
    path: Path = PROXMOX_APP_TFVARS,
) -> Path:
    """Write the Proxmox cluster config to ``path`` atomically and return it."""
    atomic_write(path, render_config(images, machines))
    logger.info("Wrote Proxmox cluster config to %s", path)
    return path


__all__ = [
    "ImageValidationError",
    "MachineValidationError",
    "canonical",
    "normalize_image",
    "normalize_machine",
    "order_images",
    "order_machines",
    "read_proxmox_app_tfvars",
    "render_config",
    "write_proxmox_app_tfvars",
]
