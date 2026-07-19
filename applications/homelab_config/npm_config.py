"""Nginx Proxy Manager desired-state helpers and read/write for
``.config/terraform/components/swarm/nginx_proxy_manager/config.tfvars``.

The file is the source of truth. It carries the variables consumed by the NPM
config Terraform slice (``terraform/components/swarm/nginx_proxy_manager/config``):

- ``default``: fallback Let's Encrypt email + DNS-challenge settings.
- ``certificates``: Let's Encrypt certs keyed by name (referenced by hosts).
- ``proxy_hosts``: HTTP(S) reverse-proxy hosts keyed by name.
- ``redirections``: HTTP redirection hosts keyed by name.
- ``streams``: TCP/UDP stream forwards keyed by name.
- ``access_lists``: access-list definitions keyed by name.

This app does not talk to NPM; it only records the desired config and renders it
to HCL. Provider login is separate (config-id
``terraform/providers/nginx_proxy_manager``) - it is NOT written here.
"""

from __future__ import annotations

import json
import logging
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path

import hcl2

from homelab_config.hcl_util import atomic_write, coerce_bool, coerce_str, hcl_escape
from homelab_config.paths import NPM_CONFIG_TFVARS

logger = logging.getLogger(__name__)

_CONFIG_TAG = "# homelab-config: terraform/components/swarm/nginx_proxy_manager/config"
_HEADER = (
    f"{_CONFIG_TAG}\n"
    "# Nginx Proxy Manager config (certificates, proxy hosts, redirections,\n"
    "# streams, access lists), managed by the homelab-config web app\n"
    "# (applications/homelab_config).\n"
    "# Generated file: edit config in the UI (or by hand) then write it back.\n"
    "#\n"
    "# Consumed by the NPM config Terraform slice\n"
    "# (terraform/components/swarm/nginx_proxy_manager/config) as its slice\n"
    "# -var-file. Provider login is separate (config-id\n"
    "# terraform/providers/nginx_proxy_manager).\n"
    "# This file lives under .config (git-ignored) - do not commit it.\n"
)

COLLECTIONS = ("certificates", "proxy_hosts", "redirections", "streams", "access_lists")


class ConfigValidationError(ValueError):
    """Raised when an NPM config payload fails validation."""


# --- field specs for the "flat" collections --------------------------------


@dataclass(frozen=True)
class Field:
    """One field on a flat collection entry.

    ``kind``: ``str`` | ``int`` | ``bool`` | ``domains`` | ``ref``.
    ``ref`` and empty-string ``str`` are omitted from the render when blank.
    ``bool`` fields render always (effective/defaulted value) so the file is
    explicit and deterministic.
    """

    name: str
    kind: str = "str"
    default: object = None
    required: bool = False
    aliases: tuple[str, ...] = ()


_CERT_FIELDS: tuple[Field, ...] = (
    Field("domain_names", "domains", required=True),
    Field("letsencrypt_email", "ref"),
    Field("letsencrypt_agree", "bool", default=True),
)
_PROXY_FIELDS: tuple[Field, ...] = (
    Field("domain_names", "domains", required=True),
    Field("forward_scheme", "str", default="http", aliases=("scheme",)),
    Field("forward_host", "str", required=True),
    Field("forward_port", "int", required=True),
    Field("certificate", "ref"),
    Field("access_list", "ref"),
    Field("enabled", "bool", default=True),
    Field("block_exploits", "bool", default=True),
    Field("caching_enabled", "bool", default=False),
    Field("allow_websocket_upgrade", "bool", default=True),
    Field("http2_support", "bool", default=True),
    Field("ssl_forced", "bool", default=True),
    Field("hsts_enabled", "bool", default=False),
    Field("hsts_subdomains", "bool", default=False),
)
_REDIRECTION_FIELDS: tuple[Field, ...] = (
    Field("domain_names", "domains", required=True),
    Field("forward_domain_name", "str", required=True, aliases=("domain_name",)),
    Field("forward_scheme", "str", default="auto"),
    Field("forward_http_code", "int", default=301),
    Field("preserve_path", "bool", default=True),
    Field("certificate", "ref"),
    Field("enabled", "bool", default=True),
    Field("block_exploits", "bool", default=True),
    Field("http2_support", "bool", default=True),
    Field("ssl_forced", "bool", default=True),
    Field("hsts_enabled", "bool", default=False),
    Field("hsts_subdomains", "bool", default=False),
)
_STREAM_FIELDS: tuple[Field, ...] = (
    Field("incoming_port", "int", required=True),
    Field("forwarding_host", "str", required=True),
    Field("forwarding_port", "int", required=True),
    Field("certificate", "ref"),
    Field("tcp_forwarding", "bool", default=True),
    Field("udp_forwarding", "bool", default=False),
    Field("enabled", "bool", default=True),
)

