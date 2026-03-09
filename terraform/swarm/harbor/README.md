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

- `terraform/swarm/harbor/app/pipeline/app.sh`
- `terraform/swarm/harbor/config/pipeline/config.sh`
