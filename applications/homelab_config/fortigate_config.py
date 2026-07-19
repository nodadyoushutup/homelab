"""FortiGate declarative-config helpers and read/write for
``.config/terraform/components/network/fortigate/config.tfvars``.

The file is the source of truth. It carries a single ``config`` object consumed
by the FortiGate config Terraform slice
(``terraform/components/network/fortigate/config``). This app models three
collections inside ``config``:

- ``virtual_ips``: static-NAT VIPs (port forwards), keyed by ``name``.
- ``firewall_policies``: firewall policies, keyed by ``policyid``.
- ``dhcp_server_reservations``: DHCP reservation groups, keyed by ``fosid``;
  each carries a ``reserved_address`` list of MAC/IP reservations.

This app does not talk to the FortiGate; it only records the desired config and
renders it to HCL. Provider login is separate (config-id
``terraform/providers/fortigate``) - it is NOT written here.
"""

from __future__ import annotations

import logging
from collections.abc import Iterable
from pathlib import Path

import hcl2

from homelab_config.hcl_util import atomic_write, coerce_bool, coerce_str, hcl_escape
from homelab_config.paths import FORTIGATE_CONFIG_TFVARS

logger = logging.getLogger(__name__)

_CONFIG_TAG = "# homelab-config: terraform/components/network/fortigate/config"
_HEADER = (
    f"{_CONFIG_TAG}\n"
    "# FortiGate declarative config (virtual IPs, firewall policies, DHCP\n"
    "# reservations), managed by the homelab-config web app\n"
    "# (applications/homelab_config).\n"
    "# Generated file: edit config in the UI (or by hand) then write it back.\n"
    "#\n"
    "# Consumed by the FortiGate config Terraform slice\n"
    "# (terraform/components/network/fortigate/config) as its slice -var-file.\n"
    "# Provider login is separate (config-id terraform/providers/fortigate).\n"
    "# This file lives under .config (git-ignored) - do not commit it.\n"
)

# Collection ids match the tfvars keys inside the `config` object.
COLLECTIONS = ("virtual_ips", "firewall_policies", "dhcp_server_reservations")

_VIP_STR_DEFAULTS = {
    "type": "static-nat",
    "extintf": "wan",
    "extip": "0.0.0.0",
    "protocol": "tcp",
    "status": "enable",
    "portforward": "enable",
}
_POLICY_STR_DEFAULTS = {
    "action": "accept",
    "status": "enable",
    "schedule": "always",
    "nat": "disable",
    "logtraffic": "all",
    "match_vip": "enable",
}
_POLICY_NAME_LISTS = ("srcintf", "dstintf", "srcaddr", "dstaddr", "service")


class ConfigValidationError(ValueError):
    """Raised when a FortiGate config payload fails validation."""


def _coerce_int(value: object) -> int | None:
    if value is None or value == "":
        return None
    if isinstance(value, bool):
        raise ValueError("expected an integer, got a boolean")
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    text = coerce_str(value).strip()
    if text == "":
        return None
    return int(text)


def _coerce_str_list(value: object) -> list[str]:
    """Coerce ranges / names into a list of plain strings.

    Accepts a comma-separated string, a list of strings, or a list of one-key
    dicts (``{"range": ...}`` / ``{"name": ...}``).
    """
    if value is None or value == "":
        return []
    if isinstance(value, str):
        parts = [coerce_str(part).strip() for part in value.split(",")]
        return [part for part in parts if part]
    if isinstance(value, (list, tuple)):
        out: list[str] = []
        for item in value:
            if isinstance(item, dict):
                inner = item.get("range")
                if inner is None:
                    inner = item.get("name")
                text = coerce_str(inner).strip()
            else:
                text = coerce_str(item).strip()
            if text:
                out.append(text)
        return out
    return [coerce_str(value).strip()]


# --- virtual IPs -----------------------------------------------------------


