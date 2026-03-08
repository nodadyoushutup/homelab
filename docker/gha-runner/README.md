# Custom GitHub Actions Runner (Ubuntu 24.04)

This directory builds a self-hosted GitHub Actions runner image from `ubuntu:24.04`.

## What is configurable

- APT packages: `packages.apt`
- Python packages: `requirements.txt`
- Runner registration/settings: `.env` values (copy from `.env.example`)

## Quick start

```bash
cd docker/gha-runner
cp .env.example .env
# Fill GH_RUNNER_URL and GH_RUNNER_TOKEN
docker compose up -d --build
```

## Required env vars

- `GH_RUNNER_URL`: repo or org URL
- `GH_RUNNER_TOKEN`: registration token from GitHub

If either required value is unset (or set to `__SET_ME__`), the container stays in standby mode so the service can remain online before credentials are provided.

## Optional env vars

- `GH_RUNNER_NAME` (default: container hostname)
- `GH_RUNNER_LABELS` (default: `self-hosted,linux`)
- `GH_RUNNER_WORKDIR` (default: `_work`)
- `GH_RUNNER_EPHEMERAL` (default: `false`)
- `GH_RUNNER_DISABLEUPDATE` (default: `true`)
- `GH_RUNNER_REMOVE_TOKEN` (optional; used only for clean deregistration on exit)
- `RUNNER_VERSION` (build arg; default: `2.326.0`)

## Notes

- The token passed in `GH_RUNNER_TOKEN` is the one your frontend/API flow can inject at runtime.
- If you set `GH_RUNNER_EPHEMERAL=true`, the runner accepts a single job and exits.
