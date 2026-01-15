# Docker Swarm

Source of truth for Swarm workflows, pipelines, Terraform state, and supporting automation. Pair this with [[Machines]] for host details and [[Secrets]] for credential locations.

## Control endpoints & state

- Repo path: `~/code/homelab` on every host (NFS from `truenas.internal`).
- Default Docker host: `ssh://swarm-cp-0.internal` (`DOCKER_SWARM_CP` in `.env`).
- Terraform backend: `~/.tfvars/minio.backend.hcl` (MinIO on `medusa.internal`).
- Compose-only stacks (MinIO backend + Renovate): run from `medusa.internal` at `docker/minio/` and `docker/renovate/`; ensure images support `linux/aarch64`.

## Application taxonomy & provider expectations
- **App + config** – multi-stage (for example, Jenkins controller/agent/config; Grafana app/config). Multiple pipelines/states.
- **App w/ inline config** – config rendered inside the module (for example, Prometheus). Single pipeline, single state.
- **App only** – single-shot services (for example, Dozzle, Graphite, Node Exporter). One pipeline/state.
- **Config only** – reserved for future config-only updates.
- Always confirm a first-class Terraform provider exists before custom Docker resources; record the provider choice in plans.

## Major feature workflow
1. **Scope & triggers** – Decide taxonomy; list touched dirs (`terraform/module/<service>`, `terraform/swarm/<service>[/<stage>]`, `terraform/swarm/<service>/<stage>/pipeline`, `docker/<service>`, Jenkins registry). Note tfvars/backend paths in `~/.tfvars`. Confirm provider availability.
2. **Create multi-stage plan** – `docs/planning/<service>-plan.md` with Stage 0–N checkboxes. Stage 0 must include tfvars/backend paths + existence checks, reference implementation, and pipeline/Jenkins surfaces to add/update. Include sanitized tfvars/backend snippets and commands you will run (`ls`, `cat`, etc.).
3. **Execute stage-by-stage** – Follow the plan; note scope changes in the doc before continuing.
4. **Validation & wrap-up** – Record commands/jobs run, outcomes, tfvars/backend proof (`ls ~/.tfvars && cat ~/.tfvars/<file>`), pending applies. Split **Agent tests** vs **Human tests**.

## Repository surfaces per Swarm service
- **Modules (`terraform/module/<service>`)** – Core Docker resources. Multi-stage services split into `app`/`config` (Grafana) or more (`jenkins/{controller,agent,config}`).
- **Stack entrypoints (`terraform/swarm/<service>`)** – Wire backends/providers/modules. Multi-stage keep per-stage dirs (`terraform/swarm/grafana/{app,config}`, `terraform/swarm/jenkins/{controller,agent,config}`).
- **Pipelines (`terraform/swarm/<service>/<stage>/pipeline/<stage>.sh`)** – Set `SERVICE_NAME`, `STAGE_NAME`, overrides, then source `pipeline/script/swarm_pipeline.sh`.
- **Jenkins wrappers (`terraform/swarm/<service>/<stage>/pipeline/<stage>.jenkins`)** – Declarative wrappers calling the bash scripts via `runShellPipeline`.
- **Jenkins job registry (`terraform/module/jenkins/config`)** – Add single-stage services to `local.single_stage_jobs`; multi-stage to `local.multi_stage_services`; keep Jenkins controller/agent/config in `local.jenkins_jobs`.
- **Pipeline helpers (`pipeline/script/`)** – Shared tooling (`env_check.sh`, `resolve_inputs.sh`, `swarm_pipeline.sh`, `terraform_exec.sh`, `terraform_output_filter.py`).
- **Planning docs (`docs/planning/<service>-plan.md`)** – Readiness gate for merges.

