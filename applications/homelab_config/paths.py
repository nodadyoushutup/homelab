"""Filesystem paths for the homelab-config application."""

from __future__ import annotations

import os
from pathlib import Path

# applications/homelab_config/paths.py -> applications/homelab_config
#   -> applications -> repo root (or /workspace in the container).
APP_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = APP_DIR.parents[1]

CONFIG_DIR = PROJECT_ROOT / ".config"
# Live Docker Swarm topology (config-id: docker/swarm) generated from the UI.
# Rendered as an HCL swarm_nodes map (tfvars), consumed only by this app.
SWARM_TFVARS = CONFIG_DIR / "docker" / "swarm.tfvars"
# Non-swarm Docker hosts (config-id: docker/extra_hosts) generated from the UI.
# Same machine shape as swarm nodes (minus role/labels); the Docker provider
# catalog derives providers from these alongside the swarm nodes.
EXTRA_HOSTS_YAML = CONFIG_DIR / "docker" / "extra_hosts.yaml"

# Shared catalog of existing NFS exports (config-id: terraform/nfs) generated from
# the UI and consumed by Terraform slices via -var-file. Lives under .config
# (git-ignored) - do not commit it.
NFS_TFVARS = CONFIG_DIR / "terraform" / "nfs.tfvars"

# Catalog of already-existing MinIO instances (config-id: terraform/minio)
# generated from the UI. Holds connection details (endpoint + S3 credentials)
# for each MinIO the homelab uses (e.g. one for Terraform remote state, one for
# backups). This app does not deploy MinIO; it only records how to reach them.
# Holds secrets, so it lives under .config (git-ignored) - do not commit it.
MINIO_TFVARS = CONFIG_DIR / "terraform" / "minio.tfvars"

# Terraform state backend settings (config-id: terraform/state) generated from
# the UI. This is the source of truth for the Terraform section: it records
# whether state is local or a remote MinIO S3 backend, which MinIO instance to
# use, and the bucket. The S3 backend file below is DERIVED from these settings.
TERRAFORM_STATE_TFVARS = CONFIG_DIR / "terraform" / "state.tfvars"

# Terraform S3 remote-state backend config (config-id: terraform/minio.backend),
# DERIVED by the Terraform section from the state settings above plus the
# selected MinIO instance's connection details. Consumed by every slice pipeline
# via `terraform init -backend-config`. Holds secrets - do not commit it.
MINIO_BACKEND_HCL = CONFIG_DIR / "terraform" / "minio.backend.hcl"

# Provider credentials live under .config/terraform/providers/<app>.tfvars
# (config-id terraform/providers/<app>): one file per app that needs a provider
# login, generated from the UI and consumed by that app's Terraform slice via
# -var-file. These hold secrets, so they live under .config (git-ignored).
PROVIDERS_DIR = CONFIG_DIR / "terraform" / "providers"
PROXMOX_TFVARS = PROVIDERS_DIR / "proxmox.tfvars"
DOCKER_TFVARS = PROVIDERS_DIR / "docker.tfvars"

# Proxmox cluster images + machines (config-id
# terraform/components/cluster/proxmox/app) generated from the UI and consumed
# by the Proxmox cluster Terraform slice as its slice -var-file. This is the
# VMs/images config, NOT the provider credentials (PROXMOX_TFVARS above).
PROXMOX_APP_TFVARS = (
    CONFIG_DIR / "terraform" / "components" / "cluster" / "proxmox" / "app.tfvars"
)

# Talos cluster machine config/bootstrap inputs (config-id
# terraform/components/cluster/talos/app) generated from the UI and consumed by
# the Talos Terraform slice as its slice -var-file. Holds the cluster settings,
# per-node Talos API endpoints + config-patch paths, client endpoints, and the
# talosconfig/kubeconfig output paths.
TALOS_APP_TFVARS = (
    CONFIG_DIR / "terraform" / "components" / "cluster" / "talos" / "app.tfvars"
)

# Jenkins swarm-app deploy inputs (CICD section). One app.tfvars per slice,
# each consumed by its Swarm Terraform slice as the slice -var-file. These hold
# the operator-facing deploy inputs (docker_machine, dns_nameservers, NFS
# selection, env, ports/placement/mounts for the controller, jenkins_url +
# label filter for the agents). Provider login stays in providers/jenkins.tfvars.
JENKINS_CONTROLLER_APP_TFVARS = (
    CONFIG_DIR / "terraform" / "components" / "swarm" / "jenkins-controller" / "app.tfvars"
)
JENKINS_AGENT_AMD64_APP_TFVARS = (
    CONFIG_DIR / "terraform" / "components" / "swarm" / "jenkins-agent-amd64" / "app.tfvars"
)
JENKINS_AGENT_ARM64_APP_TFVARS = (
    CONFIG_DIR / "terraform" / "components" / "swarm" / "jenkins-agent-arm64" / "app.tfvars"
)

# Cloudflare DNS desired state (config-id
# terraform/components/remote/cloudflare/config) generated from the UI and
# consumed by the Cloudflare config Terraform slice as its slice -var-file. This
# is the DNS records config (zone_id + records), NOT the provider credentials
# (those live in .config/terraform/providers/cloudflare.tfvars).
CLOUDFLARE_CONFIG_TFVARS = (
    CONFIG_DIR / "terraform" / "components" / "remote" / "cloudflare" / "config.tfvars"
)

# FortiGate desired state (config-id terraform/components/network/fortigate/config)
# generated from the UI and consumed by the FortiGate config Terraform slice as
# its slice -var-file. This is the declarative firewall config (virtual IPs,
# firewall policies, DHCP reservations), NOT the provider credentials (those
# live in .config/terraform/providers/fortigate.tfvars).
FORTIGATE_CONFIG_TFVARS = (
    CONFIG_DIR / "terraform" / "components" / "network" / "fortigate" / "config.tfvars"
)