def normalize_virtual_ip(data: dict) -> dict:
    """Validate and normalize a raw virtual-IP payload into canonical shape."""
    name = coerce_str(data.get("name") or "").strip()
    if not name:
        raise ConfigValidationError("virtual IP name is required")

    record: dict = {"name": name}
    for field, default in _VIP_STR_DEFAULTS.items():
        record[field] = coerce_str(data.get(field, default)).strip() or default
    record["extport"] = coerce_str(data.get("extport", "")).strip()
    if not record["extport"]:
        raise ConfigValidationError("virtual IP extport is required")
    # mappedport defaults to extport when blank (common 1:1 forward).
    mappedport = coerce_str(data.get("mappedport", "")).strip()
    record["mappedport"] = mappedport or record["extport"]
    record["mappedip"] = _coerce_str_list(data.get("mappedip"))
    if not record["mappedip"]:
        raise ConfigValidationError("virtual IP needs at least one mapped IP")
    record["import_existing"] = coerce_bool(data.get("import_existing"), default=False)
    return record


# --- firewall policies -----------------------------------------------------


def normalize_firewall_policy(data: dict) -> dict:
    """Validate and normalize a raw firewall-policy payload into canonical shape."""
    try:
        policyid = _coerce_int(data.get("policyid"))
    except ValueError as exc:
        raise ConfigValidationError("policyid must be an integer") from exc
    if policyid is None:
        raise ConfigValidationError("policyid is required")

    name = coerce_str(data.get("name") or "").strip()
    if not name:
        raise ConfigValidationError("firewall policy name is required")

    record: dict = {"policyid": policyid, "name": name}
    for field, default in _POLICY_STR_DEFAULTS.items():
        record[field] = coerce_str(data.get(field, default)).strip() or default
    for field in _POLICY_NAME_LISTS:
        record[field] = _coerce_str_list(data.get(field))
    record["import_existing"] = coerce_bool(data.get("import_existing"), default=False)
    return record


# --- DHCP reservations -----------------------------------------------------


def _normalize_reserved_address(entry: dict) -> dict:
    try:
        rid = _coerce_int(entry.get("id"))
    except ValueError as exc:
        raise ConfigValidationError("reserved_address id must be an integer") from exc
    if rid is None:
        raise ConfigValidationError("reserved_address id is required")
    ip = coerce_str(entry.get("ip") or "").strip()
    mac = coerce_str(entry.get("mac") or "").strip()
    if not ip:
        raise ConfigValidationError("reserved_address ip is required")
    if not mac:
        raise ConfigValidationError("reserved_address mac is required")
    return {
        "id": rid,
        "type": coerce_str(entry.get("type", "mac")).strip() or "mac",
        "ip": ip,
        "mac": mac,
        "action": coerce_str(entry.get("action", "reserved")).strip() or "reserved",
        "description": coerce_str(entry.get("description") or "").strip(),
    }


def normalize_dhcp_reservation(data: dict) -> dict:
    """Validate and normalize a raw DHCP-reservation payload into canonical shape."""
    try:
        fosid = _coerce_int(data.get("fosid"))
    except ValueError as exc:
        raise ConfigValidationError("fosid must be an integer") from exc
    if fosid is None:
        raise ConfigValidationError("fosid is required")

    raw_addresses = data.get("reserved_address")
    addresses: list[dict] = []
    if isinstance(raw_addresses, (list, tuple)):
        for entry in raw_addresses:
            if isinstance(entry, dict):
                addresses.append(_normalize_reserved_address(entry))
    addresses.sort(key=lambda item: item["id"])
    return {
        "fosid": fosid,
        "method": coerce_str(data.get("method", "PUT")).strip() or "PUT",
        "reserved_address": addresses,
    }


_NORMALIZERS = {
    "virtual_ips": normalize_virtual_ip,
    "firewall_policies": normalize_firewall_policy,
    "dhcp_server_reservations": normalize_dhcp_reservation,
}
_KEY_FIELDS = {
    "virtual_ips": "name",
    "firewall_policies": "policyid",
    "dhcp_server_reservations": "fosid",
}


