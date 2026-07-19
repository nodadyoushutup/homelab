#!/usr/bin/env python3
"""Graphite — Python port of pipeline/app.sh (run: python3 <path>)."""

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
        name="Graphite",
        terraform_dir="terraform/components/swarm/graphite/app",
        tfvars_env="GRAPHITE_APP_TFVARS",
        backend_env="GRAPHITE_APP_BACKEND",
        var_files=["docker", SLICE],
    )


if __name__ == "__main__":
    build_pipeline().main()
