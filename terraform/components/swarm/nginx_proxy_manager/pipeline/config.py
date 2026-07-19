#!/usr/bin/env python3
"""Nginx Proxy Manager config — Python port of pipeline/config.sh (run: python3 <path>).

Confirms the NPM app slice state exists, then applies certificates + proxy hosts
via the NPM API alongside the NPM provider credentials (serialized with
``-parallelism=1``).
"""

from __future__ import annotations

import pathlib
import sys

for _root in pathlib.Path(__file__).resolve().parents:
    if (_root / "scripts/terraform/pipelines/__init__.py").exists():
        sys.path.insert(0, str(_root))
        break

from scripts.terraform.pipelines import SLICE, SliceContext, SlicePipeline
from scripts.terraform.pipelines.state import ensure_app_state_exists


def _pre_terraform(ctx: SliceContext) -> None:
    app_dir = ctx.root / "terraform/components/swarm/nginx_proxy_manager/app"
    ensure_app_state_exists(app_dir, ctx.backend_config, stage="config")


def build_pipeline() -> SlicePipeline:
    return SlicePipeline(
        name="Nginx Proxy Manager config",
        terraform_dir="terraform/components/swarm/nginx_proxy_manager/config",
        tfvars_env="NPM_CONFIG_TFVARS",
        backend_env="NPM_CONFIG_BACKEND",
        var_files=[SLICE, "nginx_proxy_manager"],
        slice_label="config tfvars",
        parallelism=1,
        pre_terraform=_pre_terraform,
    )


if __name__ == "__main__":
    build_pipeline().main()
