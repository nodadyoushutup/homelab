# Machines

This page catalogs the machines that make up the homelab and the default expectations for how Codex interacts with them.

## Machine map

| Hostname | IP address | Role | OS | Architecture | Docker Engine |
| --- | --- | --- | --- | --- | --- |
| nodadyoushutup.internal | 192.168.1.36 | local development / coding | Ubuntu 25.10 (questing) | linux/amd64 | unknown |
| medusa.internal | 192.168.1.34 | Docker Compose host (MinIO, Renovate) | Ubuntu 25.04 (plucky) | linux/aarch64 | 28.5.2 |
| truenas.internal | 192.168.1.100 | storage / NAS (TrueNAS) | TrueNAS SCALE Dragonfish-24.04.0 (Debian 12/bookworm base) | linux/amd64 | n/a |
| proxmox.internal | 192.168.1.10 | Proxmox hypervisor | Proxmox VE 8.2.2 (Debian 12/bookworm base) | linux/amd64 | n/a |
| swarm-cp-0.internal | 192.168.1.42 | Docker Swarm controller (role=controller) | Ubuntu 25.04 (plucky) | linux/aarch64 | 28.5.2 |
| swarm-wk-0.internal | 192.168.1.41 | Docker Swarm worker (role=cicd) | Ubuntu 25.04 (plucky) | linux/aarch64 | 28.4.0 |
| swarm-wk-1.internal | 192.168.1.40 | Docker Swarm worker (role=database) | Ubuntu 25.10 (questing) | linux/aarch64 | 28.5.2 |
| swarm-wk-2.internal | 192.168.1.39 | Docker Swarm worker (role=monitoring) | Ubuntu 25.04 (plucky) | linux/aarch64 | 28.4.0 |
| swarm-wk-3.internal | 192.168.1.38 | Docker Swarm worker (role=edge) | Ubuntu 25.04 (plucky) | linux/aarch64 | 28.4.0 |
| swarm-wk-4.internal | 192.168.1.37 | Docker Swarm worker (role=unassigned) | unknown | linux/aarch64 | unknown |

## Agent guidance (see AGENTS.md)

- Repository path is `~/code/homelab` on every machine via the NFS export from `truenas.internal`.
- Default Docker Swarm control endpoint is `ssh://swarm-cp-0.internal` (from `.env`/AGENTS).
- Compose-only stacks (MinIO backend + Renovate) run on `medusa.internal`; run Docker Compose commands there.
- Host-specific secrets/vars live under `~/.jenkins` and `~/.tfvars` (including `~/.tfvars/minio.backend.hcl`) per AGENTS instructions.
- This page is the source of truth for machine details; consult AGENTS.md for pipeline/tfvars/secrets handling when operating across hosts.

## Operational notes

1. Every machine assumes a primary `nodadyoushutup` user (uid 1000, gid 1000).
2. `nodadyoushutup.internal` is the development workstation where Codex runs local commands by default.
3. When work must happen on another host, run commands over SSH from the development machine or SSH into the target directly.
4. All machines mount the same NFS share at `~/code/homelab`, so code changes fan out everywhere; paths are consistent across hosts.
5. `medusa.internal` is the single Docker Compose host for MinIO (Terraform state backend) and Renovate; it is intentionally outside the Swarm.
6. Swarm nodes host all Terraform-managed workloads; pipelines target `swarm-cp-0.internal` as the Swarm controller endpoint.
7. `truenas.internal` exports the NFS share backing `~/code/homelab`; the source dataset lives at `/mnt/eapp/home/code`.
8. `proxmox.internal` currently uses root/password auth only—no `nodadyoushutup` user or SSH keys; expect minimal interaction for now.
9. `proxmox.env` at the repo root holds Proxmox credentials for password SSH when needed—treat it carefully.
10. TrueNAS NFS exports (eapp only; do not touch `epool/media`): `/mnt/eapp/home/code`, `/mnt/eapp/home/.tfvars`, `/mnt/eapp/home/.kube`, `/mnt/eapp/home/.jenkins`.
