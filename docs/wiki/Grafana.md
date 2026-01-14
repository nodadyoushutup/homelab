# Grafana

End-to-end runbook for the Grafana Swarm stack that ships with both infrastructure (Docker provider) and configuration (Grafana provider) stages. Treat this guide as the authoritative reference once the plan in `docs/planning/grafana-plan.md` is complete.

## Overview

- **Service type:** App + config (Docker Swarm service + Grafana Terraform provider).
- **Purpose:** Visualize metrics scraped by Prometheus and emitted via Graphite (TrueNAS) or Prometheus (Node Exporter), shipping both the Node Exporter and TrueNAS folders of per-category dashboards alongside their managed data sources.
- **Key paths:** `terraform/module/grafana`, `terraform/module/grafana/config`, `terraform/swarm/grafana/{app,config}`, `pipeline/grafana/app.{sh,jenkins}`, `pipeline/grafana/config.{sh,jenkins}`.

## Prerequisites

1. Access to the Swarm manager over SSH (matches other apps—see `provider_config.docker`).
2. Remote backend credentials in `~/.tfvars/minio.backend.hcl`.
3. A populated `~/.tfvars/grafana/` directory with stage-specific tfvars files:
   - `app.tfvars` → `provider_config` containing both the Docker host (SSH URI + opts) and Grafana admin credentials. The Swarm service reads these values to configure secrets/env vars.
   - `config.tfvars` → `provider_config` (Grafana credentials/API token) plus top-level `datasources`, `dashboards`, and optional `folders` lists that feed the Grafana provider module. Split the structured inputs here instead of using the legacy `grafana_config_inputs` map.
4. Prometheus Swarm service reachable on the overlay network (defaults to `prometheus:9090`).

## TFVARS structure

`~/.tfvars/grafana/app.tfvars` (trimmed):

```hcl
provider_config = {
  docker = {
    host = "ssh://nodadyoushutup@192.168.1.22"
    ssh_opts = [...]
  }
  grafana = {
    url      = "http://grafana.internal:3000"
    username = "admin"
    password = "GrafanaAdminPass!"
  }
}
```

`~/.tfvars/grafana/config.tfvars` (trimmed):

```hcl
provider_config = {
  grafana = {
    url      = "http://grafana.internal:3000"
    username = "admin"
    password = "GrafanaAdminPass!"
  }
}

datasources = [
  {
    name       = "Prometheus"
    uid        = "prometheus"
    type       = "prometheus"
    url        = "http://prometheus:9090"
    is_default = true
    json_data  = { httpMethod = "POST" }
  },
  {
    name        = "Graphite"
    uid         = "graphite"
    type        = "graphite"
    url         = "http://swarm-cp-0.internal:8081"
    access_mode = "proxy"
    json_data = {
      graphiteVersion   = "1.1"
      tlsAuth           = false
      tlsAuthWithCACert = false
    }
  }
]

dashboards = [
  {
    name      = "TrueNAS Services & Network (override example)"
    file      = "truenas-services-network.json"
    folder    = "TrueNAS"
    uid       = "truenas-svc-net-override"
    overwrite = true
  }
]
```

> Store sensitive values (passwords, API tokens, backend credentials) outside Git. The tfvars file stays local per the guidance in `AGENTS.md`.

## Bash pipelines

Run whichever stage matches the change you’re rolling out—the app stage handles the Swarm resources, while the config stage manages Grafana provider resources once the container is healthy.

### App stage (`pipeline/grafana/app.sh`)

```bash
./pipeline/grafana/app.sh \
  --tfvars ~/.tfvars/grafana/app.tfvars \
  --backend ~/.tfvars/minio.backend.hcl
```

- Shared helpers validate the environment and resolve tfvars/backend paths.
- `terraform init` migrates the backend as needed.
- The stage runs from `terraform/swarm/grafana/app`, so the Terraform state only contains Swarm resources—no targeting needed.

### Config stage (`pipeline/grafana/config.sh`)

```bash
./pipeline/grafana/config.sh \
  --tfvars ~/.tfvars/grafana/config.tfvars \
  --backend ~/.tfvars/minio.backend.hcl
```

- Reuses the same helper flow for env/input checks.
- `terraform init` matches the app stage backend configuration.
- The dedicated `terraform/swarm/grafana/config` directory keeps Grafana provider resources in their own state file, so the stage plans/applies normally without manual targeting.

## Jenkins pipelines

- Job names: `grafana/app` and `grafana/config` (under the `grafana` folder).
- Script paths: `pipeline/grafana/app.jenkins` and `pipeline/grafana/config.jenkins`.
- Parameters: `TFVARS_FILE`, `BACKEND_FILE` (optional overrides).

