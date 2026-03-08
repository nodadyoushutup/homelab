# Prometheus

Prometheus runs as a Docker Swarm service (single replica on a controller-labeled node) and scrapes the Node Exporter instances we deployed earlier. Terraform manages both the service definition and the rendered `prometheus.yml` so scrape targets stay version-controlled.

## Prerequisites

- MinIO/S3 backend config at `~/.tfvars/minio.backend.hcl`.
- `~/.tfvars/prometheus/app.tfvars` containing the Docker provider config plus Prometheus settings. Example:

```hcl
provider_config = {
  docker = {
    host = "ssh://nodadyoushutup@192.168.1.22"
    ssh_opts = [
      "-o", "StrictHostKeyChecking=no",
      "-o", "UserKnownHostsFile=/dev/null",
      "-i", "~/.ssh/id_rsa"
    ]
  }
}

```
Terraform renders the Docker config from `terraform/docker/prometheus/app/prometheus.yaml`.

## Pipelines

### Bash deployment (`terraform/docker/prometheus/app/pipeline/app.sh`)

```bash
cd /path/to/homelab
./terraform/docker/prometheus/app/pipeline/app.sh \
  --tfvars ~/.tfvars/prometheus/app.tfvars \
  --backend ~/.tfvars/minio.backend.hcl
```

- Shared helpers verify Terraform availability and resolve input paths.
- `terraform init/plan/apply` runs against `terraform/docker/prometheus/app`, updating the service, network, volume definitions, and the rendered Docker config from `terraform/docker/prometheus/app/prometheus.yaml` in a single pass.

### Jenkins deployment (`prometheus`)

1. Trigger the `prometheus` job on the Jenkins controller.
2. Override `TFVARS_FILE` / `BACKEND_FILE` only if the defaults differ; the pipeline mirrors the bash script (Env Check → Resolve Inputs → Init → Plan → Apply) and emits identical Terraform logs.

### Validation checklist

- `docker service ls | grep prometheus` shows `Replicated: 1/1`.
- `docker service ps prometheus --no-trunc` confirms the task is running on a controller-labeled node.
- `curl http://swarm-cp-0.internal:9090/targets` (or via ingress IP) lists all Node Exporter targets as `UP`.
- `curl -X POST http://swarm-cp-0.internal:9090/-/reload` reloads config without redeploying (thanks to `--web.enable-lifecycle`).

## Editing scrape configs

1. Update target entries in `terraform/docker/prometheus/app/prometheus.yaml` if nodes change.
2. Re-run the Prometheus pipeline (bash or Jenkins). Terraform detects the config change, uploads a new Docker config, and rolling-updates the service.
3. Use `curl http://<host>:9090/-/config` or the UI to verify changes.

## Changing ports or persistence

- To adjust the Prometheus web port, edit `endpoint_spec.ports` in `terraform/docker/prometheus/app/main.tf`.
- To change TSDB retention or flags, edit the `args` list in the same file.
- Re-run the pipeline to roll out changes; remember to update firewalls and any load balancers.

## Follow-up ideas

- Introduce Alertmanager and/or Grafana using the same Terraform/pipeline pattern for a full observability suite.
- Parameterize the node constraint or published port via module variables if future environments differ.
- Consider adding additional scrape jobs as separate sections in `prometheus.yaml` as your observability stack grows.
