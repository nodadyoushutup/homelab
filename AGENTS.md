# AGENTS

Use this as a directory to the source-of-truth docs agents need.

- Machine inventory (hosts, IPs, OS/arch, Docker versions, access/NFS notes): `docs/wiki/Machines.md`.
- Secrets, tfvars/backends, kube configs, env files: `docs/wiki/Secrets.md`.
- SSH CA machine onboarding (host/user cert trust, manual install): `docs/wiki/SSH-CA.md`.
- Docker Swarm workflow (taxonomy, planning stages, pipelines/Jenkins, tfvars/backends, purge scripts, resource links): `docs/wiki/Docker-Swarm.md`.
- Swarm node onboarding (manual worker/manager add, prerequisites, labels, validation): `docs/wiki/Swarm-Node-Onboarding.md`.
- Planning docs for active changes: `docs/planning/<service>-plan.md` (complete before merging).
- Repo path is `~/code/homelab` everywhere via NFS from `truenas.internal` (see Machines for export details).
- Compose-only stacks (MinIO backend + Renovate) run on `medusa.internal` under `docker/minio/` and `docker/renovate/`; images must support `linux/aarch64`.
- NFS root_squash note: running repo scripts directly via `sudo` can return “Permission denied”; pipe them into `sudo bash -s` or copy to `/tmp` first.
- Python note: use `python3` explicitly; no `python` shim is assumed across hosts.