def normalize(collection: str, data: dict) -> dict:
    """Normalize a single entry for the named collection."""
    if collection not in _NORMALIZERS:
        raise ConfigValidationError(f"unknown collection '{collection}'")
    return _NORMALIZERS[collection](data)


def entry_key(collection: str, entry: dict) -> str:
    """Return the string key that identifies an entry within its collection."""
    return str(entry.get(_KEY_FIELDS[collection], ""))


def order_entries(collection: str, entries: Iterable[dict]) -> list[dict]:
    """Return entries sorted by their key field (numeric keys sort numerically)."""
    field = _KEY_FIELDS[collection]
    if field in ("policyid", "fosid"):
        return sorted(entries, key=lambda e: _coerce_int(e.get(field)) or 0)
    return sorted(entries, key=lambda e: str(e.get(field, "")))


# --- drift -----------------------------------------------------------------


def _vip_tuple(vip: dict) -> tuple:
    return (
        vip.get("name", ""),
        tuple(vip.get(field, "") for field in _VIP_STR_DEFAULTS),
        vip.get("extport", ""),
        vip.get("mappedport", ""),
        tuple(vip.get("mappedip", [])),
        bool(vip.get("import_existing")),
    )


def _policy_tuple(policy: dict) -> tuple:
    return (
        policy.get("policyid", 0),
        policy.get("name", ""),
        tuple(policy.get(field, "") for field in _POLICY_STR_DEFAULTS),
        tuple(tuple(policy.get(field, [])) for field in _POLICY_NAME_LISTS),
        bool(policy.get("import_existing")),
    )


def _reservation_tuple(res: dict) -> tuple:
    addresses = tuple(
        (a.get("id", 0), a.get("type", ""), a.get("ip", ""), a.get("mac", ""),
         a.get("action", ""), a.get("description", ""))
        for a in res.get("reserved_address", [])
    )
    return (res.get("fosid", 0), res.get("method", ""), addresses)


def canonical(config: dict) -> tuple:
    """Return an order-insensitive, hashable form for equality/drift checks."""
    vips = order_entries("virtual_ips", config.get("virtual_ips", []))
    policies = order_entries("firewall_policies", config.get("firewall_policies", []))
    reservations = order_entries(
        "dhcp_server_reservations", config.get("dhcp_server_reservations", [])
    )
    return (
        tuple(_vip_tuple(v) for v in vips),
        tuple(_policy_tuple(p) for p in policies),
        tuple(_reservation_tuple(r) for r in reservations),
    )


# --- rendering -------------------------------------------------------------


def _q(value: object) -> str:
    return f'"{hcl_escape(value)}"'


def _render_vip(vip: dict) -> str:
    lines = ["    {"]
    lines.append(f"      name        = {_q(vip['name'])}")
    lines.append(f"      type        = {_q(vip['type'])}")
    lines.append(f"      extintf     = {_q(vip['extintf'])}")
    lines.append(f"      extip       = {_q(vip['extip'])}")
    lines.append(f"      protocol    = {_q(vip['protocol'])}")
    lines.append(f"      extport     = {_q(vip['extport'])}")
    lines.append(f"      mappedport  = {_q(vip['mappedport'])}")
    lines.append(f"      status      = {_q(vip['status'])}")
    lines.append(f"      portforward = {_q(vip['portforward'])}")
    if vip.get("import_existing"):
        lines.append("      import_existing = true")
    mapped = ", ".join(f"{{ range = {_q(r)} }}" for r in vip["mappedip"])
    lines.append(f"      mappedip = [{mapped}]")
    lines.append("    },")
    return "\n".join(lines)