_FLAT_FIELDS = {
    "certificates": _CERT_FIELDS,
    "proxy_hosts": _PROXY_FIELDS,
    "redirections": _REDIRECTION_FIELDS,
    "streams": _STREAM_FIELDS,
}


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


def _coerce_domains(value: object) -> list[str]:
    if value is None or value == "":
        return []
    if isinstance(value, str):
        parts = [coerce_str(p).strip() for p in value.replace("\n", ",").split(",")]
        return [p for p in parts if p]
    if isinstance(value, (list, tuple)):
        out: list[str] = []
        for item in value:
            text = coerce_str(item).strip()
            if text:
                out.append(text)
        return out
    return [coerce_str(value).strip()]


def _valid_name(value: str) -> bool:
    return bool(value) and all(ch.isalnum() or ch in "_-" for ch in value)


def _normalize_flat(collection: str, data: dict) -> dict:
    fields = _FLAT_FIELDS[collection]
    name = coerce_str(data.get("name") or data.get("key") or "").strip()
    if not name:
        raise ConfigValidationError(f"{collection} name is required")
    if not _valid_name(name):
        raise ConfigValidationError(
            f"{collection} name may only contain letters, digits, '-' and '_'"
        )
    record: dict = {"name": name}
    for field in fields:
        raw = data.get(field.name)
        if raw is None or raw == "":
            for alias in field.aliases:
                if data.get(alias) not in (None, ""):
                    raw = data.get(alias)
                    break
        if field.kind == "domains":
            record[field.name] = _coerce_domains(raw)
            if field.required and not record[field.name]:
                raise ConfigValidationError(f"{collection} {field.name} is required")
        elif field.kind == "bool":
            record[field.name] = coerce_bool(raw, default=bool(field.default))
        elif field.kind == "int":
            try:
                value = _coerce_int(raw, default=field.default)
            except ValueError as exc:
                raise ConfigValidationError(
                    f"{collection} {field.name} must be an integer"
                ) from exc
            if field.required and value is None:
                raise ConfigValidationError(f"{collection} {field.name} is required")
            record[field.name] = value
        else:  # str / ref
            text = coerce_str(raw).strip()
            if field.required and not text:
                raise ConfigValidationError(f"{collection} {field.name} is required")
            record[field.name] = text or (field.default or "")
    return record


# --- per-collection normalize (adds nested pieces) -------------------------


def _normalize_dns_challenge(raw: object) -> dict | None:
    if not isinstance(raw, dict):
        return None
    enabled = coerce_bool(raw.get("enabled"), default=False)
    provider = coerce_str(raw.get("provider")).strip()
    credentials = coerce_str(raw.get("credentials")).strip()
    try:
        prop = _coerce_int(raw.get("propagation_seconds"))
    except ValueError:
        prop = None
    if not enabled and not provider and not credentials and prop is None:
        return None
    dns: dict = {"enabled": enabled}
    if provider:
        dns["provider"] = provider
    if credentials:
        dns["credentials"] = credentials
    if prop is not None:
        dns["propagation_seconds"] = prop
    return dns


def normalize_certificate(data: dict) -> dict:
    record = _normalize_flat("certificates", data)
    dns = _normalize_dns_challenge(data.get("dns_challenge"))
    if dns is not None:
        record["dns_challenge"] = dns
    return record


