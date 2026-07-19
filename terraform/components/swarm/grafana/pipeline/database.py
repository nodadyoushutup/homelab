#!/usr/bin/env python3
"""Grafana database — Python port of pipeline/database.sh (run: python3 <path>).

Derives ``TF_VAR_remote_state_backend`` from the S3 backend config and confirms
the Grafana app slice state exists before applying the database (serialized with
``-parallelism=1``).
"""

from __future__ import annotations

import os
import pathlib
import sys

for _root in pathlib.Path(__file__).resolve().parents:
    if (_root / "scripts/terraform/pipelines/__init__.py").exists():
        sys.path.insert(0, str(_root))
        break

from scripts.terraform.pipelines import SLICE, SliceContext, SlicePipeline
from scripts.terraform.pipelines.state import backend_to_json, ensure_app_state_exists


def _pre_terraform(ctx: SliceContext) -> None:
    os.environ["TF_VAR_remote_state_backend"] = backend_to_json(ctx.backend_config)
    app_dir = ctx.root / "terraform/components/swarm/grafana/app"
    ensure_app_state_exists(app_dir, ctx.backend_config, stage="database")


def build_pipeline() -> SlicePipeline:
    return SlicePipeline(
        name="Grafana database",
        terraform_dir="terraform/components/swarm/grafana/database",
        tfvars_env="GRAFANA_DATABASE_TFVARS",
        backend_env="GRAFANA_DATABASE_BACKEND",
        var_files=["docker", SLICE],
        parallelism=1,
        pre_terraform=_pre_terraform,
    )


if __name__ == "__main__":
    build_pipeline().main()
