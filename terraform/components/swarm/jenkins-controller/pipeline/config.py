#!/usr/bin/env python3
"""Jenkins controller config — Python port of pipeline/config.sh (run: python3 <path>)."""

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
        name="Jenkins controller config",
        terraform_dir="terraform/components/swarm/jenkins-controller/config",
        tfvars_env="JENKINS_CONTROLLER_CONFIG_TFVARS",
        backend_env="JENKINS_CONTROLLER_CONFIG_BACKEND",
        var_files=[SLICE, "jenkins"],
    )


if __name__ == "__main__":
    build_pipeline().main()
