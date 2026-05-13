# Harbor Terraform Stages

This service is split into two Terraform stages:

- `app/`: Docker Swarm runtime resources for Harbor containers.
- `config/`: Harbor API resources (projects/users/members/robots/system settings).

## Runtime Notes

The `app` stage is intentionally aligned with the existing manual Harbor layout:

- Host install path: `/mnt/eapp/harbor-manual/harbor`
- Host data path: `/mnt/eapp/harbor-manual/data`
- Host log path: `/mnt/eapp/harbor-manual/log`

These are configurable via tfvars.

## Harbor projects (`config/` stage)

Harbor has flat projects (no nesting). This repo standardizes on a single **`homelab`** project so images are `harbor.example.com/homelab/<service>:<tag>` instead of duplicating the service name as both project and repository.

- After changing `projects` in tfvars, run `scripts/misc/harbor_migrate_to_homelab_project.sh` if you need to copy existing tags out of older projects before Terraform deletes them.
- Robot `project` permissions should use `namespace = "homelab"` for push/pull to those repositories.

### Optional two-phase wipe (config tfvars outside the repo)

To let Terraform **destroy** all managed Harbor projects/robots before re-applying a clean layout: point `projects` and `robot_accounts` at **empty lists**, set `delete_default_library = false` for the wipe apply, run `apply`, then restore definitions from your backup tfvars (for example `config.tfvars.phase2-backup-*` under the same config directory) and apply again.

## First Apply (Recommended Order)

1. Prepare tfvars files from examples:
   - `terraform/swarm/harbor/app/app.tfvars.example`
   - `terraform/swarm/harbor/config/config.tfvars.example`
2. Ensure env files for Harbor components are available on the Terraform runner, or set explicit `env` maps in app tfvars.
3. Stop the current standalone compose Harbor deployment before applying `app` (ports/data paths overlap).
4. Apply `app` stage.
5. Verify Harbor health (`/api/v2.0/ping`).
6. Apply `config` stage.

## Pipeline Entrypoints

- `pipelines/terraform/swarm/harbor/app.sh`
- `pipelines/terraform/swarm/harbor/config.sh`
