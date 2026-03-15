# AGENTS

Use this as a directory to the source-of-truth docs agents need.

- Legacy wiki docs were intentionally removed and are being rebuilt; do not reference old wiki paths until new docs are added.
- Planning docs workflow:
  - `docs/planning/pending/<service>-plan.md`: planned/proposed work not currently being executed.
  - `docs/planning/active/<service>-plan.md`: work in progress right now (must be completed before merging related changes).
  - `docs/planning/archive/<service>-plan.md`: completed, cancelled, or superseded plans kept for history/reference.
  - Agents should move plans between these folders as state changes; do not keep active plans in the top-level `docs/planning/`.
- Repo path is `~/code/homelab` everywhere via NFS from `truenas.internal`.
- `_old/` rule (HARD RULE): always treat all code under `_old/` as out-of-scope legacy content. Do not read, modify, refactor, lint, test, or include `_old/` files in agent changes unless a human explicitly asks for `_old/` work. Do not add `_old/` to `.gitignore`.
- Compose-only stacks (MinIO backend + Renovate) run on `swarm-cp-0.local` under `docker/minio/` and `docker/renovate/`; images must support `linux/aarch64`.
- NFS root_squash note: running repo scripts directly via `sudo` can return “Permission denied”; pipe them into `sudo bash -s` or copy to `/tmp` first.
- Python note: use `python3` explicitly; no `python` shim is assumed across hosts.
- Multi-agent git rule: if unrelated untracked/modified files from other agents are present, ignore them and only stage/commit/push files relevant to the current task unless a human explicitly asks otherwise.
- Never abstract a container image to locals in terraform. Always have the image directly in the resource.
- Docker Swarm Terraform note (current policy): `terraform/module/<service>` abstraction is deprecated for new Swarm apps. For new Swarm work, define resources directly in `terraform/swarm/<service>/<stage>` and reference existing working direct-stack services as implementation examples.
- Edge routing/DNS rule (HARD RULE): whenever adding any new application endpoint (Docker Swarm, standalone Docker/Compose, or Kubernetes), agents must add/update both Nginx Proxy Manager and Cloudflare entries via tfvars (`/mnt/eapp/.tfvars/nginx-proxy-manager/config.tfvars` and `/mnt/eapp/.tfvars/cloudflare/config.tfvars`) and deploy them through Terraform pipelines; do not leave app endpoints as manual-only UI/API changes.
- Torrent ingress rule (HARD RULE): for any BitTorrent client (for example qBittorrent) that needs inbound peer traffic, agents must implement direct L4 forwarding in code, not HTTP reverse proxy routing. In Kubernetes, expose the torrent port with a dedicated `NodePort` Service for both TCP and UDP and keep per-instance ports unique. In FortiGate Terraform, create/update matching VIP + WAN->LAN firewall policies for both TCP and UDP so `extport` maps to the correct node IP and nodePort. Agents must check for existing VIP/policy port conflicts before apply (legacy entries can shadow new mappings), avoid Nginx Proxy Manager for torrent peer ports, and validate both in-cluster reachability (`nodeIP:nodePort`) and external reachability (public IP + forwarded port).
- Infra persistence rule (HARD RULE): agents must not treat MCP/UI/manual firewall or routing edits as sufficient final state. Any networking, FortiGate, DNS, proxy, or ingress changes must be represented in repo code (`*.tf`, `*.tfvars`, Kubernetes manifests, kustomizations) and applied from code so they persist across reconciliations and future runs.
- Never use Terraform `moved` blocks in this repo unless the user explicitly asks for them in that task.
- Kubernetes workflow: when making Kubernetes changes, agents should run raw `kubectl apply` as needed for immediate rollout/validation and should not wait on GitOps reconciliation. Humans will handle commits/pushes that trigger GitOps.
- Argo CD recovery rule (HARD RULE): after any action that can disrupt the whole cluster (control-plane/worker rebuilds, mass node restarts, cluster-wide networking/storage changes), agents must verify Argo CD is healthy again before closing the task (`argocd-server`, `argocd-repo-server`, `argocd-application-controller`, and app health checks).
- DATASET SAFETY (HARD RULE): agents must never delete, destroy, rename, or purge any TrueNAS/ZFS dataset in any pool.
- DATASET SAFETY (HARD RULE): agents must never run any destroy/delete Terraform apply/plan targeting datasets, and must never run `zfs destroy`, `midclt call pool.dataset.delete`, or any equivalent destructive dataset operation.
- DATASET SAFETY (HARD RULE): creating new Kubernetes-related datasets is allowed only under the `eapp` pool (for example `eapp/k8s/...`) and must not modify or remove existing datasets.
- DATASET SAFETY (HARD RULE): dataset deletion is manual-only by a human operator, never by an agent.
