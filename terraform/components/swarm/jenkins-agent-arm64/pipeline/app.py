#!/usr/bin/env python3
"""Jenkins agent arm64 — Python port of pipeline/app.sh (run: python3 <path>).

Validates the Jenkins controller slice is applied and that the pinned agent
image manifest advertises arm64 before deploying.
"""

from __future__ import annotations

import pathlib
import sys

for _root in pathlib.Path(__file__).resolve().parents:
    if (_root / "scripts/terraform/pipelines/__init__.py").exists():
        sys.path.insert(0, str(_root))
        break

from scripts.terraform.pipelines import SLICE, SlicePipeline
from scripts.terraform.pipelines.jenkins_agent import make_pre_terraform


def build_pipeline() -> SlicePipeline:
    return SlicePipeline(
        name="Jenkins agent arm64",
        terraform_dir="terraform/components/swarm/jenkins-agent-arm64/app",
        tfvars_env="JENKINS_AGENT_ARM64_APP_TFVARS",
        backend_env="JENKINS_AGENT_ARM64_APP_BACKEND",
        var_files=["docker", SLICE, "nfs"],
        pre_terraform=make_pre_terraform("arm64"),
    )


if __name__ == "__main__":
    build_pipeline().main()
