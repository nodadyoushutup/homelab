#!/usr/bin/env python3
"""Argo CD config — Python port of pipeline/config.sh (run: python3 <path>)."""

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
        name="Argo CD config",
        terraform_dir="terraform/components/cluster/argocd/config",
        tfvars_env="ARGOCD_CONFIG_TFVARS",
        backend_env="ARGOCD_CONFIG_BACKEND",
        var_files=[SLICE, "argocd"],
    )


if __name__ == "__main__":
    build_pipeline().main()