def _normalize_location(entry: dict) -> dict:
    path = coerce_str(entry.get("path") or "").strip()
    host = coerce_str(entry.get("forward_host") or "").strip()
    if not path:
        raise ConfigValidationError("location path is required")
    if not host:
        raise ConfigValidationError("location forward_host is required")
    try:
        port = _coerce_int(entry.get("forward_port"))
    except ValueError as exc:
        raise ConfigValidationError("location forward_port must be an integer") from exc
    if port is None:
        raise ConfigValidationError("location forward_port is required")
    scheme = (
        coerce_str(entry.get("forward_scheme") or entry.get("scheme") or "").strip()
        or "http"
    )
    return {
        "path": path,
        "forward_scheme": scheme,
        "forward_host": host,
        "forward_port": port,
    }


def normalize_proxy_host(data: dict) -> dict:
    record = _normalize_flat("proxy_hosts", data)
    raw_locations = data.get("locations")
    locations: list[dict] = []
    if isinstance(raw_locations, (list, tuple)):
        for entry in raw_locations:
            if isinstance(entry, dict):
                locations.append(_normalize_location(entry))
    if locations:
        record["locations"] = locations
    return record


def normalize_redirection(data: dict) -> dict:
    return _normalize_flat("redirections", data)


def normalize_stream(data: dict) -> dict:
    return _normalize_flat("streams", data)


def _normalize_authorization(entry: dict) -> dict:
    username = coerce_str(entry.get("username") or "").strip()
    if not username:
        raise ConfigValidationError("authorization username is required")
    return {"username": username, "password": coerce_str(entry.get("password") or "")}


def _normalize_access_rule(entry: dict) -> dict:
    directive = coerce_str(entry.get("directive") or "").strip()
    address = coerce_str(entry.get("address") or "").strip()
    if directive not in ("allow", "deny"):
        raise ConfigValidationError("access directive must be 'allow' or 'deny'")
    if not address:
        raise ConfigValidationError("access address is required")
    return {"directive": directive, "address": address}


def normalize_access_list(data: dict) -> dict:
    name = coerce_str(data.get("name") or data.get("key") or "").strip()
    if not name:
        raise ConfigValidationError("access_lists name is required")
    if not _valid_name(name):
        raise ConfigValidationError(
            "access_lists name may only contain letters, digits, '-' and '_'"
        )
    record: dict = {"name": name}
    if coerce_bool(data.get("satisfy_any"), default=False):
        record["satisfy_any"] = True
    if coerce_bool(data.get("pass_auth"), default=False):
        record["pass_auth"] = True
    authorizations: list[dict] = []
    raw_auth = data.get("authorizations")
    if isinstance(raw_auth, (list, tuple)):
        for entry in raw_auth:
            if isinstance(entry, dict):
                authorizations.append(_normalize_authorization(entry))
    if authorizations:
        record["authorizations"] = authorizations
    access: list[dict] = []
    raw_access = data.get("access")
    if isinstance(raw_access, (list, tuple)):
        for entry in raw_access:
            if isinstance(entry, dict):
                access.append(_normalize_access_rule(entry))
    if access:
        record["access"] = access
    return record


_NORMALIZERS = {
    "certificates": normalize_certificate,
    "proxy_hosts": normalize_proxy_host,
    "redirections": normalize_redirection,
    "streams": normalize_stream,
    "access_lists": normalize_access_list,
}


def normalize(collection: str, data: dict) -> dict:
    """Normalize a single entry for the named collection."""
    if collection not in _NORMALIZERS:
        raise ConfigValidationError(f"unknown collection '{collection}'")
    return _NORMALIZERS[collection](data)


def normalize_default(data: dict) -> dict:
    """Normalize the ``default`` object (email + DNS-challenge settings)."""
    record: dict = {}
    email = coerce_str((data or {}).get("certificate_email") or "").strip()
    if email:
        record["certificate_email"] = email
    dns = _normalize_dns_challenge((data or {}).get("dns_challenge"))
    if dns is not None:
        record["dns_challenge"] = dns
    return record


