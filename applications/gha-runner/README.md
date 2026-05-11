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
`runner-amd64` node and its native x86_64 builds plus KVM-backed Packer jobs.
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
- Terraform Swarm binds **`/dev/kvm`** from the **host** into both runner services (`terraform/swarm/gha-runner-amd64` and `terraform/swarm/gha-runner-arm64`). The image already installs QEMU/Packer via `scripts/install/packer.sh`; acceleration still requires a working KVM device on the **node** running the task.
- Default runner labels include **`build,kvm`** on both pools (see each `variables.tf`). Workflows that need hardware acceleration (for example **Packer** in `.github/workflows/packer_build_push.yml`) should use `runs-on` labels that include **`kvm`** so jobs land on these pools only after you confirm nodes are KVM-capable.
- Default **`github_runner_replicas`** is **2** per pool (override in tfvars if you want more). Apply both stacks so you get two AMD64 and two ARM64 runner tasks (subject to Swarm scheduling).

### Verify KVM on a Swarm node (run on the host, not in the runner)

Use this before relying on Packer with `accelerator=kvm`:

- **Device:** `test -c /dev/kvm && ls -l /dev/kvm` — should show a character device (commonly `root:kvm` `660`).
- **Kernel:** `lsmod | grep kvm` — expect `kvm` plus `kvm_intel` or `kvm_amd` on x86; on AArch64 servers often `kvm` alone when HW virtualization is available.
- **CPUs:** on x86, `grep -E 'vmx|svm' /proc/cpuinfo` — should match if virtualization is enabled in firmware.

If `/dev/kvm` is missing on the host, fix the host (BIOS/UEFI virtualization, nested virt for VMs, or correct kernel) before expecting KVM inside the runner container.

**ARM64 worker mix:** `gha-runner-arm64` defaults to placement on any `aarch64` worker. If some ARM nodes lack KVM (common on small SBCs), add a **node label** and extend `github_runner_constraints` in tfvars so Packer jobs only schedule on KVM-capable machines.

### After changing Terraform or the image

1. Build and push a new **`gha-runner`** image if you changed `Dockerfile` or `scripts/install/*` (multi-arch workflow).
2. Bump `github_runner_image` / registry reference for the ARM64 module if it pins an old tag.
3. **`terraform apply`** for `gha-runner-amd64` and `gha-runner-arm64`.
4. Confirm a running task: `docker service ps gha-runner-amd64` / `gha-runner-arm64`, then `docker exec` into a task container and run `test -r /dev/kvm && test -w /dev/kvm` (Swarm services use `user 0:0`, so root should open the device when the bind mount works).
