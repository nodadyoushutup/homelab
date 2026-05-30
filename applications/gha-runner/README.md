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
  - `target_registry=github` for GHCR or `target_registry=zot` for Zot
- Workflow publishes:
  - GHCR: `ghcr.io/<owner>/gha-runner:<version>` and `:latest`
  - Zot: `zot.nodadyoushutup.com/gha-runner:<version>` and `:latest`

For Terraform deployment, pin the runner image tag in each pool’s `locals.tf` (`local.runner_image`; use an exact published tag, not `latest`).

The runner pools are deployed as **standalone `docker_container` resources** on dedicated pool
hosts (AMD64 and ARM64), each with `/dev/kvm` passed through via the Docker **`devices`**
block so QEMU/Packer get real device cgroup permissions (unlike Swarm services). In this
repo, the ARM64 pool is managed from `terraform/components/runners/gha-runner-arm64/app` and the AMD64
pool from `terraform/components/runners/gha-runner-amd64/app`. Pool Docker SSH targets live in
`.config/terraform/components/runners/amd64.tfvars` and `.config/terraform/components/runners/arm64.tfvars`
(shared per arch with Jenkins agent pools; Swarm stacks use
`.config/terraform/components/swarm/swarm.tfvars`).

The Docker image publish workflow fans direct image builds out to those native runner pools
in parallel, then publishes the final multi-arch manifest tags after both native arch images
are available.

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
- `RUNNER_VERSION` (build arg; default: `2.334.0`)

## Notes

- On container shutdown, the entrypoint deregisters the runner using a remove token **minted via `GH_RUNNER_ACCESS_TOKEN`** when that token is set (no separate remove-token env is required).
- `GH_RUNNER_TOKEN` is a single-use registration token; for replicated services use `GH_RUNNER_ACCESS_TOKEN` to mint fresh tokens per task startup.
- If you set `GH_RUNNER_EPHEMERAL=true`, the runner accepts a single job and exits.
- Local compose mounts `/var/run/docker.sock` and runs as root so Docker Buildx/QEMU actions can access the host daemon.
- **Pool host + nested `docker run -v $PWD`**: Runner containers only see the host engine via `docker.sock`; the checkout under `_work` is **not** on the engine host, so nested builds that bind-mount `$PWD` see an empty path unless the job uses a host-visible directory. Both Terraform stacks bind-mount `engine_visible_build_path` (default `/var/lib/gha-runner-engine-build`) at the same absolute path and set `GHA_ENGINE_BUILD_TMP_PARENT` on the **container**. **Create that directory on the pool host** before apply (`sudo mkdir -p` on the host targeted by `provider_config.docker.host`). The entrypoint runs `mkdir -p` under that mount for job subdirs once the bind succeeds.
- Terraform provisions **`docker_container`** with **`devices { host_path = "/dev/kvm" ... }`** and **`group_add = ["kvm"]`** on each pool. The image installs QEMU/Packer via `scripts/install/packer.sh`; acceleration still requires a working KVM device on **that host**.
- **Swarm services cannot reliably grant `/dev/kvm` in the device cgroup** ([moby/moby#24865](https://github.com/moby/moby/issues/24865)); bind-mounting the node alone is not enough for QEMU. These runner pools therefore use **standalone containers** on the pool host’s Docker engine, not Swarm services, when KVM matters.
- Default runner labels include **`build,kvm`** on both pools (see each `variables.tf`). Workflows that need hardware acceleration (for example **Packer** in `.github/workflows/packer_build_push.yml`) should use `runs-on` labels that include **`kvm`** so jobs land on these pools only after you confirm the **pool host** is KVM-capable.
- **`replicas`** is the number of parallel runner containers on **that pool host** (set in each pool’s `app.tfvars`). Apply both stacks so you get the intended AMD64 and ARM64 capacity.

### Verify KVM on the pool host (run on the host, not in the runner)

Use this before relying on Packer with `accelerator=kvm`:

- **Device:** `test -c /dev/kvm && ls -l /dev/kvm` — should show a character device (commonly `root:kvm` `660`).
- **Kernel:** `lsmod | grep kvm` — expect `kvm` plus `kvm_intel` or `kvm_amd` on x86; on AArch64 servers often `kvm` alone when HW virtualization is available.
- **CPUs:** on x86, `grep -E 'vmx|svm' /proc/cpuinfo` — should match if virtualization is enabled in firmware.

If `/dev/kvm` is missing on the host, fix the host (BIOS/UEFI virtualization, nested virt for VMs, or correct kernel) before expecting KVM inside the runner container.

**ARM64 pool host choice:** point `swarm_docker_provider_config.docker.host` in `.config/terraform/components/runners/arm64.tfvars` at an AArch64 machine that actually exposes `/dev/kvm` if you expect Packer with `-accel kvm`. Small SBCs often omit KVM; pick another ARM host there if needed.

### After changing Terraform or the image

1. Build and push a new **`gha-runner`** image if you changed `Dockerfile` or `scripts/install/*` (multi-arch workflow).
2. Bump `image` in `terraform/components/runners/gha-runner-amd64/app/variables.tf` (or override in `.config/terraform/components/runners/gha-runner-amd64/app.tfvars`) if you need a new tag; same for ARM64.
3. **`terraform apply`** for `gha-runner-amd64` and `gha-runner-arm64`.
4. Confirm running containers on each pool host, for example `docker ps --filter name=homelab-gha-runner-amd64` (names include a numeric suffix). Validate KVM with `docker exec <container> dd if=/dev/kvm of=/dev/null count=0` when the pool host passes the device through correctly.
