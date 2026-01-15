# Secrets

Source of truth for where operational secrets and environment files live across the homelab fleet. All paths are present on every machine via the NFS exports from `truenas.internal` (see [[Machines]] for host details).

## Locations

| Path | Purpose | Notes |
| --- | --- | --- |
| `~/.jenkins` | Jenkins controller/agent secrets, CASC fragments, SSH materials | Backed by `/mnt/eapp/home/.jenkins` on TrueNAS; required before running any Jenkins Terraform stages or pipelines. |
| `~/.tfvars` | Terraform inputs for all stacks plus backend config | Backed by `/mnt/eapp/home/.tfvars`; includes `minio.backend.hcl` and per-service tfvars (for example `prometheus.tfvars`, `grafana/app.tfvars`, `jenkins/controller.tfvars`). |
| `~/.kube` | Kubernetes configs/contexts (when enabled) | Backed by `/mnt/eapp/home/.kube`; keep kubeconfigs out of the repo. |
| `.env` (repo root) | Baseline dev environment hints for automation | Defaults for `DOCKER_SWARM_CP`, `NPM_USERNAME`, `NPM_PASSWORD`; not for production secrets. |
| `proxmox.env` (repo root) | Proxmox credentials for password SSH to `proxmox.internal` | Handle carefully; this host currently uses root/password auth only. |

## Handling guidance

- Treat these paths as private; never commit contents to the repo.
- When adding new services, follow existing tfvars naming in `~/.tfvars` and update planning docs with the exact files created.
- Verify files exist before running pipelines (for example, `ls ~/.tfvars/<service>.tfvars`); capture proof in the relevant plan.
- Do not symlink repo paths (for example, `.tfvars/`) into `~/.tfvars`; keep tfvars files directly under `~/.tfvars` to avoid broken-link sync failures.