Trigger the stage you need via Jenkins once tfvars/backend files are available on the agent. The job templates mirror the bash stages, so Terraform logs and helper output stay consistent regardless of entrypoint.

## Updating dashboards or data sources

1. Edit `~/.tfvars/grafana/config.tfvars`:
  - Adjust the `datasources` list to add/remove Prometheus, Graphite, or future integrations.
  - Append new dashboard objects to the `dashboards` list (or `folders` if you need extra folders). The module still honors the legacy `grafana_config_inputs` map, but new work should stick to the dedicated lists.
2. Rerun the config pipeline (bash or Jenkins). Terraform will detect diffs and update Grafana via the provider.
3. For ad-hoc testing, run `terraform plan` inside `terraform/swarm/grafana/config`, but stick to the pipelines for consistency.

## Node Exporter dashboard folder

- Folder UID: `node-exporter-fold`, managed by `terraform/module/grafana/config`.
- Dashboards live under `terraform/module/grafana/config/dashboards/node-exporter-*.json` and deploy automatically:
  1. **Node Exporter – Overview (`node-exporter-overview.json`, uid `node-exp-overview`):** nodes online/offline, uptime, network up state, clock/NTP status.
  2. **Node Exporter – CPU & Load (`node-exporter-cpu-load.json`, uid `node-exp-cpu`):** load averages, CPU busy %, context switches vs interrupts, CPU frequency/governor, pressure metrics.
  3. **Node Exporter – Memory & Swap (`node-exporter-memory.json`, uid `node-exp-mem`):** memory utilization, swap usage/activity, page cache/buffers, memory pressure, entropy.
  4. **Node Exporter – Storage & IO (`node-exporter-storage.json`, uid `node-exp-storage`):** filesystem utilization, disk throughput/latency, IO busy %, IO pressure wait/stall.
  5. **Node Exporter – Network & Transport (`node-exporter-network.json`, uid `node-exp-net`):** throughput, errors/drops, TCP/UDP health, conntrack/socket metrics, softnet stats, interface speed.
  6. **Node Exporter – Processes & Alerts (`node-exporter-processes.json`, uid `node-exp-proc`):** running vs blocked processes, file descriptor usage, critical OOM/fault alerts.
  7. **Node Exporter – Hardware & Sensors (`node-exporter-hardware.json`, uid `node-exp-hw`):** cooling device state, fan RPM, temperature panels beyond CPU-only metrics.
- Template variables: currently reuses the existing `node` multi-select (`label_values(up{job="node_exporter"}, instance)`) on every dashboard. Additional filters (device/filesystem/interface/sensor) are tracked as a future enhancement.
- Extending the folder follows the same workflow as TrueNAS: copy the closest JSON, add the new file to `local.default_dashboard_inputs`, and rerun the Grafana pipeline.

## TrueNAS dashboard folder

- Folder UID: `truenas-fold`, seeded automatically by the Grafana config module.
- Dashboard JSON files live under `terraform/module/grafana/config/dashboards/truenas-*.json` and deploy by default:
  1. **TrueNAS – CPU & Thermals (`truenas-cpu-thermals.json`, uid `truenas-cpu`):** `cpu.*`, `cpu*_cpuidle.*`, `cputemp.*`.
  2. **TrueNAS – Disk Throughput (`truenas-disk-throughput.json`, uid `truenas-disk-tput`):** `disk.*`, `disk_ops.*`, `disk_mops.*`, `disk_qops.*`.
  3. **TrueNAS – Disk Latency & Queues (`truenas-disk-latency.json`, uid `truenas-disk-lat`):** `disk_iotime.*`, `disk_await.*`, `disk_backlog.*`, `disk_busy.*`, `disk_util.*`.
  4. **TrueNAS – Disk SLA & Sizes (`truenas-disk-sla.json`, uid `truenas-disk-sla`):** `disk_svctm.*`, `disk_avgsz.*`.
  5. **TrueNAS – Extended Disk Ops (`truenas-disk-extended.json`, uid `truenas-disk-ext`):** all `disk_ext*` namespaces.
  6. **TrueNAS – SMART & ZFS (`truenas-smart-zfs.json`, uid `truenas-smart-zfs`):** `smart_log_smart.*`, `zfs.*`, `zfspool.*`.
  7. **TrueNAS – Services & Network (`truenas-services-network.json`, uid `truenas-svc-net`):** `system.*`, `mem.*`, `net.*`, `net_speed.*`, `nut_ix_dummy_ups.*`, `nfsd.*`.
  8. **TrueNAS – K3s & Diagnostics (`truenas-k3s-diagnostics.json`, uid `truenas-k3s`):** `k3s_stats.k3s_pod_stats.*` plus optional `netdata.*` helpers.
