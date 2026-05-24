# Harbor Terraform Stages

This service is split into two Terraform stages:

- `app/`: Docker Swarm runtime resources for Harbor containers.
- `config/`: Harbor API resources (projects/users/members/robots/system settings).

## Operator config

Live tfvars live under **`.config/terraform/swarm/harbor/`**:

- **`app.tfvars`** — hostname, admin/DB passwords, host paths, placement. About a dozen values.
- **`config.tfvars`** — Harbor provider URL/credentials, projects, robots.

You do **not** hand-write component `env` files. The app pipeline runs **`harbor-prepare`** before `terraform apply`, which renders `harbor.yml` from `app.tfvars` and generates:

- `${harbor_install_path}/common/config/**` (nginx, core, registry, jobservice, trivy, …)
- `${harbor_data_path}/secret/**` (keys, certs)
- component env files under `common/config/*/env` (read by Terraform at apply time)

## First apply (recommended order)

1. Copy checked-in examples to your config dir (adjust paths/passwords):
   - `terraform/swarm/harbor/app/app.tfvars.example` → `.config/terraform/swarm/harbor/app.tfvars`
   - `terraform/swarm/harbor/config/config.tfvars.example` → `.config/terraform/swarm/harbor/config.tfvars`
2. Set **`harbor_admin_password`** in `app.tfvars` and the same value in **`config.tfvars`** `provider_config.harbor.password`.
3. Stop any overlapping standalone Harbor deployment before applying `app`.
4. Run **`pipelines/terraform/swarm/harbor/app.sh`** (prepare + Terraform apply).
5. Verify Harbor health (`/api/v2.0/ping`).
6. Run **`pipelines/terraform/swarm/harbor/config.sh`**.

## Runtime notes

Default host paths in examples are placeholders. Align `harbor_install_path`, `harbor_data_path`, and `harbor_log_path` with your Swarm node layout.

When Harbor is behind Nginx Proxy Manager or another HTTPS edge, set **`harbor_external_url`** in `app.tfvars` (for example `https://harbor.example.com`) so core/registry URLs match what clients use.

## Harbor projects (`config/` stage)

Harbor has flat projects (no nesting). This repo standardizes on a single **`homelab`** project so images are `harbor.example.com/homelab/<service>:<tag>`.

- Robot `project` permissions should use `namespace = "homelab"` for push/pull to those repositories.

## Pipeline entrypoints

- `pipelines/terraform/swarm/harbor/app.sh` — `scripts/harbor/prepare_from_tfvars.py` then Terraform app slice
- `pipelines/terraform/swarm/harbor/config.sh` — Harbor API config slice