def entry_key(entry: dict) -> str:
    """Return the string key (name) that identifies an entry."""
    return str(entry.get("name", ""))


def order_entries(entries: Iterable[dict]) -> list[dict]:
    """Return entries sorted alphabetically by name."""
    return sorted(entries, key=lambda e: str(e.get("name", "")))


def default_config() -> dict:
    """Return the empty config (empty default + empty collections)."""
    config: dict = {"default": {}}
    for collection in COLLECTIONS:
        config[collection] = []
    return config


# --- drift -----------------------------------------------------------------


def canonical(config: dict) -> str:
    """Return an order-insensitive JSON string for equality/drift checks."""
    comparable: dict = {"default": config.get("default", {})}
    for collection in COLLECTIONS:
        comparable[collection] = {
            entry_key(e): {k: v for k, v in e.items() if k != "name"}
            for e in config.get(collection, [])
        }
    return json.dumps(comparable, sort_keys=True, default=str)


# --- rendering -------------------------------------------------------------


def _q(value: object) -> str:
    return f'"{hcl_escape(value)}"'


def _bool(value: object) -> str:
    return "true" if value else "false"


def _domains_lines(domains: list[str], indent: str) -> list[str]:
    lines = [f"{indent}domain_names = ["]
    for domain in domains:
        lines.append(f"{indent}  {_q(domain)},")
    lines.append(f"{indent}]")
    return lines


def _render_flat_fields(collection: str, entry: dict, indent: str) -> list[str]:
    lines: list[str] = []
    for field in _FLAT_FIELDS[collection]:
        value = entry.get(field.name)
        if field.kind == "domains":
            lines.extend(_domains_lines(value or [], indent))
        elif field.kind == "bool":
            lines.append(f"{indent}{field.name} = {_bool(value)}")
        elif field.kind == "int":
            if value is None:
                continue
            lines.append(f"{indent}{field.name} = {int(value)}")
        elif field.kind == "ref":
            if value:
                lines.append(f"{indent}{field.name} = {_q(value)}")
        else:  # str
            if value != "":
                lines.append(f"{indent}{field.name} = {_q(value)}")
    return lines


def _render_dns_challenge(dns: dict, indent: str) -> list[str]:
    lines = [f"{indent}dns_challenge = {{"]
    lines.append(f"{indent}  enabled = {_bool(dns.get('enabled'))}")
    if dns.get("provider"):
        lines.append(f"{indent}  provider = {_q(dns['provider'])}")
    if dns.get("credentials"):
        lines.append(f"{indent}  credentials = {_q(dns['credentials'])}")
    if dns.get("propagation_seconds") is not None:
        lines.append(
            f"{indent}  propagation_seconds = {int(dns['propagation_seconds'])}"
        )
    lines.append(f"{indent}}}")
    return lines


def _render_map(name: str, entries: list[dict], render_entry) -> str:
    if not entries:
        return f"{name} = {{}}\n"
    body = f"{name} = {{\n"
    for entry in order_entries(entries):
        body += f'  {_q(entry["name"])} = {{\n'
        body += "\n".join(render_entry(entry)) + "\n"
        body += "  }\n"
    body += "}\n"
    return body


def _render_certificate(cert: dict) -> list[str]:
    lines = _render_flat_fields("certificates", cert, "    ")
    if isinstance(cert.get("dns_challenge"), dict):
        lines.extend(_render_dns_challenge(cert["dns_challenge"], "    "))
    return lines


def _render_proxy_host(host: dict) -> list[str]:
    lines = _render_flat_fields("proxy_hosts", host, "    ")
    locations = host.get("locations")
    if isinstance(locations, list) and locations:
        lines.append("    locations = [")
        for loc in locations:
            lines.append("      {")
            lines.append(f"        path = {_q(loc['path'])}")
            lines.append(f"        forward_scheme = {_q(loc['forward_scheme'])}")
            lines.append(f"        forward_host = {_q(loc['forward_host'])}")
            lines.append(f"        forward_port = {int(loc['forward_port'])}")
            lines.append("      },")
        lines.append("    ]")
    return lines


