#!/usr/bin/env python3
"""Graylog database — Python port of pipeline/database.sh (run: python3 <path>)."""

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
        name="Graylog database",
        terraform_dir="terraform/components/swarm/graylog/database",
        tfvars_env="GRAYLOG_DATABASE_TFVARS",
        backend_env="GRAYLOG_DATABASE_BACKEND",
        var_files=["docker", SLICE],
    )


if __name__ == "__main__":
    build_pipeline().main()
