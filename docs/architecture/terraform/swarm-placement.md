# Swarm application placement

When someone says **“add XYZ app”**, classify the workload **before** writing
Terraform. Runtime choice (Swarm vs Kubernetes vs runner pool) comes first; for
Swarm services, **node role** comes next. Only then pick slice structure
(`app` / `config` / `database`) — see
[swarm-slices.md](./swarm-slices.md).

For Swarm vs Kubernetes at the repo level, start with
[01-repository-layout.md](../01-repository-layout.md). For `terraform/` domains and
the slice index, see [README.md](./README.md).

## Swarm nodes

| Node | LAN address | Label (`node.labels.role`) | Primary role |
| --- | --- | --- | --- |
| `swarm-cp-0` | `192.168.1.120` | (manager) | Control plane; colocated **edge / registry / secrets** when noted below |
| `swarm-wk-0` | `192.168.1.121` | `swarm-wk-0` | **Platform observability** — logs, metrics, monitoring, system introspection |
| `swarm-wk-1` | `192.168.1.122` | `swarm-wk-1` | **CI/CD** — Jenkins, pipeline runners, build-adjacent Swarm services |
| `swarm-wk-2` | `192.168.1.123` | `swarm-wk-2` | Spare worker (no exclusive stack class today) |
| `swarm-wk-3` | `192.168.1.124` | `swarm-wk-3` | Spare worker (no exclusive stack class today) |
| `swarm-wk-4` | `192.168.1.125` | `swarm-wk-4` | **AI** — RAG, vector DBs, MCP servers, agent-adjacent workloads |

Static addressing and Ethernet-only networking:
[`docs/workflows/swarm-rpi-network.md`](../../workflows/swarm-rpi-network.md).

Label a worker before pinning a stack:

```bash
docker node update --label-add role=swarm-wk-0 <node-id>
# or: scripts/swarm/ensure_swarm_worker_node.sh --role swarm-wk-0 --host swarm-wk-0.local --apply-label
```

For **`swarm-wk-4`**, join + label in one step:
`scripts/swarm/prepare_swarm_wk4_ai_node.sh`.

## Decision flow

```mermaid
flowchart TD
  start["Add component XYZ"]
  runtime{"Where does it run?"}
  swarm["terraform/components/swarm/"]
  k8s["kubernetes/ + Argo CD"]
  runners["terraform/components/runners/"]
  classify{"Swarm workload class?"}
  wk0["swarm-wk-0\n(observability / system mgmt)"]
  wk1["swarm-wk-1\n(CI/CD Swarm services)"]
  wk4["swarm-wk-4\n(AI / RAG / MCP)"]
  cp0["swarm-cp-0\n(edge / registry / secrets)"]
  global["Global mode\n(all nodes)"]
  slices["Pick slices:\nswarm-slices.md"]

  start --> runtime
  runtime -->|Swarm docker_service| swarm
  runtime -->|Cluster workload| k8s
  runtime -->|Pool-host docker_container| runners
  swarm --> classify
  classify -->|Logs, metrics, monitoring,\ncontainer/host introspection| wk0
  classify -->|Jenkins, GHA on wk-1 host,\nimage/build helpers| wk1
  classify -->|RAG, embeddings, MCP,\nLLM agents, vector DB| wk4
  classify -->|NPM, Zot, Vault,\nmanager-colocated edge| cp0
  classify -->|Per-node daemon\n(e.g. exporters)| global
  wk0 --> slices
  wk1 --> slices
  wk4 --> slices
  cp0 --> slices
  global --> slices
```

## Workload classes

### Platform observability and system management → `swarm-wk-0`

Use **`swarm-wk-0`** when the service **monitors or manages the homelab
platform itself**: log aggregation, metrics storage/scrape, dashboards,
container visibility, and similar **operator-facing** observability.

**Examples in repo:** `grafana` (+ `database`, `config`), `prometheus`,
`victoriametrics`, `graphite`, `graylog` (+ `database`), `dozzle`,
`prometheus-pve-exporter`, `qbittorrent-exporter`.

**Exception — global daemons:** `cadvisor` and `node_exporter` run in Swarm
**global** mode (one task per node). Do **not** pin them to `swarm-wk-0`; they
already cover every worker.

### CI/CD → `swarm-wk-1` and `terraform/components/runners/`

