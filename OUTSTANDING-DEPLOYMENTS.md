# Outstanding deployments

Operator snapshot of what is **not yet deployed** on Swarm after the **May 2026
Swarm recreate** on `swarm-cp-0` (`192.168.1.120`). Live tfvars live under
[`.config/terraform/swarm/`](.config/terraform/swarm/). Pipelines live under
[`terraform/swarm/<service>/pipeline/`](terraform/swarm/).

**Last verified:** 2026-05-23 (Swarm services on `swarm-cp-0`, GHA runner
containers on pool hosts).

Update this file when a stack is brought online or scope changes.

## Context

Recreating Swarm (wiping `/var/lib/docker/swarm` and re-init on
`192.168.1.120:2377`) removed all Swarm **service definitions**. Config in
`.config/terraform/**` and remote Terraform state in MinIO survived; stacks were
re-applied from pipelines. **Bind-mounted / NFS data** (Grafana, etc.) also
survived on disk.

## Already online (Swarm)

These stacks have healthy Swarm services (`1/1` or global `6/6` where
applicable):

| Area | Stacks |
| --- | --- |
| Edge | Nginx Proxy Manager (app + database), cloud-image-repository |
| Observability | Grafana (+ postgres, config), Prometheus, VictoriaMetrics, Graphite, **Graylog** (+ mongodb, datanode on `swarm-wk-0`), prometheus-pve-exporter, qbittorrent-exporter, node_exporter, cadvisor, dozzle |
| RAG | chromadb, rag-engine, mcp-rag |
| MCPs | mcp-argocd, mcp-atlassian, mcp-cloudflare, mcp-fortigate, mcp-github, mcp-google-workspace, mcp-kubernetes, mcp-playwright |
| Registry | **zot** (OCI registry on `swarm-cp-0`, port `35081`) |
| Secrets | vault (app + config on `swarm-cp-0`; unsealed, `vault-auto-unseal.service` on manager) |

## Already online (not Swarm)

These are **not** `docker service` resources and were **not** affected by the
Swarm recreate:

| Stack | Where | Status |
| --- | --- | --- |
| **gha-runner-amd64** (×2) | `runner-amd64` (`192.168.1.101`) — standalone `docker_container` via [`terraform/runners/gha-runner-amd64/pipeline/app.sh`](terraform/runners/gha-runner-amd64/pipeline/app.sh) | Healthy |
| **gha-runner-arm64** (×2) | `swarm-wk-1` (`192.168.1.122`) — [`terraform/runners/gha-runner-arm64/pipeline/app.sh`](terraform/runners/gha-runner-arm64/pipeline/app.sh) | Healthy |

Do **not** expect GHA runners in `docker service ls` on the manager.

## Intentionally scaled down

| Stack | Node | Notes |
| --- | --- | --- |
| **mcp-terraform** | `swarm-wk-0` | Service exists at **`0/0`** — `replicas = 0` in [`.config/terraform/swarm/mcp-terraform/app.tfvars`](.config/terraform/swarm/mcp-terraform/app.tfvars). Raise replicas and re-apply to enable. |

## Yet to deploy (Swarm)

Stacks with tfvars under `.config/terraform/swarm/` that are **not** running on
Swarm:

| Stack | Placement | Pipeline order | Notes |
| --- | --- | --- | --- |
| **jenkins-controller** | `swarm-wk-1` | [`jenkins-controller/app.sh`](terraform/swarm/jenkins-controller/pipeline/app.sh) → [`jenkins-controller/config.sh`](terraform/swarm/jenkins-controller/pipeline/config.sh) | Fix Terraform syntax in [`terraform/swarm/jenkins-controller/app/main.tf`](terraform/swarm/jenkins-controller/app/main.tf) (`Missing newline after block definition` near dynamic `mounts`) before apply |
| **jenkins-agent-amd64** | pool / any | [`jenkins-agent-amd64/pipeline/app.sh`](terraform/runners/jenkins-agent-amd64/pipeline/app.sh) | Depends on controller |
| **jenkins-agent-arm64** | pool / any | [`jenkins-agent-arm64/pipeline/app.sh`](terraform/runners/jenkins-agent-arm64/pipeline/app.sh) | Depends on controller |
| **langchain-agent-chat** | Kubernetes | Argo CD / cluster apply | Production pair is **Kubernetes** only — see [`docs/architecture/kubernetes/README.md`](docs/architecture/kubernetes/README.md) and [`applications/langchain-agent-chat/README.md`](applications/langchain-agent-chat/README.md) |

## Removed / out of scope

| Item | Notes |
| --- | --- |
| **docker_volume_backup** | Removed from `.config`; no repo pipeline or Terraform stack remains |
| **Swarm workers wk-2 / wk-3** | Ready in the cluster; no stacks in `.config` target them exclusively for the redeploy batch |

## Quick verify commands

```bash
# Swarm services (on manager)
ssh nodadyoushutup@192.168.1.120 'docker service ls --format "{{.Name}} {{.Replicas}}" | sort'

# GHA runners (pool hosts, not Swarm)
ssh nodadyoushutup@192.168.1.101 'docker ps --filter name=gha-runner --format "{{.Names}} {{.Status}}"'
ssh nodadyoushutup@192.168.1.122 'docker ps --filter name=gha-runner --format "{{.Names}} {{.Status}}"'
```

## Related docs

- [`docs/workflows/swarm-rpi-network.md`](docs/workflows/swarm-rpi-network.md) — static IPs, Swarm advertise addr on `192.168.1.120`, **boot time sync / Docker Swarm guard** (power-loss recovery)
- [`docs/architecture/terraform/README.md`](docs/architecture/terraform/README.md) — Terraform index
- [`docs/architecture/terraform/swarm-placement.md`](docs/architecture/terraform/swarm-placement.md) — node placement
- [`docs/architecture/terraform/swarm-slices.md`](docs/architecture/terraform/swarm-slices.md) — slice pattern (`app` / `database` / `config`)
- [`docs/workflows/edge-dns-and-nginx-proxy.md`](docs/workflows/edge-dns-and-nginx-proxy.md) — public hostnames via NPM + Cloudflare
