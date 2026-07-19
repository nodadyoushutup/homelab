#!/usr/bin/env python3
"""Vault app — Python port of pipeline/app.sh (run: python3 <path>).

SSH port preflight against the swarm manager, then terraform init/plan/apply,
then ``scripts/vault/bootstrap.sh`` and a post-deploy health poll.
"""

from __future__ import annotations

import pathlib
import sys

for _root in pathlib.Path(__file__).resolve().parents:
    if (_root / "scripts/terraform/pipelines/__init__.py").exists():
        sys.path.insert(0, str(_root))
        break

from scripts.terraform.pipelines import SLICE, SlicePipeline
from scripts.terraform.pipelines.vault import app_bootstrap_and_health, app_preflight


def build_pipeline() -> SlicePipeline:
    return SlicePipeline(
        name="Vault app",
        terraform_dir="terraform/components/swarm/vault/app",
        tfvars_env="VAULT_APP_TFVARS",
        backend_env="VAULT_APP_BACKEND",
        var_files=["docker", SLICE],
        pre_terraform=app_preflight,
        post_apply=app_bootstrap_and_health,
    )


if __name__ == "__main__":
    build_pipeline().main()
