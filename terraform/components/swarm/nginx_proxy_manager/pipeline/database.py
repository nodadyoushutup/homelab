#!/usr/bin/env python3
"""Nginx Proxy Manager database — Python port of pipeline/database.sh (run: python3 <path>)."""

from __future__ import annotations

import pathlib
import sys

for _root in pathlib.Path(__file__).resolve().parents:
    if (_root / "scripts/terraform/pipelines/__init__.py").exists():
        sys.path.insert(0, str(_root))
        break

from scripts.terraform.pipelines import SLICE, SlicePipeline


def build_pipeline() -> SlicePipeline:
    return SlicePipeline(
        name="Nginx Proxy Manager database",
        terraform_dir="terraform/components/swarm/nginx_proxy_manager/database",
        tfvars_env="NGINX_PROXY_MANAGER_DATABASE_TFVARS",
        backend_env="NGINX_PROXY_MANAGER_DATABASE_BACKEND",
        var_files=["docker", SLICE],
    )


if __name__ == "__main__":
    build_pipeline().main()
