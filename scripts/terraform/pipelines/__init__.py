"""Homelab pipeline library.

Pure-Python (stdlib-only) reimplementation of the repo's bash ``pipeline/*.sh``
Terraform runners, plus the Docker/Packer build pipelines.  Each
``pipeline/<slice>.py`` entrypoint builds a :class:`SlicePipeline` (or a bespoke
runner) from this library and can be executed directly:

    python3 terraform/components/swarm/grafana/pipeline/app.py

The same building blocks (``ConfigResolver``, ``TerraformRunner``,
``SlicePipeline``, provider var-file specs) are import-friendly so the
homelab-config web app can launch pipelines programmatically in the future
(see :mod:`scripts.terraform.pipelines.registry`).
"""

from __future__ import annotations

from .cli import SliceArgs, env_first, parse_slice_args
from .config_resolver import ConfigResolver, config_id_from_terraform_dir
from .logging_util import PipelineError, done, err, info, stage, step, warn
from .providers import PROVIDERS, ProviderVarFile, provider
from .slice_pipeline import SLICE, SliceContext, SlicePipeline, run_pipeline_main
from .state import backend_to_json, ensure_app_state_exists
from .terraform import TerraformRunner, require_terraform

__all__ = [
    "SLICE",
    "SliceArgs",
    "SliceContext",
    "SlicePipeline",
    "ConfigResolver",
    "PROVIDERS",
    "ProviderVarFile",
    "TerraformRunner",
    "PipelineError",
    "config_id_from_terraform_dir",
    "ensure_app_state_exists",
    "backend_to_json",
    "env_first",
    "parse_slice_args",
    "provider",
    "require_terraform",
    "run_pipeline_main",
    "info",
    "warn",
    "step",
    "stage",
    "done",
    "err",
]
