# AGENTS

This repo is docs-driven when live `docs/` exists. Treat archived material under
`.old/` as **out of scope**.

## Ignore `.old/` completely

**Do not read, update, restore, or cite anything under `<repo>/.old/`.**

- Never edit files in `.old/` (including archived docs, AGENTS backups, or old
  workflows).
- Never migrate content out of `.old/` unless the user explicitly asks to restore
  a named path.
- Prefer live `docs/`, code, and `.config/` as sources of truth. If live docs are
  missing, work from code and config — do not fall back to `.old/`.

## Hard cuts only — no legacy support

**When changing code, configs, or APIs in this repo, never keep backward
compatibility with the old shape.**

- Do **not** add fallbacks, dual-read paths, deprecation shims, or silent
  migration helpers.
- **Hard cut every change:** remove the old path, update callers in the same
  change, and state what operators must update if the edit is breaking.

## Do not add `*.tfvars.example` files

**Do not create, restore, or expand checked-in `*.tfvars.example`** unless the
user explicitly asks. Live operator config belongs under
`<repo>/.config/terraform/**`.

## Config

- Tfvars live under `<repo>/.config/terraform/**` (mirroring
  `terraform/components/`).
- Docker/local dotenv lives under `<repo>/.config/docker/`.
- Pipelines use `scripts/terraform/load_root_env.sh`.
- Per-slice tfvars are self-contained; each slice pipeline passes **only** that
  slice’s `-var-file`, with two intentional exceptions, both managed by the
  homelab-config web app:
  - the shared NFS catalog (`terraform/nfs` -> `.config/terraform/nfs.tfvars`);
    consumer slices that mount NFS pass `nfs.tfvars` as an extra `-var-file` and
    select a share via `nfs_share`.
  - provider config under `terraform/providers/<app>` ->
    `.config/terraform/providers/<app>.tfvars` (one file per app/provider). The
    consuming slice passes its `providers/<app>.tfvars` as an extra `-var-file`:
    - the Proxmox slice feeds `var.proxmox` from `providers/proxmox.tfvars`.
    - every Swarm slice feeds `var.docker_providers` + `var.registry_auths` from
      the shared `providers/docker.tfvars` and selects an entry via
      `docker_machine`. `docker_providers` is fully derived (swarm-node entries
      from `docker/swarm.tfvars`, plus non-swarm hosts from
      `docker/extra_hosts.yaml`); only `registry_auths` is edited in that file.
    - each remaining provider `config/` slice feeds a single `var.<app>` login
      object from its own `providers/<app>.tfvars`: `cloudflare`, `grafana`,
      `jenkins`, `argocd`, `fortigate`, `nginx_proxy_manager`, and `vault`.
      Provider login lives in the shared file only; desired-state config (DNS
      records, dashboards, jobs, firewall policy, proxy hosts, KV secrets) stays
      in that slice's own `config.tfvars`.

  No other shared swarm/dns/amd64/arm64 bundles.
- Container image tags are hardcoded literals on resources in `main.tf` — tag
  only, **no** digest/`@sha256:...`, and **not** a variable or local (Renovate
  must see the literal).

## Cursor / MCP

- Use Cursor shell and local file tools for repo filesystem work.
- Homelab MCP servers are configured in project `.cursor/mcp.json`.
- **`mcp_agentmemory`** is user-global in `~/.cursor/mcp.json`.
