#!/usr/bin/env python3
"""
Render harbor.yml from Harbor app tfvars and run harbor-prepare before Terraform.

Reads operator-facing values from the app slice tfvars (hostname, passwords, paths),
writes harbor.yml under the install path, and invokes the harbor-prepare container to
generate common/config (including component env files) and data secrets.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

try:
    import hcl2
except ImportError as exc:  # pragma: no cover
    print(
        "[ERR] python-hcl2 is required.\n"
        "      uv run --with 'python-hcl2>=4,<5' --with pyyaml python3 "
        ".../scripts/harbor/prepare_from_tfvars.py ...",
        file=sys.stderr,
    )
    raise SystemExit(1) from exc

try:
    import yaml
except ImportError as exc:  # pragma: no cover
    print("[ERR] pyyaml is required.", file=sys.stderr)
    raise SystemExit(1) from exc


DEFAULT_PREPARE_IMAGE = (
    "ghcr.io/nodadyoushutup/harbor-prepare:0.0.3"
    "@sha256:5b319c300934aa66671316570afae4c4b05de42d287ac688e311693fefa6eb36"
)
DEFAULT_HTTP_PORT = 8080


def _require_str(doc: dict, key: str, path: Path) -> str:
    value = doc.get(key)
    if not isinstance(value, str) or not value.strip():
        print(f"[ERR] {path} must set non-empty string {key}", file=sys.stderr)
        raise SystemExit(1)
    return value.strip()


def _optional_str(doc: dict, key: str) -> str | None:
    value = doc.get(key)
    if value is None:
        return None
    if not isinstance(value, str):
        print(f"[ERR] {key} must be a string when set", file=sys.stderr)
        raise SystemExit(1)
    value = value.strip()
    return value or None


def _load_tfvars(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        parsed = hcl2.load(handle)
    if not isinstance(parsed, dict):
        print(f"[ERR] Expected HCL object in {path}", file=sys.stderr)
        raise SystemExit(1)
    return parsed


def build_harbor_yml(doc: dict, tfvars_path: Path) -> dict:
    hostname = _require_str(doc, "harbor_hostname", tfvars_path)
    admin_password = _require_str(doc, "harbor_admin_password", tfvars_path)
    db_password = _require_str(doc, "harbor_db_password", tfvars_path)
    data_volume = _require_str(doc, "harbor_data_path", tfvars_path)
    external_url = _optional_str(doc, "harbor_external_url")
    log_location = _optional_str(doc, "harbor_log_path") or "/var/log/harbor"

    harbor_yml: dict = {
        "hostname": hostname,
        "http": {"port": DEFAULT_HTTP_PORT},
        "harbor_admin_password": admin_password,
        "database": {"password": db_password},
        "data_volume": data_volume,
        "jobservice": {
            "max_job_workers": 10,
            "max_job_duration_hours": 24,
            "job_loggers": ["STD_OUTPUT", "FILE"],
            "logger_sweeper_duration": 1,
        },
        "notification": {
            "webhook_job_max_retry": 3,
            "webhook_job_http_client_timeout": 3,
        },
        "log": {
            "level": "info",
            "local": {
                "rotate_count": 50,
                "rotate_size": "200M",
                "location": log_location,
            },
        },
        "_version": "2.14.0",
    }
    if external_url:
        harbor_yml["external_url"] = external_url
    return harbor_yml


def write_harbor_yml(install_path: Path, harbor_yml: dict) -> Path:
    install_path.mkdir(parents=True, exist_ok=True)
    output = install_path / "harbor.yml"
    with output.open("w", encoding="utf-8") as handle:
        yaml.safe_dump(harbor_yml, handle, default_flow_style=False, sort_keys=False)
    return output


def fix_config_permissions(config_path: Path) -> None:
    """Prepare writes root-only files; Terraform file() must read component env on the runner."""
    if not config_path.is_dir():
        return
    subprocess.run(
        [
            "docker",
            "run",
            "--rm",
            "-v",
            f"{config_path}:/config",
            "alpine:3",
            "sh",
            "-c",
            "find /config -type f -name env -exec chmod a+r {} +",
        ],
        check=True,
    )


def run_prepare(
    *,
    prepare_image: str,
    install_path: Path,
    data_path: Path,
    harbor_yml: Path,
    enable_trivy: bool,
) -> None:
    config_path = install_path / "common" / "config"
    config_path.mkdir(parents=True, exist_ok=True)
    data_path.mkdir(parents=True, exist_ok=True)

    cmd = [
        "docker",
        "run",
        "--rm",
        "--privileged",
        "-v",
        "/:/hostfs",
        "-v",
        f"{harbor_yml.parent}:/input:ro",
        "-v",
        f"{data_path}:/data",
        "-v",
        f"{install_path}:/compose_location",
        "-v",
        f"{config_path}:/config",
        prepare_image,
        "prepare",
        "--conf",
        "/input/harbor.yml",
    ]
    if enable_trivy:
        cmd.append("--with-trivy")

    print(f"[STEP] harbor-prepare install={install_path} data={data_path} trivy={enable_trivy}")
    subprocess.run(cmd, check=True)
    fix_config_permissions(config_path)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tfvars", type=Path, required=True, help="Harbor app.tfvars path")
    parser.add_argument(
        "--prepare-image",
        default=DEFAULT_PREPARE_IMAGE,
        help="harbor-prepare image reference",
    )
    args = parser.parse_args(argv)

    tfvars_path = args.tfvars.resolve()
    if not tfvars_path.is_file():
        print(f"[ERR] Missing tfvars file: {tfvars_path}", file=sys.stderr)
        return 1

    doc = _load_tfvars(tfvars_path)
    install_path = Path(_require_str(doc, "harbor_install_path", tfvars_path))
    data_path = Path(_require_str(doc, "harbor_data_path", tfvars_path))
    log_path = _optional_str(doc, "harbor_log_path")
    if log_path:
        Path(log_path).mkdir(parents=True, exist_ok=True)

    enable_trivy = doc.get("enable_trivy", True)
    if not isinstance(enable_trivy, bool):
        print("[ERR] enable_trivy must be a boolean when set", file=sys.stderr)
        return 1

    prepare_image = _optional_str(doc, "prepare_image") or args.prepare_image

    harbor_yml_doc = build_harbor_yml(doc, tfvars_path)
    harbor_yml_path = write_harbor_yml(install_path, harbor_yml_doc)
    print(f"[INFO] Wrote {harbor_yml_path}")

    run_prepare(
        prepare_image=prepare_image,
        install_path=install_path,
        data_path=data_path,
        harbor_yml=harbor_yml_path,
        enable_trivy=enable_trivy,
    )
    print("[DONE] harbor-prepare complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
