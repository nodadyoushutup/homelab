# Repository layout

This file describes the **top-level tree** of the homelab repo: what each area
is for and how it tends to interact with the others.

## Mental model

- **`terraform/`** defines *where things run* (Swarm stacks, cluster bootstrap,
  edge DNS, firewall objects) and wires networks, volumes, and providers.
- **`applications/`** holds *runnable artifacts* for services we build or
  customize heavily: Docker build contexts, LangGraph apps, MCP servers, Jenkins
  agents, and similar.
- **`kubernetes/`** holds *cluster workload definitions* (Helm values,
  manifests, Argo CD Application roots) for workloads that live on Talos (or
  other kube) rather than on Docker Swarm.
- **`docker/`** is the **local developer** stack (Compose) for fast iteration on
  LangGraph, Agent Chat, RAG, and related tooling—see `AGENTS.md` for the
  canonical dev URLs and env file location.

Those four areas are the day-to-day spine; the sections below expand each
top-level directory.

## Directory reference

| Path | Role |
| --- | --- |
| `applications/` | Service source and Docker build contexts aligned with deployable units (for example `langgraph/`, `rag-engine/`, `mcp-*`, Jenkins pieces, `harbor/` assets where applicable). |
| `kubernetes/` | Per-app or per-platform folders consumed by Argo CD or manual apply; cluster ingress, storage, media stack, and production LangGraph/chat pairs live here. Layout conventions: [03-kubernetes-layout.md](./03-kubernetes-layout.md). |
| `terraform/` | IaC roots: Swarm services, cluster provisioning helpers, remote DNS (Cloudflare), FortiGate config slices, and shared **`terraform/modules/`** helpers. |
| `docker/` | Compose-based local development; not the production Swarm definition. |
| `docs/` | Human source of truth: workflows, architecture (this folder), RAG notes, subagent overlays, resources shelf. |
| `scripts/` | Shell and Python helpers grouped by domain (`swarm/`, `terraform/`, `agents/`, `vault/`, `rag/`, etc.). |
| `packer/` | Machine and cloud image definitions (for example Ubuntu base images) used upstream of Swarm or cluster nodes. |
| `pipelines/` | Jenkins (or related) pipeline definitions organized by technology (`applications/`, `packer/`, `terraform/`). |
| `data/` | Local or exported operational data (screenshots, exports, dev artifacts). Treat as **not** authoritative for infra state; Git usually ignores most of it. |
| `.github/` | GitHub Actions workflows (image builds, Packer, validation). |
| `.config/` | Site-local tfvars, backends, keys, and dotenv (see `.config/docker/README.md`); never commit real secrets or live tfvars. |
| `.cursor/`, `.vscode/` | Editor config. |

## Swarm versus Kubernetes

Use this rule of thumb when deciding where a *new* component should land:

- **Docker Swarm** (Terraform under `terraform/swarm/<service>/`) for edge
  proxies, registries, observability agents, internal MCP endpoints, and other
  infra that the repo already treats as Swarm-first.
- **Kubernetes** (`kubernetes/`) for cluster-native apps, CSI drivers,
  ingress-based services, and workloads that share the Talos cluster lifecycle.

Some systems exist in both worlds in different roles (for example LangGraph
dev in Compose, production graph under `kubernetes/langgraph`). Keep dev/prod
pairing aligned with `AGENTS.md` so local chat never points at prod backends by
accident.

## Config outside this repo

Runtime secrets and host-specific paths often live in a separate config tree
(for example `CONFIG_DIR` on disk). The repo references those locations through
Terraform variables and Compose env files rather than copying secrets into Git.