def _render_redirection(entry: dict) -> list[str]:
    return _render_flat_fields("redirections", entry, "    ")


def _render_stream(entry: dict) -> list[str]:
    return _render_flat_fields("streams", entry, "    ")


def _render_access_list(entry: dict) -> list[str]:
    lines: list[str] = []
    if entry.get("satisfy_any"):
        lines.append("    satisfy_any = true")
    if entry.get("pass_auth"):
        lines.append("    pass_auth = true")
    auth = entry.get("authorizations")
    if isinstance(auth, list) and auth:
        lines.append("    authorizations = [")
        for item in auth:
            lines.append(
                "      { "
                f"username = {_q(item['username'])}, password = {_q(item['password'])}"
                " },"
            )
        lines.append("    ]")
    access = entry.get("access")
    if isinstance(access, list) and access:
        lines.append("    access = [")
        for item in access:
            lines.append(
                "      { "
                f"directive = {_q(item['directive'])}, address = {_q(item['address'])}"
                " },"
            )
        lines.append("    ]")
    if not lines:
        lines.append("    # (no rules)")
    return lines


def _render_default(default: dict) -> str:
    if not default:
        return "default = {}\n"
    lines = ["default = {"]
    if default.get("certificate_email"):
        lines.append(f"  certificate_email = {_q(default['certificate_email'])}")
    if isinstance(default.get("dns_challenge"), dict):
        lines.extend(_render_dns_challenge(default["dns_challenge"], "  "))
    lines.append("}")
    return "\n".join(lines) + "\n"


def render_config(config: dict) -> str:
    """Render the NPM config tfvars document (including the config-id header)."""
    body = _render_default(config.get("default") or {})
    body += "\n" + _render_map(
        "certificates", config.get("certificates", []), _render_certificate
    )
    body += "\n" + _render_map(
        "proxy_hosts", config.get("proxy_hosts", []), _render_proxy_host
    )
    body += "\n" + _render_map(
        "redirections", config.get("redirections", []), _render_redirection
    )
    body += "\n" + _render_map("streams", config.get("streams", []), _render_stream)
    body += "\n" + _render_map(
        "access_lists", config.get("access_lists", []), _render_access_list
    )
    return f"{_HEADER}{body}"


# --- reading ---------------------------------------------------------------


def _read_collection(collection: str, raw: object) -> list[dict]:
    entries: list[dict] = []
    if not isinstance(raw, dict):
        return entries
    for key, entry in raw.items():
        if not isinstance(entry, dict):
            continue
        payload = dict(entry)
        payload["name"] = coerce_str(key)
        try:
            entries.append(normalize(collection, payload))
        except ConfigValidationError as exc:
            logger.warning("Skipping invalid NPM %s '%s': %s", collection, key, exc)
    return entries


def read_npm_tfvars(path: Path = NPM_CONFIG_TFVARS) -> dict | None:
    """Parse the NPM config tfvars into the config dict, or ``None``.

    Returns ``None`` when the file is missing/unparsable or declares none of the
    managed keys.
    """
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse NPM config %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        return None
    managed = ("default",) + COLLECTIONS
    if not any(key in data for key in managed):
        return None
    config: dict = {"default": normalize_default(data.get("default") or {})}
    for collection in COLLECTIONS:
        config[collection] = _read_collection(collection, data.get(collection))
    return config


def write_npm_tfvars(config: dict, path: Path = NPM_CONFIG_TFVARS) -> Path:
    """Write the NPM config to ``path`` atomically and return it."""
    atomic_write(path, render_config(config))
    logger.info("Wrote NPM config to %s", path)
    return path


__all__ = [
    "COLLECTIONS",
    "ConfigValidationError",
    "canonical",
    "default_config",
    "entry_key",
    "normalize",
    "normalize_default",
    "order_entries",
    "read_npm_tfvars",
    "render_config",
    "write_npm_tfvars",
]
