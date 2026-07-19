"""Shared provider / catalog ``-var-file`` specs.

Python equivalents of the ``scripts/terraform/*_tfvars_env.sh`` helpers.  Each
entry resolves a shared tfvars file (managed by the homelab-config web app) by
config-id; slice pipelines pass the relevant ones as extra ``-var-file`` args
alongside their own slice tfvars.

The ``env_var`` field matches the bash export name so an operator override such
as ``DOCKER_TFVARS=/path`` behaves identically in the Python ports.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from .config_resolver import ConfigResolver


@dataclass(frozen=True)
class ProviderVarFile:
    """A shared tfvars file passed as an extra ``-var-file``."""

    key: str
    config_id: str
    label: str
    env_var: str

    def resolve(self, resolver: ConfigResolver) -> Path:
        override = os.environ.get(self.env_var)
        if override:
            return Path(override)
        return resolver.resolve(self.config_id)


PROVIDERS: dict[str, ProviderVarFile] = {
    "docker": ProviderVarFile(
        "docker", "terraform/providers/docker", "docker providers tfvars", "DOCKER_TFVARS"
    ),
    "nfs": ProviderVarFile(
        "nfs", "terraform/nfs", "nfs catalog tfvars", "NFS_TFVARS"
    ),
    "grafana": ProviderVarFile(
        "grafana", "terraform/providers/grafana", "grafana credentials tfvars", "GRAFANA_TFVARS"
    ),
    "jenkins": ProviderVarFile(
        "jenkins", "terraform/providers/jenkins", "jenkins credentials tfvars", "JENKINS_TFVARS"
    ),
    "fortigate": ProviderVarFile(
        "fortigate", "terraform/providers/fortigate", "fortigate credentials tfvars", "FORTIGATE_TFVARS"
    ),
    "cloudflare": ProviderVarFile(
        "cloudflare", "terraform/providers/cloudflare", "cloudflare credentials tfvars", "CLOUDFLARE_TFVARS"
    ),
    "argocd": ProviderVarFile(
        "argocd", "terraform/providers/argocd", "argocd credentials tfvars", "ARGOCD_TFVARS"
    ),
    "proxmox": ProviderVarFile(
        "proxmox", "terraform/providers/proxmox", "proxmox credentials tfvars", "PROXMOX_TFVARS"
    ),
    "vault": ProviderVarFile(
        "vault", "terraform/providers/vault", "vault credentials tfvars", "VAULT_TFVARS"
    ),
    "nginx_proxy_manager": ProviderVarFile(
        "nginx_proxy_manager",
        "terraform/providers/nginx_proxy_manager",
        "nginx proxy manager credentials tfvars",
        "NGINX_PROXY_MANAGER_TFVARS",
    ),
}


def provider(key: str) -> ProviderVarFile:
    try:
        return PROVIDERS[key]
    except KeyError as exc:  # pragma: no cover - programming error
        raise KeyError(f"Unknown provider var-file '{key}'") from exc
