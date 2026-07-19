"""Prometheus scrape-config helpers and read/write for the Prometheus YAML at
``.config/terraform/components/swarm/prometheus/prometheus.yaml``.

This is plain Prometheus configuration (NOT tfvars): it is bind-mounted into the
Prometheus service via the app slice's ``config_path``. The file is the source
of truth; this module parses it into an editable model and renders it back.

Model:
- ``global``: ``scrape_interval`` / ``evaluation_interval`` (any other keys are
  preserved as ``extra``).
- ``remote_write``: a list of endpoints (``url`` + preserved ``extra``).
- ``scrape_configs``: scrape jobs keyed by ``job_name``. Common fields
  (``metrics_path``, ``scheme``, ``scrape_interval``, ``scrape_timeout``) and the
  ``static_configs`` (target groups: ``targets`` + ``labels``) are structured;
  any other job keys (``params``, ``relabel_configs``, ...) are preserved
  verbatim as ``extra`` so nothing is dropped on save.
"""

from __future__ import annotations

import json
import logging
from collections.abc import Iterable
from pathlib import Path

import yaml

from homelab_config.hcl_util import atomic_write
from homelab_config.paths import PROMETHEUS_YAML

logger = logging.getLogger(__name__)

_HEADER = (
    "# Prometheus scrape configuration, managed by the homelab-config web app\n"
    "# (applications/homelab_config).\n"
    "# Generated file: edit scrape jobs in the UI (or by hand) then write it back.\n"
    "# Bind-mounted into the Prometheus service via the app slice's config_path.\n"
    "# This file lives under .config (git-ignored) - do not commit it.\n"
)

_GLOBAL_KNOWN = ("scrape_interval", "evaluation_interval")
_JOB_KNOWN = (
    "job_name",
    "metrics_path",
    "scheme",
    "scrape_interval",
    "scrape_timeout",
    "static_configs",
)


class ConfigValidationError(ValueError):
    """Raised when a Prometheus config payload fails validation."""


def _s(value: object) -> str:
    return "" if value is None else str(value)


def _extra_from(mapping: dict, known: Iterable[str]) -> dict:
    known_set = set(known)
    return {k: v for k, v in mapping.items() if k not in known_set}


def _parse_extra_yaml(text: object) -> dict:
    """Parse the per-item advanced-YAML text into a mapping (empty when blank)."""
    if isinstance(text, dict):
        return text
    raw = _s(text).strip()
    if not raw:
        return {}
    try:
        parsed = yaml.safe_load(raw)
    except yaml.YAMLError as exc:
        raise ConfigValidationError(f"advanced YAML is not valid: {exc}") from exc
    if parsed is None:
        return {}
    if not isinstance(parsed, dict):
        raise ConfigValidationError("advanced YAML must be a mapping of keys")
    return parsed


# --- normalize -------------------------------------------------------------


def normalize_global(data: dict) -> dict:
    data = data or {}
    record: dict = {}
    scrape = _s(data.get("scrape_interval")).strip()
    evaluation = _s(data.get("evaluation_interval")).strip()
    if scrape:
        record["scrape_interval"] = scrape
    if evaluation:
        record["evaluation_interval"] = evaluation
    extra = data.get("extra")
    record["extra"] = _parse_extra_yaml(extra) if extra is not None else (
        _extra_from(data, _GLOBAL_KNOWN + ("extra",))
    )
    return record


def normalize_remote_write(entries: object) -> list[dict]:
    out: list[dict] = []
    if not isinstance(entries, (list, tuple)):
        return out
    for entry in entries:
        if isinstance(entry, str):
            url = entry.strip()
            if url:
                out.append({"url": url, "extra": {}})
            continue
        if not isinstance(entry, dict):
            continue
        url = _s(entry.get("url")).strip()
        if not url:
            continue
        extra_raw = entry.get("extra")
        extra = (
            _parse_extra_yaml(extra_raw)
            if extra_raw is not None
            else _extra_from(entry, ("url", "extra"))
        )
        out.append({"url": url, "extra": extra})
    return out


def _normalize_static_config(entry: dict) -> dict:
    targets_raw = entry.get("targets")
    targets: list[str] = []
    if isinstance(targets_raw, str):
        targets = [t.strip() for t in targets_raw.replace("\n", ",").split(",") if t.strip()]
    elif isinstance(targets_raw, (list, tuple)):
        targets = [_s(t).strip() for t in targets_raw if _s(t).strip()]
    labels_raw = entry.get("labels")
    labels: dict = {}
    if isinstance(labels_raw, dict):
        for key, value in labels_raw.items():
            name = _s(key).strip()
            if name:
                labels[name] = _s(value)
    extra = _extra_from(entry, ("targets", "labels"))
    sc: dict = {"targets": targets, "labels": labels}
    if extra:
        sc["extra"] = extra
    return sc


