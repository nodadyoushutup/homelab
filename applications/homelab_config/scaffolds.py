"""Ensure managed ``.config`` files exist on boot as empty, editable scaffolds.

homelab-config treats the on-disk files as the source of truth. So a fresh
checkout (or a freshly wiped ``.config``) can be worked on immediately, every
config file this app manages is registered here: on boot, any missing file is
created with an *empty* body. Existing files are never touched, so operator
content and hand edits are preserved.

As new settings are added to the app, register their file + empty renderer here.
"""

from __future__ import annotations

import logging
from collections.abc import Callable
from pathlib import Path

from homelab_config.cloud_image_repository_config import (
    default_config as cloud_image_repository_default_config,
)
from homelab_config.cloud_image_repository_config import (
    render_config as render_cloud_image_repository,
)
from homelab_config.cloudflare_dns_config import render_config as render_cloudflare_dns
from homelab_config.docker_providers_config import render_docker_tfvars
from homelab_config.extra_hosts_config import render_extra_hosts
from homelab_config.fortigate_config import default_config as fortigate_default_config
from homelab_config.fortigate_config import render_config as render_fortigate_config
from homelab_config.grafana_config import render_config as render_grafana_config
from homelab_config.minio_config import render_instances as render_minio
from homelab_config.nfs_config import render_shares
from homelab_config.npm_config import default_config as npm_default_config
from homelab_config.npm_config import render_config as render_npm_config
from homelab_config.packer_config import default_settings as packer_default_settings
from homelab_config.packer_config import render_settings as render_packer_settings
from homelab_config.prometheus_config import default_config as prometheus_default_config
from homelab_config.prometheus_config import render_config as render_prometheus_config
from homelab_config.victoriametrics_config import (
    default_settings as victoriametrics_default_settings,
)
from homelab_config.victoriametrics_config import (
    render_settings as render_victoriametrics_settings,
)
from homelab_config.vault_config import (
    DEFAULT_MOUNT_PATH as VAULT_DEFAULT_MOUNT_PATH,
)
from homelab_config.vault_config import render_config as render_vault_config
from homelab_config.paths import (
    CLOUD_IMAGE_REPOSITORY_APP_TFVARS,
    CLOUDFLARE_CONFIG_TFVARS,
    DOCKER_TFVARS,
    EXTRA_HOSTS_YAML,
    FORTIGATE_CONFIG_TFVARS,
    GRAFANA_CONFIG_TFVARS,
    MINIO_BACKEND_HCL,
    MINIO_TFVARS,
    NFS_TFVARS,
    NPM_CONFIG_TFVARS,
    PACKER_BUILD_PKRVARS,
    PROMETHEUS_YAML,
    PROXMOX_APP_TFVARS,
    PROXMOX_TFVARS,
    SWARM_TFVARS,
    TALOS_APP_TFVARS,
    TERRAFORM_STATE_TFVARS,
    VAULT_CONFIG_TFVARS,
    VICTORIAMETRICS_APP_TFVARS,
)
from homelab_config.terraform_config import default_settings as terraform_default_settings
from homelab_config.terraform_config import render_backend as render_minio_backend
from homelab_config.terraform_config import render_settings as render_terraform_state
from homelab_config.talos_config import default_config as talos_default_config
from homelab_config.talos_config import render_config as render_talos
from homelab_config.jenkins_config import SLICES as JENKINS_SLICES
from homelab_config.jenkins_config import default_config as jenkins_default_config
from homelab_config.jenkins_config import render_config as render_jenkins
from homelab_config.proxmox_cluster_config import render_config as render_proxmox_cluster
from homelab_config.provider_config_generic import (
    default_record as provider_default_record,
)
from homelab_config.provider_config_generic import render as render_provider
from homelab_config.provider_specs import PROVIDER_SPECS
from homelab_config.proxmox_config import default_credentials, render_credentials
from homelab_config.swarm_config import order_nodes, read_swarm_tfvars, render_nodes

logger = logging.getLogger(__name__)


def _render_docker_scaffold() -> str:
    """Docker catalog scaffold: derived swarm providers, empty extras/registry."""
    nodes = order_nodes(read_swarm_tfvars(SWARM_TFVARS) or [])
    return render_docker_tfvars(nodes, [], [])


# Each entry: (target path, renderer producing the *empty* file contents).
_SCAFFOLDS: list[tuple[Path, Callable[[], str]]] = [
    (SWARM_TFVARS, lambda: render_nodes([])),
    (NFS_TFVARS, lambda: render_shares([])),
    (MINIO_TFVARS, lambda: render_minio([])),
    (TERRAFORM_STATE_TFVARS, lambda: render_terraform_state(terraform_default_settings())),
    (MINIO_BACKEND_HCL, lambda: render_minio_backend(terraform_default_settings(), None)),
    (PROXMOX_TFVARS, lambda: render_credentials(default_credentials())),
    (PROXMOX_APP_TFVARS, lambda: render_proxmox_cluster([], [])),
    (TALOS_APP_TFVARS, lambda: render_talos(talos_default_config())),
    (EXTRA_HOSTS_YAML, lambda: render_extra_hosts([])),
    *(
        (
            _js.path,
            lambda s=_js: render_jenkins(s.key, jenkins_default_config(s.kind)),
        )
        for _js in JENKINS_SLICES
    ),
    (DOCKER_TFVARS, _render_docker_scaffold),
    (CLOUDFLARE_CONFIG_TFVARS, lambda: render_cloudflare_dns("", [])),
    (FORTIGATE_CONFIG_TFVARS, lambda: render_fortigate_config(fortigate_default_config())),
    (NPM_CONFIG_TFVARS, lambda: render_npm_config(npm_default_config())),
    (
        CLOUD_IMAGE_REPOSITORY_APP_TFVARS,
        lambda: render_cloud_image_repository(cloud_image_repository_default_config()),
    ),
    (GRAFANA_CONFIG_TFVARS, lambda: render_grafana_config([])),
    (PROMETHEUS_YAML, lambda: render_prometheus_config(prometheus_default_config())),
    (
        VICTORIAMETRICS_APP_TFVARS,
        lambda: render_victoriametrics_settings(victoriametrics_default_settings()),
    ),
    (VAULT_CONFIG_TFVARS, lambda: render_vault_config(VAULT_DEFAULT_MOUNT_PATH, [])),
    (PACKER_BUILD_PKRVARS, lambda: render_packer_settings(packer_default_settings())),
]

# Register a scaffold per spec-driven provider (cloudflare, grafana, jenkins,
# argocd, fortigate, nginx_proxy_manager, vault) so a fresh checkout boots with
# an empty, valid providers/<app>.tfvars for each.
for _spec in PROVIDER_SPECS:
    _SCAFFOLDS.append(
        (
            _spec.tfvars_path,
            lambda s=_spec: render_provider(s, provider_default_record(s)),
        )
    )


def ensure_config_scaffolds() -> list[Path]:
    """Create any missing managed config file as an empty scaffold.

    Returns:
        The list of paths that were created this call (empty when all present).
    """
    created: list[Path] = []
    for path, render in _SCAFFOLDS:
        if path.exists():
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(render(), encoding="utf-8")
        logger.info("Created empty config scaffold: %s", path)
        created.append(path)
    return created


__all__ = ["ensure_config_scaffolds"]