Use **`swarm-wk-1`** for Swarm services that **run or support pipelines**:
Jenkins controller, build helpers, and anything whose primary job is CI/CD
orchestration on Swarm.

**Swarm on `swarm-wk-1`:** `jenkins-controller` (+ `config`),
`cloud-image-repository`, **`gha-runner-arm64`** (standalone `docker_container`
resources on the `swarm-wk-1` host — not a `docker service`).

**Runner pools (`terraform/components/runners/`):** workloads that must be
**`docker_container`** on a pool host, not Swarm tasks:

| Pool | Typical host | Stacks |
| --- | --- | --- |
| `gha-runner-amd64` | `runner-amd64` (`192.168.1.101`) | `terraform/components/runners/gha-runner-amd64/app` |
| `gha-runner-arm64` | `swarm-wk-1` | `terraform/components/runners/gha-runner-arm64/app` |
| `jenkins-agent-amd64` / `jenkins-agent-arm64` | pool / any ready host | `terraform/components/runners/jenkins-agent-*/app` |

Do **not** look for GHA runners in `docker service ls` on the manager.

### AI → `swarm-wk-4`

Use **`swarm-wk-4`** for anything **AI-related**: RAG, vector databases,
embedding/index services, MCP servers wired to agents, and other stacks whose
primary consumers are LangGraph or operator AI tooling.

**Examples in repo:** `chromadb`, `rag-engine`, `mcp-rag`, and the rest of the
`mcp-*` Swarm family (`mcp-atlassian`, `mcp-playwright`, `mcp-kubernetes`, …).

Production **LangGraph** and **LangChain Agent Chat** run on **Kubernetes**, not
Swarm — see [kubernetes/README.md](../kubernetes/README.md).

### Manager-colocated edge and platform (`swarm-cp-0`)

Some stacks intentionally run on the **manager** because they are cluster-wide
edge, registry, or secrets infrastructure:

**Examples:** `nginx_proxy_manager` (+ `database`, `config`), `zot`, `vault`
(+ `config`).

This is **not** a fourth general-purpose worker pool — default new apps to
`swarm-wk-0`, `swarm-wk-1`, or `swarm-wk-4` unless they match edge/registry/secrets.

### Spare workers (`swarm-wk-2`, `swarm-wk-3`)

No stack class is pinned exclusively to wk-2 or wk-3 today. Use them only when
you have a deliberate reason (isolation experiment, capacity relief) and document
the exception in the stack’s operator notes.

## Expressing placement in Terraform

Swarm **`app/`** and **`database/`** slices take an optional **`placement`**
map in slice tfvars (not in `main.tf`):

```hcl
placement = {
  constraints = ["node.labels.role==swarm-wk-4"]
  platforms = [
    {
      os           = "linux"
      architecture = "aarch64"
    },
  ]
}
```

Omit **`placement`** only when the service is **global** or genuinely
schedulable anywhere. For new replicated services, **always set a constraint**
matching the workload class above.

Runner pools set the target host via provider tfvars
(`.config/terraform/components/runners/amd64.tfvars`, `runners/arm64.tfvars`) — see
[swarm-slices.md](./swarm-slices.md#config-and-pipelines).

## Checklist: new Swarm app

1. **Classify** — observability (`wk-0`), CI/CD (`wk-1` / runners), AI (`wk-4`),
   manager edge (`cp-0`), or global.
2. **Confirm runtime** — Swarm `docker_service` vs `terraform/components/runners/` vs
   Kubernetes.
3. **Create** `terraform/components/swarm/<service>/` (and slices) — naming matches the
   operational service name.
4. **Set `placement`** in `.config/terraform/components/swarm/<service>/app.tfvars` (and
   `database.tfvars` when the DB slice should follow the same node).
5. **Pin image + ports** in slice **`main.tf`**; put `env` and secrets in tfvars.
6. **Add pipeline** under `terraform/components/swarm/<service>/pipeline/` (`app.sh`,
   and `config.sh` / `database.sh` when those slices exist) — mirror a neighbor
   in the same class; shared logic stays in `scripts/terraform/swarm_pipeline.sh`.
7. **Public hostname** — Cloudflare + NPM tfvars if the app is edge-published
   ([edge-dns-and-nginx-proxy.md](../../workflows/edge-dns-and-nginx-proxy.md)).
