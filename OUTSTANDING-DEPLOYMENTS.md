# Outstanding deployments

Operator snapshot of what is **not yet deployed** on Swarm after the **May 2026
Swarm recreate** on `swarm-cp-0` (`192.168.1.120`). Live tfvars live under
[`.config/terraform/swarm/`](.config/terraform/swarm/). Pipelines live under
[`pipelines/terraform/swarm/`](pipelines/terraform/swarm/).

**Last verified:** 2026-05-23 (Swarm services on `swarm-cp-0`, GHA runner
containers on pool hosts).

Update this file when a stack is brought online or scope changes.

## Context

Recreating Swarm (wiping `/var/lib/docker/swarm` and re-init on
`192.168.1.120:2377`) removed all Swarm **service definitions**. Config in
`.config/terraform/**` and remote Terraform state in MinIO survived; stacks were
re-applied from pipelines. **Bind-mounted / NFS data** (Grafana, Harbor Postgres,
etc.) also survived on disk.

## Already online (Swarm)

These stacks have healthy Swarm services (`1/1` or global `6/6` where
applicable):

| Area | Stacks |
| --- | --- |
| Edge | Nginx Proxy Manager (app + database), cloud-image-repository |
| Observability | Grafana (+ postgres, config), Prometheus (+ VictoriaMetrics), Graphite, **Graylog** (+ mongodb, datanode on `swarm-wk-0`), prometheus-pve-exporter, qbittorrent-exporter, node_exporter, telegraf_docker_metrics, dozzle |
| RAG | chromadb, rag-engine, mcp-rag |
| MCPs | mcp-argocd, mcp-atlassian, mcp-cloudflare, mcp-fortigate, mcp-github, mcp-google-workspace, mcp-kubernetes, mcp-playwright |
| Harbor runtime | harbor-log, registry, registryctl, postgresql, redis, core, portal, jobservice, proxy, trivy-adapter (all on `swarm-cp-0`) |
| Secrets | vault (app + config on `swarm-cp-0`; unsealed, `vault-auto-unseal.service` on manager) |

Harbor **config** (`harbor/config`) is reconciled in Terraform (project
`homelab`, robot accounts).

## Already online (not Swarm)

These are **not** `docker service` resources and were **not** affected by the
Swarm recreate:

| Stack | Where | Status |
| --- | --- | --- |
| **gha-runner-amd64** (×2) | `runner-amd64` (`192.168.1.101`) — standalone `docker_container` via [`pipelines/terraform/swarm/gha-runner-amd64/app.sh`](pipelines/terraform/swarm/gha-runner-amd64/app.sh) | Healthy |
| **gha-runner-arm64** (×2) | `swarm-wk-1` (`192.168.1.122`) — [`pipelines/terraform/swarm/gha-runner-arm64/app.sh`](pipelines/terraform/swarm/gha-runner-arm64/app.sh) | Healthy |

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
| **jenkins-controller** | `swarm-wk-1` | [`jenkins-controller/app.sh`](pipelines/terraform/swarm/jenkins-controller/app.sh) → [`jenkins-controller/config.sh`](pipelines/terraform/swarm/jenkins-controller/config.sh) | Fix Terraform syntax in [`terraform/swarm/jenkins-controller/app/main.tf`](terraform/swarm/jenkins-controller/app/main.tf) (`Missing newline after block definition` near dynamic `mounts`) before apply |
| **jenkins-agent-amd64** | pool / any | [`jenkins-agent-amd64/app.sh`](pipelines/terraform/swarm/jenkins-agent-amd64/app.sh) | Depends on controller |
| **jenkins-agent-arm64** | pool / any | [`jenkins-agent-arm64/app.sh`](pipelines/terraform/swarm/jenkins-agent-arm64/app.sh) | Depends on controller |
| **langchain-agent-chat** | any (Swarm tfvars exist) | Swarm pipeline if used | Production pair is usually **Kubernetes** — see [`docs/architecture/03-kubernetes-layout.md`](docs/architecture/03-kubernetes-layout.md) and [`applications/langchain-agent-chat/README.md`](applications/langchain-agent-chat/README.md) |

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

- [`docs/workflows/swarm-rpi-network.md`](docs/workflows/swarm-rpi-network.md) — static IPs, Swarm advertise addr on `192.168.1.120`
- [`docs/architecture/02-terraform-layout.md`](docs/architecture/02-terraform-layout.md) — slice pattern (`app` / `database` / `config`)
- [`docs/workflows/edge-dns-and-nginx-proxy.md`](docs/workflows/edge-dns-and-nginx-proxy.md) — public hostnames via NPM + Cloudflare
