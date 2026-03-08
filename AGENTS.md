# AGENTS

Use this as a directory to the source-of-truth docs agents need.

- Machine inventory (hosts, IPs, OS/arch, Docker versions, access/NFS notes): `docs/wiki/Machines.md`.
- Secrets, tfvars/backends, kube configs, env files: `docs/wiki/Secrets.md`.
- SSH CA machine onboarding (host/user cert trust, manual install): `docs/wiki/SSH-CA.md`.
- Docker Swarm workflow (taxonomy, planning stages, pipelines/Jenkins, tfvars/backends, purge scripts, resource links): `docs/wiki/Docker-Swarm.md`.
- Swarm node onboarding (manual worker/manager add, prerequisites, labels, validation): `docs/wiki/Swarm-Node-Onboarding.md`.
- Planning docs for active changes: `docs/planning/<service>-plan.md` (complete before merging).
- Repo path is `~/code/homelab` everywhere via NFS from `truenas.internal` (see Machines for export details).
- `_old/` rule (HARD RULE): always treat all code under `_old/` as out-of-scope legacy content. Do not read, modify, refactor, lint, test, or include `_old/` files in agent changes unless a human explicitly asks for `_old/` work. Do not add `_old/` to `.gitignore`.
- Compose-only stacks (MinIO backend + Renovate) run on `swarm-cp-0.local` under `docker/minio/` and `docker/renovate/`; images must support `linux/aarch64`.
- NFS root_squash note: running repo scripts directly via `sudo` can return “Permission denied”; pipe them into `sudo bash -s` or copy to `/tmp` first.
- Python note: use `python3` explicitly; no `python` shim is assumed across hosts.
- Never abstract a container image to locals in terraform. Always have the image directly in the resource.
- Docker Swarm Terraform note (current policy): `terraform/module/<service>` abstraction is deprecated for new Swarm apps. For new Swarm work, define resources directly in `terraform/docker/<service>/<stage>` and reference existing working direct-stack services as implementation examples.
- Never use Terraform `moved` blocks in this repo unless the user explicitly asks for them in that task.
- Kubernetes workflow: when making Kubernetes changes, agents should run raw `kubectl apply` as needed for immediate rollout/validation and should not wait on GitOps reconciliation. Humans will handle commits/pushes that trigger GitOps.
- Argo CD recovery rule (HARD RULE): after any action that can disrupt the whole cluster (control-plane/worker rebuilds, mass node restarts, cluster-wide networking/storage changes), agents must verify Argo CD is healthy again before closing the task (`argocd-server`, `argocd-repo-server`, `argocd-application-controller`, and app health checks).
- DATASET SAFETY (HARD RULE): agents must never delete, destroy, rename, or purge any TrueNAS/ZFS dataset in any pool.
- DATASET SAFETY (HARD RULE): agents must never run any destroy/delete Terraform apply/plan targeting datasets, and must never run `zfs destroy`, `midclt call pool.dataset.delete`, or any equivalent destructive dataset operation.
- DATASET SAFETY (HARD RULE): creating new Kubernetes-related datasets is allowed only under the `eapp` pool (for example `eapp/k8s/...`) and must not modify or remove existing datasets.
- DATASET SAFETY (HARD RULE): dataset deletion is manual-only by a human operator, never by an agent.
