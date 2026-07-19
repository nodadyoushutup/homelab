#!/usr/bin/env python3
"""Vault config — Python port of pipeline/config.sh (run: python3 <path>).

Ensures Vault is reachable + unsealed, merges KV secret payloads into a
generated ``*.auto.tfvars.json`` (passed as an extra ``-var-file``), then applies
the config slice alongside the Vault provider credentials.
"""

from __future__ import annotations

import pathlib
import sys

for _root in pathlib.Path(__file__).resolve().parents:
    if (_root / "scripts/terraform/pipelines/__init__.py").exists():
        sys.path.insert(0, str(_root))
        break

from scripts.terraform.pipelines import SLICE, SlicePipeline
from scripts.terraform.pipelines.vault import config_unseal_and_merge


def build_pipeline() -> SlicePipeline:
    return SlicePipeline(
        name="Vault config",
        terraform_dir="terraform/components/swarm/vault/config",
        tfvars_env="VAULT_CONFIG_TFVARS",
        backend_env="VAULT_CONFIG_BACKEND",
        var_files=[SLICE, "vault"],
        pre_terraform=config_unseal_and_merge,
    )


if __name__ == "__main__":
    build_pipeline().main()
