#!/usr/bin/env python3
"""Talos cluster — Python port of pipeline/app.sh (run: python3 <path>).

Before plan/apply it decides which node ``talos_machine_configuration_apply``
resources (and the bootstrap resource) to ``-replace`` based on Talos API
reachability and Kubernetes readiness, and redirects local-file outputs to
writable managed paths when needed.  After init it repairs the
``talos_machine_secrets`` / ``talos_machine_bootstrap`` state entries when the
live API is reachable.
"""

from __future__ import annotations

import pathlib
import sys

for _root in pathlib.Path(__file__).resolve().parents:
    if (_root / "scripts/terraform/pipelines/__init__.py").exists():
        sys.path.insert(0, str(_root))
        break

from scripts.terraform.pipelines import SLICE, SlicePipeline
from scripts.terraform.pipelines.talos import TalosReconciler


def build_pipeline() -> SlicePipeline:
    reconciler = TalosReconciler()
    return SlicePipeline(
        name="Talos cluster",
        terraform_dir="terraform/components/cluster/talos/app",
        tfvars_env="TALOS_APP_TFVARS",
        backend_env="TALOS_APP_BACKEND",
        var_files=[SLICE],
        pre_terraform=reconciler.pre_terraform,
        post_init=reconciler.post_init,
    )


if __name__ == "__main__":
    build_pipeline().main()
