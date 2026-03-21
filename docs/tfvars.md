# Terraform tfvars in this homelab repo

This repo keeps Terraform variable values outside git in a host-mounted tfvars directory. Terraform code stays in-repo; environment values (especially secrets) live under `/mnt/eapp/.tfvars`.

## Why this exists

- Keeps sensitive values out of git (`.gitignore` excludes `*.tfvars` and `*.tfvars.json`).
- Lets the same Terraform code run across stages/hosts with different values.
- Centralizes service configuration files (for example app/config/database tfvars and related sidecar files).

## Default location and overrides

Default tfvars home:

```text
/mnt/eapp/.tfvars
```

Resolution rules from pipeline scripts:

- `TFVARS_HOME_DIR` defaults to `${TFVARS_DIR:-/mnt/eapp/.tfvars}`.
- `TFVARS_DIR` is typically set in repo `.env` (see `.env.example`).
- `load_root_env.sh` sources `.env`, while preserving already-exported `TFVARS_DIR`, `TFVARS_HOME_DIR`, and `JENKINS_TFVARS_DIR` if they were set before invocation.

Jenkins-specific default directory:

```text
${JENKINS_TFVARS_DIR:-${TFVARS_DIR:-/mnt/eapp/.tfvars}/jenkins}
```

## Current directory structure (host example)

At the time of writing, `/mnt/eapp/.tfvars` is structured like this:

```text
/mnt/eapp/.tfvars/
  minio.backend.hcl
  alloy/
    app.tfvars
    config.alloy
  argocd/
    config.tfvars
  cloudflare/
    config.tfvars
  fortigate/
    config.tfvars
  grafana/
    app.tfvars
    config.tfvars
    database.tfvars
    grafana.ini
  harbor/
    app.tfvars
    config.tfvars
  jenkins/
    controller.tfvars
    agent.tfvars
    config.tfvars
  loki/
    app.tfvars
    config.yaml
  nginx-proxy-manager/
    app.tfvars
    config.tfvars
    database.tfvars
  prometheus/
    app.tfvars
    database.tfvars (legacy/optional; see notes below)
    prometheus.yaml
  proxmox/
    app.tfvars
    *.yaml
  talos/
    app.tfvars
    *-config-patch.yaml
  vault/
    app.tfvars
    config.tfvars
    .env
    init.json
  victoriametrics/
    app.tfvars
  <other service dirs>/
    app.tfvars
```

Notes:

- You may see `*.bak.*` files from manual backups.
- Companion files like `config.yaml`, `grafana.ini`, `service_account.json`, and cloud-init YAML are expected in some service folders.

## Naming conventions

Most service stages follow these filenames:

- App stage: `<service>/app.tfvars`
- Config stage: `<service>/config.tfvars`
- Database stage: `<service>/database.tfvars`

Examples used by current pipeline entrypoints:

- `terraform/swarm/nginx_proxy_manager/config/pipeline/config.sh` -> `/mnt/eapp/.tfvars/nginx-proxy-manager/config.tfvars`
- `terraform/remote/cloudflare/config/pipeline/config.sh` -> `/mnt/eapp/.tfvars/cloudflare/config.tfvars`
- `terraform/network/fortigate/config/pipeline/config.sh` -> `/mnt/eapp/.tfvars/fortigate/config.tfvars`

Special cases:

- Jenkins uses `/mnt/eapp/.tfvars/jenkins/{controller,agent,config}.tfvars`.
- Prometheus database stage prefers `/mnt/eapp/.tfvars/prometheus/database.tfvars`, but falls back to `/mnt/eapp/.tfvars/victoriametrics/app.tfvars` if missing.

## tfvars/backend lookup precedence

`swarm_pipeline.sh` delegates path resolution to `scripts/terraform/resolve_inputs.sh`.

TFVARS lookup order:

1. Explicit `--tfvars <path>` (or first positional arg).
2. `DEFAULT_TFVARS_FILE` from the stage pipeline script.
3. `TFVARS_HOME_DIR/${DEFAULT_TFVARS_BASENAME}.tfvars`.
4. First `*.tfvars` found at top level of `TFVARS_HOME_DIR`.
5. First `*.tfvars` found at top level of the Terraform working directory.

Backend lookup order:

1. Explicit `--backend <path>` (or second positional arg).
2. `DEFAULT_BACKEND_FILE` from the stage script.
3. First `*.backend.hcl` (or `backend.hcl`) at top level of `TFVARS_HOME_DIR`.

If either file cannot be resolved, pipeline execution fails before `terraform init`.

## How pipelines consume tfvars

The standard wrapper (`scripts/terraform/swarm_pipeline.sh`) runs:

- `terraform init -backend-config="<backend file>"`
- `terraform plan -var-file "<tfvars file>"`
- `terraform apply -var-file "<tfvars file>"`

It prints the resolved tfvars/backend paths before execution.

## Common usage

Default run (uses stage defaults):

```bash
terraform/swarm/nginx_proxy_manager/config/pipeline/config.sh
```

Override tfvars/backend explicitly:

```bash
terraform/swarm/nginx_proxy_manager/config/pipeline/config.sh \
  --tfvars /mnt/eapp/.tfvars/nginx-proxy-manager/config.tfvars \
  --backend /mnt/eapp/.tfvars/minio.backend.hcl
```

Positional form is also supported:

```bash
terraform/swarm/nginx_proxy_manager/config/pipeline/config.sh \
  /mnt/eapp/.tfvars/nginx-proxy-manager/config.tfvars \
  /mnt/eapp/.tfvars/minio.backend.hcl
```

## Adding a new service tfvars set

1. Create a service folder under `/mnt/eapp/.tfvars/<service>/`.
2. Add stage files (`app.tfvars`, `config.tfvars`, `database.tfvars`) as needed.
3. Wire `DEFAULT_TFVARS_FILE` (and backend default) in that stage's `pipeline/*.sh`.
4. Ensure Terraform variables are declared in the corresponding `variables.tf`.
5. Run the stage pipeline and confirm it resolves the intended files.

## Security and ops expectations

- Never commit tfvars or secret sidecar files.
- Keep permissions restrictive for secret-bearing files.
- Treat tfvars edits as infrastructure changes: update them in tandem with Terraform code.
- Per repo hard rules, new app endpoints must be represented in tfvars-driven Nginx Proxy Manager and Cloudflare config and applied through Terraform pipelines.
