# Node Exporter

Node Exporter runs as a global Docker Swarm service so Prometheus can scrape hardware and OS metrics from every node. Its Terraform, bash, and Jenkins pipelines mirror the Dozzle deployment so operators can reuse the same workflow muscle memory.

## Prerequisites

- A Swarm manager node with access to the MinIO/S3 backend defined in `~/.tfvars/minio.backend.hcl`.
- A TFVARS file at `~/.tfvars/node_exporter.tfvars` that provides the Docker provider connection (same schema as Dozzle/Jenkins). Example:

```hcl
provider_config = {
  docker = {
    host     = "ssh://user@manager.example.com"
    ssh_opts = ["-o", "StrictHostKeyChecking=no"]
  }
}

dns_nameservers = [
  "192.168.1.1",
  "1.1.1.1",
  "8.8.8.8",
]

placement = {
  constraints = []
  platforms = [
    {
      os           = "linux"
      architecture = "aarch64"
    }
  ]
}
```

- Optional: omit `dns_nameservers` or `placement` to let Docker defaults apply; the rest of the service config is set in `terraform/module/node_exporter/main.tf`.

- Prometheus (or another scraper) reachable on the published ingress port (default `9100`).

## Deploy via bash pipeline

```bash
cd /path/to/homelab
./terraform/swarm/node_exporter/app/pipeline/app.sh \
  --tfvars ~/.tfvars/node_exporter.tfvars \
  --backend ~/.tfvars/minio.backend.hcl
```

What happens:
1. Helper scripts verify Terraform/python availability and resolve tfvars/backend paths.
2. Terraform initializes the `terraform/swarm/node_exporter/app` stack, planning + applying the `module.node_exporter_app`.
3. A `node-exporter` overlay network plus a global `docker_service` is created; each node binds `/proc`, `/sys`, `/` read-only and exposes `:9100`.

### Validation checklist

- `docker service ls | grep node-exporter` shows `Replicated: global`.
- `docker service ps node-exporter --no-trunc` reports one running task per node.
- `curl -s http://<node-ip>:9100/metrics | head` returns Prometheus metrics.

## Deploy via Jenkins

1. In Jenkins, navigate to the `node_exporter` job (script path `terraform/swarm/node_exporter/app/pipeline/app.jenkins`).
2. Kick off a build; optionally override `TFVARS_FILE` or `BACKEND_FILE` parameters to point at non-default locations.
3. The pipeline stages mirror the bash script (Env Check → Resolve Inputs → Init → Plan → Apply) and emit the same Terraform logs.

## Prometheus scraping

- Default target: `http://<swarm-ingress-ip>:9100/metrics` (ingress publishes `9100` on every node).
- Sample static scrape config:

```yaml
- job_name: node_exporter
  static_configs:
    - targets:
        - manager01:9100
        - worker01:9100
        - worker02:9100
```

Adjust to match however you route traffic (load balancer, DNS, etc.).

## Changing the published port

- Edit `terraform/module/node_exporter/main.tf`:
  - Update `endpoint_spec.ports[0].target_port` if the container should listen elsewhere.
  - Update `endpoint_spec.ports[0].published_port` to change the exposed ingress port.
- Re-run the pipeline to roll out the new mapping, then update Prometheus/firewall rules accordingly.

## Follow-up ideas

- The Dozzle and Node Exporter modules are almost identical aside from container specs. A shared module or locals file could reduce duplication if more Swarm services follow this pattern.
- Consider parameterizing the published port/labels via module variables if future services require per-environment tweaks without editing Terraform code.
