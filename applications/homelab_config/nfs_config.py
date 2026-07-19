"""NFS share catalog helpers and ``.config/terraform/nfs.tfvars`` read/write.

The file is the source of truth. A "share" is a plain dict describing an
*already-existing* NFS export that the homelab can mount. Keys:
``name``, ``server``, ``export``, ``mount_point``, ``options``.

- ``name``: catalog key (e.g. ``code``, ``media``); used as the ``nfs_shares``
  map key and to select a share from a Terraform slice (``nfs_share``).
- ``server``: NFS server address (e.g. ``192.168.1.100``).
- ``export``: server-side export path (e.g. ``/mnt/eapp/code``).
- ``mount_point``: the host-side mount point for reference (from fstab).
- ``options``: Docker-usable NFS mount options string (host/systemd-only flags
  such as ``_netdev``/``nofail``/``x-systemd.*`` are intentionally excluded).

The catalog renders to an HCL ``nfs_shares`` map so Terraform slices can consume
it via ``-var-file``. This app does not create or serve NFS; it only records
exports that already exist. The file lives under ``.config`` (git-ignored).
"""

from __future__ import annotations

import logging
import os
import tempfile
from collections.abc import Iterable
from pathlib import Path

import hcl2

from homelab_config.paths import NFS_TFVARS

logger = logging.getLogger(__name__)

_CONFIG_TAG = "# homelab-config: terraform/nfs"
_HEADER = (
    f"{_CONFIG_TAG}\n"
    "# Catalog of already-existing NFS exports, managed by the homelab-config\n"
    "# web app (applications/homelab_config).\n"
    "# Generated file: edit shares in the UI (or by hand) then write it back.\n"
    "#\n"
    "# Consumed by Terraform slices as a shared -var-file: a slice selects a\n"
    "# share by name (nfs_share) and composes its own Docker volume driver_opts.\n"
    "# 'options' holds Docker-usable NFS mount opts only (host/systemd-only flags\n"
    "# like _netdev/nofail/x-systemd.* are excluded).\n"
    "# This file lives under .config (git-ignored) - do not commit it.\n"
)

_FIELDS = ("name", "server", "export", "mount_point", "options")


class ShareValidationError(ValueError):
    """Raised when a share payload fails validation."""


def normalize_share(data: dict) -> dict:
    """Validate and normalize a raw share payload into the canonical shape.

    Args:
        data: Raw share mapping (from the API or a parsed tfvars entry).

    Returns:
        A normalized share dict with keys ``name``, ``server``, ``export``,
        ``mount_point``, ``options``.

    Raises:
        ShareValidationError: When required fields are missing or invalid.
    """
    name = str(data.get("name") or "").strip()
    if not name:
        raise ShareValidationError("name is required")
    # The name becomes an HCL map key / Terraform selector, so keep it simple.
    if not all(ch.isalnum() or ch in "_-" for ch in name):
        raise ShareValidationError(
            "name may only contain letters, digits, '-' and '_'"
        )

    server = str(data.get("server") or "").strip()
    if not server:
        raise ShareValidationError("server is required")

    export = str(data.get("export") or "").strip()
    if not export:
        raise ShareValidationError("export is required")
    if not export.startswith("/"):
        raise ShareValidationError("export must be an absolute path")

    # mount_point is informational (from fstab); default it to the export path.
    mount_point = str(data.get("mount_point") or "").strip() or export

    options = str(data.get("options") or "").strip()

    return {
        "name": name,
        "server": server,
        "export": export,
        "mount_point": mount_point,
        "options": options,
    }


def order_shares(shares: Iterable[dict]) -> list[dict]:
    """Return shares sorted alphabetically by name."""
    return sorted(shares, key=lambda share: share.get("name", ""))


def canonical(shares: Iterable[dict]) -> tuple:
    """Return an order-insensitive, hashable form for equality/drift checks."""
    return tuple(
        tuple(share.get(field, "") for field in _FIELDS)
        for share in order_shares(shares)
    )


def _hcl_escape(value: str) -> str:
    return str(value).replace("\\", "\\\\").replace('"', '\\"')


def _coerce_str(value: object) -> str:
    """Coerce a parsed tfvars value to a plain string.

    python-hcl2 (v8+) returns quoted literals with their surrounding double
    quotes preserved (e.g. ``'"192.168.1.100"'``); our catalog values are always
    plain quoted strings, so strip a single surrounding pair when present.
    """
    text = "" if value is None else str(value)
    if len(text) >= 2 and text[0] == '"' and text[-1] == '"':
        text = text[1:-1]
    return text


def _render_share_block(share: dict) -> str:
    return (
        f'  {share["name"]} = {{\n'
        f'    server      = "{_hcl_escape(share["server"])}"\n'
        f'    export      = "{_hcl_escape(share["export"])}"\n'
        f'    mount_point = "{_hcl_escape(share["mount_point"])}"\n'
        f'    options     = "{_hcl_escape(share["options"])}"\n'
        f"  }}\n"
    )


def render_shares(shares: Iterable[dict]) -> str:
    """Render the NFS catalog tfvars document (including the config-id header)."""
    ordered = order_shares(shares)
    body = "nfs_shares = {\n"
    body += "".join(_render_share_block(share) for share in ordered)
    body += "}\n"
    return f"{_HEADER}{body}"


def read_nfs_tfvars(path: Path = NFS_TFVARS) -> list[dict] | None:
    """Parse nfs.tfvars into normalized share dicts.

    Args:
        path: Source file; defaults to ``.config/terraform/nfs.tfvars``.

    Returns:
        A list of normalized share dicts (possibly empty when the file declares
        ``nfs_shares = {}``), or ``None`` when the file is missing, unparsable,
        or has no ``nfs_shares`` key. Malformed individual entries are skipped
        with a warning.
    """
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse NFS catalog %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        return None
    raw_shares = data.get("nfs_shares")
    if not isinstance(raw_shares, dict):
        return None

    shares: list[dict] = []
    for key, entry in raw_shares.items():
        if not isinstance(entry, dict):
            continue
        payload = {field: _coerce_str(value) for field, value in entry.items()}
        payload["name"] = _coerce_str(key)
        try:
            shares.append(normalize_share(payload))
        except ShareValidationError as exc:
            logger.warning("Skipping invalid NFS share in %s: %s", path, exc)
            continue
    return shares


def write_nfs_tfvars(shares: Iterable[dict], path: Path = NFS_TFVARS) -> Path:
    """Write the NFS catalog to ``path`` atomically and return it.

    Writes to a temp file in the same directory then ``os.replace``s it into
    place, so a concurrent reader (e.g. the drift watcher) never observes a
    partially written file and reports a spurious out-of-band change.
    """
    content = render_shares(shares)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        dir=str(path.parent), prefix=f".{path.name}.", suffix=".tmp"
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, path)
    except BaseException:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise
    logger.info("Wrote NFS catalog to %s", path)
    return path


__all__ = [
    "ShareValidationError",
    "canonical",
    "normalize_share",
    "order_shares",
    "read_nfs_tfvars",
    "render_shares",
    "write_nfs_tfvars",
]