- Shared template variables (Graphite datasource `uid=graphite`):
  - `host` (constant) – pinned to `truenas.nas` on every dashboard.
  - `disk` – multi-select include-all list sourced from `truenas.nas.disk_ops.*` (disk-* and disk_ext dashboards).
  - `smart_serial` – multi-select of drive serials from `truenas.nas.smart_log_smart.disktemp.*` (SMART dashboard).
  - `zpool` – multi-select derived from `truenas.nas.zfspool.state_*` (SMART & ZFS dashboard).
  - `nfs_op` – optional filter across `truenas.nas.nfsd.proc[34].*` (Services & Network).
  - `k3s_pod` – multi-select for pod IDs under `k3s_stats.k3s_pod_stats.*` (K3s dashboard).
  - `diagnostic_target` – optional multi-select defaulting to `netdata.*` for the diagnostics panel.
- The former `graphite-truenas-overview` dashboard has been removed; update any tfvars to reference the specific `truenas-*` dashboards listed above.
- Terraform now ignores (and logs via plan output) any tfvars `dashboards` (or legacy `grafana_config_inputs.dashboards`) entries that still point at `graphite-truenas-overview.json`, so applies won’t fail while you clean up—just delete the legacy entry when convenient.
- Extending the folder:
  1. Generate the latest metric inventory (see below) to spot new namespaces.
  2. Add/edit the relevant JSON(s) using `aliasByNode`/`aliasSub` and reuse the variables above.
  3. If you introduce a brand new dashboard, add it to `default_dashboard_inputs` (or append it to the tfvars `dashboards` list) with the `TrueNAS` folder reference, then re-run `pipeline/grafana/config.sh`.

### Graphite inventory helper

- Script: `scripts/graphite_inventory.py`
  - Example: `python3 scripts/graphite_inventory.py --base-url http://swarm-cp-0:8081 --prefix truenas.nas --output /tmp/truenas_metrics.txt --verbose`.
  - Crawls `/metrics/find` breadth-first, records every leaf metric, and prints progress when `--verbose` / `--log-every` is set.
- Workflow:
  1. Copy the previous `/tmp/truenas_metrics.txt` before re-running so you can diff against the new output.
  2. Use `diff -u old new` (or a small Python helper) to highlight additions; new namespaces should translate into new dashboard coverage.
  3. Document notable changes in `docs/planning/truenas-graphite-dashboard-plan.md` so future contributors know when metrics appeared.

## Validation checklist

After each apply:

1. Verify the Swarm service is healthy (using the Docker host from `app.tfvars`):
   ```bash
   docker --host "${provider_config.docker.host}" service ps grafana --no-trunc
   ```
2. Hit the health endpoint:
   ```bash
   curl -sf http://grafana.internal:3000/api/health
   ```
   Expect `{"database":"ok","version":"11.x.x"}`.
3. Log in using the admin credentials defined in tfvars and confirm:
   - The Prometheus data source exists and passes the “Save & test” check.
   - Both `Node Exporter` and `TrueNAS` folders exist with their respective dashboards (overview + per-category splits).
4. Confirm users/dashboards survive restarts (volume mount `grafana-data` should persist on the Swarm node).

If anything fails, re-run the app stage from `terraform/swarm/grafana/app` (or via `pipeline/grafana/app.sh`) to remediate container-level issues before touching config.

## Rollback / destroy

To remove Grafana entirely, run a targeted destroy from the stack directory:

1. Destroy the Grafana provider resources so dashboards/data sources are cleaned up while the app is still reachable:
   ```bash
   cd terraform/swarm/grafana/config
   terraform destroy -var-file ~/.tfvars/grafana/config.tfvars
   ```
2. Destroy the Swarm resources:
   ```bash
   cd terraform/swarm/grafana/app
   terraform destroy -var-file ~/.tfvars/grafana/app.tfvars
   ```

Destroying both states removes the Swarm service, overlay, volume, secrets, data sources, and dashboards. Export dashboards before destroying if you need to retain history.

## Troubleshooting

- **Backend/file discovery errors:** ensure the tfvars path exists or pass `--tfvars` / `--backend` explicitly.
- **Grafana provider auth failures:** confirm the admin username/password in `provider_config.grafana` match what the Swarm service booted with; mismatches often happen after a password rotation without updating tfvars.
- **Network connectivity:** if Grafana cannot reach Prometheus, double-check that `attach_prometheus_network = true` and the Prometheus stack is publishing the expected service alias.
- **Dashboard UID conflicts:** keep `uid` values unique across dashboards; Terraform/Grafana will reject duplicates.

## References

- Grafana Terraform provider documentation: <https://registry.terraform.io/providers/grafana/grafana/latest/docs>
- Deployment plan with historical context: `docs/planning/grafana-plan.md`
- Helper scripts used by all pipelines: `pipeline/script/*.sh`