def _render_policy(policy: dict) -> str:
    lines = ["    {"]
    lines.append(f"      policyid   = {policy['policyid']}")
    lines.append(f"      name       = {_q(policy['name'])}")
    lines.append(f"      action     = {_q(policy['action'])}")
    lines.append(f"      status     = {_q(policy['status'])}")
    lines.append(f"      schedule   = {_q(policy['schedule'])}")
    lines.append(f"      nat        = {_q(policy['nat'])}")
    lines.append(f"      logtraffic = {_q(policy['logtraffic'])}")
    lines.append(f"      match_vip  = {_q(policy['match_vip'])}")
    if policy.get("import_existing"):
        lines.append("      import_existing = true")
    for field in _POLICY_NAME_LISTS:
        names = ", ".join(f"{{ name = {_q(n)} }}" for n in policy.get(field, []))
        lines.append(f"      {field} = [{names}]")
    lines.append("    },")
    return "\n".join(lines)


def _render_reservation(res: dict) -> str:
    lines = ["    {"]
    lines.append(f"      fosid  = {res['fosid']}")
    lines.append(f"      method = {_q(res['method'])}")
    lines.append("      reserved_address = [")
    for addr in res.get("reserved_address", []):
        lines.append(
            "        { "
            f"id = {addr['id']}, type = {_q(addr['type'])}, ip = {_q(addr['ip'])}, "
            f"mac = {_q(addr['mac'])}, action = {_q(addr['action'])}, "
            f"description = {_q(addr['description'])} }},"
        )
    lines.append("      ]")
    lines.append("    },")
    return "\n".join(lines)


def _render_list(name: str, entries: list[dict], renderer) -> str:
    if not entries:
        return f"  {name} = []\n"
    body = f"  {name} = [\n"
    body += "\n".join(renderer(entry) for entry in entries) + "\n"
    body += "  ]\n"
    return body


def render_config(config: dict) -> str:
    """Render the FortiGate config tfvars document (including the config-id header)."""
    vips = order_entries("virtual_ips", config.get("virtual_ips", []))
    policies = order_entries("firewall_policies", config.get("firewall_policies", []))
    reservations = order_entries(
        "dhcp_server_reservations", config.get("dhcp_server_reservations", [])
    )
    body = "config = {\n"
    body += _render_list("virtual_ips", vips, _render_vip)
    body += "\n"
    body += _render_list("firewall_policies", policies, _render_policy)
    body += "\n"
    body += _render_list(
        "dhcp_server_reservations", reservations, _render_reservation
    )
    body += "}\n"
    return f"{_HEADER}{body}"


# --- reading ---------------------------------------------------------------


def _read_collection(collection: str, raw: object) -> list[dict]:
    entries: list[dict] = []
    if not isinstance(raw, list):
        return entries
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        try:
            entries.append(normalize(collection, entry))
        except ConfigValidationError as exc:
            logger.warning("Skipping invalid FortiGate %s entry: %s", collection, exc)
    return entries


def read_fortigate_tfvars(path: Path = FORTIGATE_CONFIG_TFVARS) -> dict | None:
    """Parse the FortiGate config tfvars into the collections dict, or ``None``.

    Returns ``None`` when the file is missing/unparsable or has no ``config`` key.
    """
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse FortiGate config %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        return None
    raw_config = data.get("config")
    if not isinstance(raw_config, dict):
        return None
    return {
        collection: _read_collection(collection, raw_config.get(collection))
        for collection in COLLECTIONS
    }


def default_config() -> dict:
    """Return the empty config (all collections empty)."""
    return {collection: [] for collection in COLLECTIONS}


def write_fortigate_tfvars(config: dict, path: Path = FORTIGATE_CONFIG_TFVARS) -> Path:
    """Write the FortiGate config to ``path`` atomically and return it."""
    atomic_write(path, render_config(config))
    logger.info("Wrote FortiGate config to %s", path)
    return path


__all__ = [
    "COLLECTIONS",
    "ConfigValidationError",
    "canonical",
    "default_config",
    "entry_key",
    "normalize",
    "normalize_dhcp_reservation",
    "normalize_firewall_policy",
    "normalize_virtual_ip",
    "order_entries",
    "read_fortigate_tfvars",
    "render_config",
    "write_fortigate_tfvars",
]
