# Official Documentation Resources

This is a repo-backed inventory of the main technologies in `homelab`, with official docs that were verified live on `2026-04-16`.

When a project does not maintain a standalone docs site, this file links to the official project wiki or README instead.

## Core infrastructure and build systems

| Technology | Repo evidence | Official docs |
| --- | --- | --- |
| Terraform | `terraform/`, `docs/workflows/terraform.md` | [Terraform docs](https://developer.hashicorp.com/terraform/docs) |
| Packer | `packer/ubuntu-24.04-ndysu.pkr.hcl`, `.github/workflows/packer_build_push.yml` | [Packer docs](https://developer.hashicorp.com/packer/docs) |
| Docker | `terraform/swarm/**`, `applications/**`, `.github/workflows/docker_build_push.yml` | [Docker docs](https://docs.docker.com/) |
| Docker Compose | `docker/docker-compose.minio.yaml`, `applications/gha-runner/docker-compose.yaml` | [Docker Compose docs](https://docs.docker.com/compose/) |
| Docker Swarm | `terraform/swarm/**`, `docs/workflows/terraform.md` | [Docker Swarm docs](https://docs.docker.com/engine/swarm/) |
| GitHub Actions | `.github/workflows/docker_build_push.yml`, `.github/workflows/packer_build_push.yml` | [GitHub Actions docs](https://docs.github.com/en/actions) |
| GitHub Actions self-hosted runners | `applications/gha-runner/`, `terraform/swarm/gha-runner-arm64/app`, `terraform/swarm/gha-runner-amd64/app` | [Self-hosted runner docs](https://docs.github.com/en/actions/concepts/runners/self-hosted-runners) |
| QEMU | `packer/ubuntu-24.04-ndysu.pkr.hcl`, `.github/workflows/packer_build_push.yml` | [QEMU docs](https://www.qemu.org/docs/master/) |
| cloud-init | `packer/cloud-init/user-data`, `packer/cloud-init/meta-data` | [cloud-init docs](https://docs.cloud-init.io/en/latest/) |

## Cluster platform and GitOps

| Technology | Repo evidence | Official docs |
| --- | --- | --- |
| Proxmox VE | `terraform/cluster/proxmox/app` | [Proxmox VE docs index](https://pve.proxmox.com/pve-docs/index.html) |
| Talos Linux | `terraform/cluster/talos/app`, `docs/talos-packages.md` | [Talos docs](https://www.talos.dev/latest/) |
| Kubernetes | `kubernetes/**`, `docs/workflows/kubernetes.md` | [Kubernetes docs](https://kubernetes.io/docs/home/) |
| Argo CD | `kubernetes/bootstrap/argocd-management-app.yaml`, `kubernetes/argocd-management/**`, `terraform/cluster/argocd/config` | [Argo CD docs](https://argo-cd.readthedocs.io/en/stable/) |
| Helm | `kubernetes/k10/values.yaml`, `kubernetes/snapshot-controller/values.yaml`, Argo CD chart apps under `kubernetes/argocd-management/` | [Helm docs](https://helm.sh/docs/) |
| Kustomize | `kubernetes/qbittorrent/base/kustomization.yaml`, `kubernetes/cross-seed/base/kustomization.yaml` | [Kustomize docs](https://kustomize.io/) |
| External Secrets Operator | `kubernetes/external-secrets/`, app-level `secretstore.yaml` and `externalsecret.yaml` manifests | [External Secrets docs](https://external-secrets.io/latest/) |
| ingress-nginx | `kubernetes/ingress-nginx/`, ingress manifests across app directories | [ingress-nginx docs](https://kubernetes.github.io/ingress-nginx/) |
| MetalLB | `kubernetes/metallb/`, `kubernetes/argocd-management/` addon wiring | [MetalLB docs](https://metallb.io/) |
| democratic-csi | `kubernetes/democratic-csi-iscsi/`, `kubernetes/democratic-csi-nfs/` | [democratic-csi docs](https://democratic-csi.github.io/charts/) |
| Veeam Kasten K10 | `kubernetes/k10/`, `kubernetes/argocd-management/applications/k10.yaml` | [K10 docs](https://docs.kasten.io/latest/) |
| CSI snapshot controller / external-snapshotter | `kubernetes/snapshot-controller/`, `kubernetes/argocd-management/snapshot-controller-app.yaml` | [external-snapshotter docs](https://kubernetes-csi.github.io/docs/external-snapshotter.html) |

## Edge, networking, storage, and secrets

| Technology | Repo evidence | Official docs |
| --- | --- | --- |
| Cloudflare | `terraform/remote/cloudflare/config`, `docs/workflows/edge-dns-and-nginx-proxy.md` | [Cloudflare docs](https://developers.cloudflare.com/) |
| Nginx Proxy Manager | `terraform/swarm/nginx_proxy_manager/{app,config,database}`, `docs/workflows/edge-dns-and-nginx-proxy.md` | [Nginx Proxy Manager guide](https://nginxproxymanager.com/guide/) |
| FortiGate / FortiOS | `terraform/network/fortigate/config`, torrent ingress policy in `AGENTS.md` | [FortiGate docs](https://docs.fortinet.com/product/fortigate) |
| MinIO | `docker/docker-compose.minio.yaml`, S3 backends in Terraform provider files | [MinIO docs](https://docs.min.io/) |
| HashiCorp Vault | `terraform/swarm/vault/{app,config}`, `scripts/vault/` | [Vault docs](https://developer.hashicorp.com/vault/docs) |
| PostgreSQL | app-local `postgres-deployment.yaml` files under `kubernetes/` and service database stages | [PostgreSQL docs](https://www.postgresql.org/docs/) |

## Observability, registry, automation, and integration tooling

| Technology | Repo evidence | Official docs |
| --- | --- | --- |
| Grafana | `terraform/swarm/grafana/{app,config,database}` | [Grafana docs](https://grafana.com/docs/) |
| Prometheus | `terraform/swarm/prometheus/{app,database}` | [Prometheus docs](https://prometheus.io/docs/introduction/overview/) |
| Grafana Loki | `terraform/swarm/loki/app` | [Loki docs](https://grafana.com/docs/loki/latest/) |
| Grafana Alloy | `terraform/swarm/alloy/app` | [Alloy docs](https://grafana.com/docs/alloy/latest/) |
| Graphite | `terraform/swarm/graphite/app` | [Graphite docs](https://graphite.readthedocs.io/en/latest/) |
| Telegraf | `terraform/swarm/telegraf_docker_metrics/app` | [Telegraf docs](https://docs.influxdata.com/telegraf/v1/configuration/) |
| Dozzle | `terraform/swarm/dozzle/app` | [Dozzle docs](https://dozzle.dev/guide/what-is-dozzle) |
| Harbor | `terraform/swarm/harbor/{app,config}`, `applications/harbor/` | [Harbor docs](https://goharbor.io/docs/) |
| Jenkins | `terraform/swarm/jenkins-agent-arm64/app`, `terraform/swarm/jenkins-agent-amd64/app`, `terraform/swarm/jenkins-controller/{app,config}`, `applications/jenkins-agent/`, `applications/jenkins-controller/` | [Jenkins docs](https://www.jenkins.io/doc/) |
| Model Context Protocol (MCP) | `applications/mcp-*`, `terraform/swarm/mcp-*/app` | [MCP docs](https://modelcontextprotocol.io/docs/learn) |

## Application workloads

| Technology | Repo evidence | Official docs |
| --- | --- | --- |
| ChromaDB | `terraform/swarm/chromadb/app` | [Chroma Docker docs](https://docs.trychroma.com/guides/deploy/docker) |
| qBittorrent | `kubernetes/qbittorrent/base`, `kubernetes/qbittorrent/overlays` | [qBittorrent wiki](https://github.com/qbittorrent/qBittorrent/wiki) |
| cross-seed | `kubernetes/cross-seed/base`, `kubernetes/cross-seed/overlays` | [cross-seed docs](https://www.cross-seed.org/docs/basics/getting-started) |
| Plex / ClusterPlex | `kubernetes/clusterplex/` | [Plex support docs](https://support.plex.tv/) |
| Radarr | `kubernetes/radarr/` | [Radarr wiki](https://wiki.servarr.com/radarr) |
| Sonarr | `kubernetes/sonarr/` | [Sonarr wiki](https://wiki.servarr.com/sonarr) |
| Prowlarr | `kubernetes/prowlarr/` | [Prowlarr wiki](https://wiki.servarr.com/prowlarr) |
| Seerr | `kubernetes/seerr/` | [Seerr docs](https://docs.seerr.dev/) |
| Tautulli | `kubernetes/tautulli/` | [Tautulli installation wiki](https://github.com/Tautulli/Tautulli/wiki/Installation) |
| The Lounge | `kubernetes/thelounge/` | [The Lounge docs](https://thelounge.chat/docs) |
| PrivateBin | `kubernetes/privatebin/` | [PrivateBin site and docs hub](https://privatebin.info/) |
| Picsur | `kubernetes/picsur/` | [Picsur official repo README](https://github.com/CaramelFur/Picsur) |

## Notes

- Some projects in this repo expose official docs through a GitHub wiki or repository README rather than a dedicated docs site. Those entries are intentionally marked that way.
- This file is meant to be a quick starting point, not a complete vendor manual index. If a new major technology lands in the repo, add it here only after verifying the official link is live.
