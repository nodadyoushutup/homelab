# Custom GitHub Actions Runner (Ubuntu 24.04)

This directory builds a self-hosted GitHub Actions runner image from `ubuntu:24.04`.
The Dockerfile uses the shared automation tooling bundle at
`scripts/install/automation_tooling.sh` as source-of-truth for the common
infra/CI toolchain.

## What is configurable

- Shared infra/CI tooling:
  `scripts/install/automation_tooling.sh`
  - base packages from `scripts/install/packages.sh`
  - Docker CLI, Terraform, Ansible, `kubectl`, `k9s`, Packer, and MinIO client
- Runner-specific OS/Python prereqs: `applications/gha-runner/Dockerfile`
- Python packages: `requirements.txt`
- Runner registration/settings: `.env` values (copy from `.env.example`)

## Quick start

```bash
cd applications/gha-runner
cp .env.example .env
# Fill GH_RUNNER_URL and either GH_RUNNER_ACCESS_TOKEN (recommended) or GH_RUNNER_TOKEN
docker compose up -d --build
```

## GHCR publish workflow

- Use GitHub Actions workflow: `.github/workflows/docker_build_push.yml`
- Trigger `workflow_dispatch` with:
  - `build_target=gha-runner`
  - required input `version`
  - `target_registry=github` for GHCR or `target_registry=harbor` for Harbor
- Workflow publishes:
  - GHCR: `ghcr.io/<owner>/gha-runner:<version>` and `:latest`
  - Harbor:
    `harbor.nodadyoushutup.com/gha-runner/gha-runner:<version>` and `:latest`

For Swarm/Terraform deployment, set `github_runner_image` to the exact published tag (recommended), not `latest`.

The Swarm deployment supports separate ARM64 and AMD64 runner pools from the
same multi-arch image. In this repo, the ARM64 pool is managed from
`terraform/swarm/gha-runner-arm64/app` for the ARM swarm workers, while the
AMD64 pool is managed from `terraform/swarm/gha-runner-amd64/app` for the
`development` node and its native x86_64 builds plus KVM-backed Packer jobs.
The Docker image publish workflow now fans direct image builds out to those
native runner pools in parallel, then publishes the final multi-arch manifest
tags after both native arch images are available.

## Required env vars

- `GH_RUNNER_URL`: repo or org URL
- one of:
  - `GH_RUNNER_ACCESS_TOKEN` (recommended): PAT/App token that can call GitHub runner token APIs
  - `GH_RUNNER_TOKEN`: one-time registration token from GitHub

If `GH_RUNNER_URL` is unset, or no usable runner registration token can be resolved, the container stays in standby mode so the service can remain online before credentials are provided.

## Optional env vars

- `GH_RUNNER_NAME` (default: container hostname)
- `GH_RUNNER_LABELS` (default: `self-hosted,linux`)
- `GH_RUNNER_WORKDIR` (default: `_work`)
- `GH_RUNNER_EPHEMERAL` (default: `false`)
- `GH_RUNNER_DISABLEUPDATE` (default: `true`)
- `GH_RUNNER_REMOVE_TOKEN` (optional; if omitted and `GH_RUNNER_ACCESS_TOKEN` is set, a remove token is minted automatically on shutdown)
- `RUNNER_VERSION` (build arg; default: `2.332.0`)

## Notes

- `GH_RUNNER_TOKEN` is a single-use registration token; for replicated services use `GH_RUNNER_ACCESS_TOKEN` to mint fresh tokens per task startup.
- If you set `GH_RUNNER_EPHEMERAL=true`, the runner accepts a single job and exits.
- Local compose mounts `/var/run/docker.sock` and runs as root so Docker Buildx/QEMU actions can access the host daemon.
- The Terraform Swarm stage can advertise different custom labels per runner
  pool, such as `arm64` for the ARM workers and `amd64,build,kvm` for the
  x86_64 development node.