def normalize_job(data: dict) -> dict:
    job_name = _s(data.get("job_name")).strip()
    if not job_name:
        raise ConfigValidationError("job_name is required")
    record: dict = {"job_name": job_name}
    for field in ("metrics_path", "scheme", "scrape_interval", "scrape_timeout"):
        value = _s(data.get(field)).strip()
        if value:
            record[field] = value
    static_configs: list[dict] = []
    raw_sc = data.get("static_configs")
    if isinstance(raw_sc, (list, tuple)):
        for entry in raw_sc:
            if isinstance(entry, dict):
                sc = _normalize_static_config(entry)
                if sc["targets"] or sc["labels"] or sc.get("extra"):
                    static_configs.append(sc)
    record["static_configs"] = static_configs
    extra_raw = data.get("extra")
    record["extra"] = (
        _parse_extra_yaml(extra_raw)
        if extra_raw is not None
        else _extra_from(data, _JOB_KNOWN + ("extra",))
    )
    return record


def default_config() -> dict:
    """Return an empty Prometheus config model."""
    return {"global": {"extra": {}}, "remote_write": [], "scrape_configs": []}


def job_key(job: dict) -> str:
    return str(job.get("job_name", ""))


def order_jobs(jobs: Iterable[dict]) -> list[dict]:
    """Prometheus evaluates jobs in file order; preserve it (no re-sorting)."""
    return list(jobs)


# --- drift -----------------------------------------------------------------


def canonical(config: dict) -> str:
    """Return a semantic JSON string for equality/drift checks (format-agnostic)."""
    return json.dumps(config or {}, sort_keys=True, default=str)


# --- rendering -------------------------------------------------------------


def _global_document(global_cfg: dict) -> dict:
    doc: dict = {}
    for field in _GLOBAL_KNOWN:
        if global_cfg.get(field):
            doc[field] = global_cfg[field]
    doc.update(global_cfg.get("extra") or {})
    return doc


def _job_document(job: dict) -> dict:
    doc: dict = {"job_name": job["job_name"]}
    for field in ("scrape_interval", "scrape_timeout", "metrics_path", "scheme"):
        if job.get(field):
            doc[field] = job[field]
    static_configs = []
    for sc in job.get("static_configs", []):
        entry: dict = {}
        if sc.get("targets"):
            entry["targets"] = list(sc["targets"])
        if sc.get("labels"):
            entry["labels"] = dict(sc["labels"])
        entry.update(sc.get("extra") or {})
        static_configs.append(entry)
    if static_configs:
        doc["static_configs"] = static_configs
    doc.update(job.get("extra") or {})
    return doc


def build_document(config: dict) -> dict:
    """Build the plain dict that is dumped to YAML (ordered global/rw/jobs)."""
    doc: dict = {}
    global_doc = _global_document(config.get("global") or {})
    if global_doc:
        doc["global"] = global_doc
    remote_write = []
    for entry in config.get("remote_write", []):
        rw: dict = {"url": entry["url"]}
        rw.update(entry.get("extra") or {})
        remote_write.append(rw)
    if remote_write:
        doc["remote_write"] = remote_write
    doc["scrape_configs"] = [_job_document(j) for j in config.get("scrape_configs", [])]
    return doc


def render_config(config: dict) -> str:
    """Render the Prometheus YAML document (including the header comment)."""
    body = yaml.safe_dump(
        build_document(config), sort_keys=False, default_flow_style=False, width=4096
    )
    return f"{_HEADER}{body}"


# --- reading ---------------------------------------------------------------


def read_prometheus_yaml(path: Path = PROMETHEUS_YAML) -> dict | None:
    """Parse prometheus.yaml into the config model, or ``None`` when missing/bad."""
    if not path.is_file():
        return None
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        logger.warning("Could not parse Prometheus config %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        return None
    config: dict = {
        "global": normalize_global(data.get("global") or {}),
        "remote_write": normalize_remote_write(data.get("remote_write")),
        "scrape_configs": [],
    }
    raw_jobs = data.get("scrape_configs")
    if isinstance(raw_jobs, (list, tuple)):
        for entry in raw_jobs:
            if not isinstance(entry, dict):
                continue
            try:
                config["scrape_configs"].append(normalize_job(entry))
            except ConfigValidationError as exc:
                logger.warning("Skipping invalid Prometheus job: %s", exc)
    return config


def write_prometheus_yaml(config: dict, path: Path = PROMETHEUS_YAML) -> Path:
    """Write the Prometheus config to ``path`` atomically and return it."""
    atomic_write(path, render_config(config))
    logger.info("Wrote Prometheus config to %s", path)
    return path


__all__ = [
    "ConfigValidationError",
    "build_document",
    "canonical",
    "default_config",
    "job_key",
    "normalize_global",
    "normalize_job",
    "normalize_remote_write",
    "order_jobs",
    "read_prometheus_yaml",
    "render_config",
    "write_prometheus_yaml",
]