## TFVARS, provider_config, and backend contract
- `resolve_inputs.sh` order: CLI flags, script overrides (`DEFAULT_TFVARS_FILE`, `DEFAULT_BACKEND_FILE`), then `~/.tfvars/<basename>.tfvars`.
- Keep backend at `~/.tfvars/minio.backend.hcl` unless a plan overrides it; state keys usually `<service>.tfstate` or `jenkins-<stage>.tfstate`.
- Use `provider_config` map with Docker host + SSH opts; add nested providers only when needed (Grafana auth, Jenkins creds).
- Place secrets/env-specific coordinates in tfvars; encode static defaults as locals.
- Include sanitized tfvars/backend snippets in plans; create missing files under `~/.tfvars` (never defer to the user).
- Avoid symlinking repo paths (such as `.tfvars/`) into `~/.tfvars`; edit the files directly under `~/.tfvars` to prevent sync failures.

## Docker Swarm module conventions
- Prefix resources with the service name; set `com.docker.stack.namespace` + `com.docker.service` labels.
- Hardcode container images directly in `task_spec.container_spec` (`image = "repo:tag"` or digest) for Renovate visibility.
- Inline config services render YAML/JSON via `yamlencode`/`jsonencode` + `docker_config` resources.
- Reuse support modules like `module/healthcheck` when needed.

## Pipeline implementation details
- Bash entrypoints set `SERVICE_NAME`, `STAGE_NAME`, optional `ENTRYPOINT_RELATIVE`, `TERRAFORM_DIR`, `DEFAULT_TFVARS_FILE`, `PLAN_ARGS_EXTRA`, `APPLY_ARGS_EXTRA`, then source `swarm_pipeline.sh`.
- `swarm_pipeline.sh` runs env checks, resolves tfvars/backends, and performs `terraform init/plan/apply`, filtering output when Python is available.
- Use `PLAN/APPLY_ARGS_EXTRA` only when scoping is required; prefer separate `TERRAFORM_DIR` per stage.
- Implement `pipeline_pre_terraform()` when a stage needs prep (for example, Jenkins agent stage pulling controller outputs).
- Every bash script must have a `.jenkins` sibling with matching path/name.

## Jenkins job automation
- `terraform/module/jenkins/config/main.tf` provisions folders/jobs via `taiidani/jenkins`.
- Single-stage services → `local.single_stage_jobs`; multi-stage → `local.multi_stage_services`; Jenkins controller/agent/config remain in `local.jenkins_jobs`.
- New jobs must point to the `.jenkins` script path and include a short description.

## Docker Swarm service workflow
- **Container inspection**: `docker run -d`/`docker create` then `docker cp`/`docker exec`; remove containers after inspection.
- **Purge scripts**: Each service needs `docker/<service>/purge.sh`, wired to remove that service’s networks/volumes/configs/secrets. Document usage in planning docs/wiki.

## Resource links
- **Terraform providers**
  - [`kreuzwerker/docker`](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs)
  - [`grafana/grafana`](https://registry.terraform.io/providers/grafana/grafana/latest/docs)
  - [`taiidani/jenkins`](https://registry.terraform.io/providers/taiidani/jenkins/latest/docs)
  - [`Sander0542/nginxproxymanager`](https://registry.terraform.io/providers/Sander0542/nginxproxymanager/latest/docs)
- **Container images**
  - [`amir20/dozzle`](https://github.com/amir20/dozzle)
  - [`prom/node-exporter`](https://hub.docker.com/r/prom/node-exporter)
  - [`prom/prometheus`](https://hub.docker.com/r/prom/prometheus)
  - [`grafana/grafana`](https://hub.docker.com/r/grafana/grafana)
  - [`graphiteapp/graphite-statsd`](https://hub.docker.com/r/graphiteapp/graphite-statsd)
  - [`minio/minio`](https://min.io/docs/minio/container/index.html)
  - [`ghcr.io/nodadyoushutup/jenkins-controller`](docker/jenkins/controller)
  - [`ghcr.io/nodadyoushutup/jenkins-agent`](docker/jenkins/agent)
  - [`jc21/nginx-proxy-manager`](https://hub.docker.com/r/jc21/nginx-proxy-manager)
