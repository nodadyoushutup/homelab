# Graphite

Graphite (Carbon cache + Graphite-web + bundled StatsD) currently runs as a **minimal app-only** Docker Swarm stack. Terraform provisions the network, persistent volume, and Docker service; the container uses upstream defaults (no custom configs or secrets yet).

## Prerequisites

- Remote backend definition at `~/.tfvars/minio.backend.hcl`.
- `~/.tfvars/graphite.tfvars` containing only the Docker provider map. No additional values are required while the service runs with baked-in defaults.

```hcl
provider_config = {
  docker = {
    host = "ssh://nodadyoushutup@swarm-cp-0.internal"
    ssh_opts = [
      "-o", "StrictHostKeyChecking=no",
      "-i", "~/.ssh/id_ed25519"
    ]
  }
}

```

## Deploy via bash pipeline

```bash
cd /home/nodadyoushutup/code/homelab
./terraform/swarm/graphite/app/pipeline/app.sh \
  --tfvars ~/.tfvars/graphite.tfvars \
  --backend ~/.tfvars/minio.backend.hcl
```

Pipeline stages:
1. Environment + input resolution through `scripts/pipeline/*.sh`.
2. `terraform init` with the MinIO backend.
3. Full-stack `terraform plan` + `apply` (single module, no targeting needed).

Set `TF_CLI_ARGS_plan` or `TF_LOG` before running if you need extra Terraform flags.

## Deploy via Jenkins

1. Open the `graphite` job under the Jenkins root (script path `terraform/swarm/graphite/app/pipeline/app.jenkins`).
2. Override `TFVARS_FILE` / `BACKEND_FILE` only if the defaults (`~/.tfvars/graphite.tfvars`, `~/.tfvars/minio.backend.hcl`) differ.
3. Build the job; stages mirror the bash script (Env Check → Resolve Inputs → Init → Stack Plan/Apply).

The Jenkins job template matches other Swarm services (log retention, GitHub metadata, concurrency guard).

## Managing configuration

Configuration templating is deferred for the MVP deployment. Graphite runs with the defaults embedded in the upstream container image. Custom retention rules, StatsD overrides, or admin bootstrap scripts are not currently managed via Terraform.

## Validation checklist

- `docker service ls | grep graphite` shows `1/1` replicas on a monitoring node.
- `curl http://<ingress-host>:8081/` loads the Graphite UI; use the default credentials shipped with the image (or create an admin manually once the container is up).
- Send a test metric: `echo "swarm.test.metric 1 $(date +%s)" | nc -w1 127.0.0.1 2003` from a node; it should appear in the UI shortly (or query via `/render` API).
- StatsD UDP check: `echo "teststatsd:1|c" | nc -w1 -u <ingress-host> 8125` and confirm counters increase.
## Troubleshooting

- `docker service logs graphite --tail 100` surfaces gunicorn/nginx output; combine `docker service ps graphite` with `docker logs <task-id>` for detailed carbon-cache/StatsD traces.
- Keep an eye on volume size (`graphite-data`) to ensure whisper retention fits available disk; adjust settings manually inside the container if the cluster runs out of space (full Terraform-driven config is TBD).