# Nginx Proxy Manager desired state (config-id
# terraform/components/swarm/nginx_proxy_manager/config) generated from the UI
# and consumed by the NPM config Terraform slice as its slice -var-file. This is
# the proxy hosts / certificates / access lists / redirections / streams config,
# NOT the provider credentials (those live in
# .config/terraform/providers/nginx_proxy_manager.tfvars).
NPM_CONFIG_TFVARS = (
    CONFIG_DIR
    / "terraform"
    / "components"
    / "swarm"
    / "nginx_proxy_manager"
    / "config.tfvars"
)

# Cloud Image Repository Swarm app settings (config-id
# terraform/components/swarm/cloud-image-repository/app) generated from the UI
# and consumed by the Cloud Image Repository app Terraform slice as its slice
# -var-file: which docker_machine to deploy on, DNS nameservers, placement, and
# which shared NFS share + sub-path backs the served /data directory. The shared
# Docker provider catalog (providers/docker.tfvars) and NFS catalog (nfs.tfvars)
# are separate -var-files.
CLOUD_IMAGE_REPOSITORY_APP_TFVARS = (
    CONFIG_DIR
    / "terraform"
    / "components"
    / "swarm"
    / "cloud-image-repository"
    / "app.tfvars"
)

# --- Monitoring section -----------------------------------------------------

# Grafana desired state (config-id terraform/components/swarm/grafana/config)
# generated from the UI and consumed by the Grafana config Terraform slice as
# its slice -var-file. This is the data sources config (dashboards are JSON
# files baked into the slice), NOT the provider credentials (those live in
# .config/terraform/providers/grafana.tfvars).
GRAFANA_CONFIG_TFVARS = (
    CONFIG_DIR / "terraform" / "components" / "swarm" / "grafana" / "config.tfvars"
)

# Prometheus scrape configuration YAML, bind-mounted into the Prometheus service
# via the app slice's config_path. This is the real "what are we monitoring"
# config (global settings, remote_write, and scrape jobs + targets). It is plain
# Prometheus YAML (NOT tfvars), so it carries no homelab-config tfvars tag.
PROMETHEUS_YAML = (
    CONFIG_DIR / "terraform" / "components" / "swarm" / "prometheus" / "prometheus.yaml"
)

# VictoriaMetrics Swarm app settings (config-id
# terraform/components/swarm/victoriametrics/app) generated from the UI and
# consumed by the VictoriaMetrics app Terraform slice as its slice -var-file:
# which docker_machine to deploy on, DNS nameservers, and placement. The shared
# Docker provider catalog (providers/docker.tfvars) is a separate -var-file.
VICTORIAMETRICS_APP_TFVARS = (
    CONFIG_DIR / "terraform" / "components" / "swarm" / "victoriametrics" / "app.tfvars"
)

# Vault KV desired state (config-id terraform/components/swarm/vault/config)
# generated from the UI and consumed by the Vault config Terraform slice as its
# slice -var-file. This is the KV v2 mount path + inline secrets (group -> name
# -> field -> value), NOT the provider credentials (those live in
# .config/terraform/providers/vault.tfvars). Holds secret values, so it lives
# under .config (git-ignored) - do not commit it.
VAULT_CONFIG_TFVARS = (
    CONFIG_DIR / "terraform" / "components" / "swarm" / "vault" / "config.tfvars"
)

# Packer build defaults (config-id: packer/build) generated from the UI and
# consumed as defaults by packer/packer.sh and packer/pipeline/packer.sh (CLI
# flags still override). This is a Packer var-file-shaped HCL document, but it
# also carries orchestration keys (distro, build_arch, target, publish) that are
# NOT Packer variables, so the scripts parse it for their own defaults rather
# than feeding it to `packer -var-file`. Lives under .config (git-ignored).
PACKER_BUILD_PKRVARS = CONFIG_DIR / "packer" / "build.pkrvars.hcl"

# SSH identity/config used by providers and hosts. Mirrors the operator's
# ~/.ssh and is fully git-ignored (see .gitignore: .config/*).
SSH_DIR = CONFIG_DIR / ".ssh"
# The host machine's SSH directory we can sync keys/config from. Overridable via
# HOMELAB_HOST_SSH_DIR so the container can point at a read-only bind mount of the
# operator's real ~/.ssh (see docker/docker-compose.homelab-config.yaml).
HOST_SSH_DIR = Path(os.environ.get("HOMELAB_HOST_SSH_DIR") or (Path.home() / ".ssh"))

# Runtime state lives under data/ (git-ignored) so it never pollutes the tree.
DATA_DIR = PROJECT_ROOT / "data" / "homelab-config"
# Records the PID of the running server so a fresh launch can restart it.
PID_FILE = DATA_DIR / "homelab_config.pid"

DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 8770


def display_path(path: Path | str, *, root: Path = PROJECT_ROOT) -> str:
    """Return a repo-relative path string for logs and prompts.

    Uses the logical path under ``root`` and does not follow symlinks out of the
    tree (important for ``.venv/bin/python3`` → system interpreter). Paths
    outside ``root`` fall back to their original string form.

    Args:
        path: Filesystem path to display.
        root: Repository root used as the relative base.

    Returns:
        POSIX-style relative path when under ``root``, otherwise ``str(path)``.
    """
    candidate = Path(path)
    root_resolved = root.resolve()
    absolute = candidate if candidate.is_absolute() else root_resolved / candidate
    # absolute() does not follow symlinks; resolve() can escape the repo.
    try:
        return absolute.absolute().relative_to(root_resolved).as_posix()
    except ValueError:
        return candidate.as_posix()
