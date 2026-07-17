# Jenkins Agent Image

This directory builds the custom inbound Jenkins agent image used by the homelab
Jenkins agent pools.

The Dockerfile uses `scripts/install/automation_tooling.sh` as the shared
source-of-truth for the common automation toolchain so the Jenkins agent stays
aligned with the GitHub Actions runner image and the Packer base image.

## Shared tooling

The shared tooling bundle installs:

- base packages from `scripts/install/packages.sh`
- Docker CLI
- Terraform
- Ansible
- `kubectl`
- `k9s`
- Packer and its QEMU/KVM dependencies
- MinIO client (`mc`)

## Publish workflow

Build and publish this image with `.github/workflows/docker_build_push.yml`
using:

- `build_target=jenkins-agent`
- `target_registry=github` or `target_registry=zot`
- a required `version`

The workflow publishes a multi-arch image for both `linux/amd64` and
`linux/arm64`.

## Pool deployment (not Swarm)

Agent pools are **`docker_container`** resources on dedicated pool hosts (same
pattern as `gha-runner-*`), not Swarm services:

| Pool | Terraform | Site tfvars |
| --- | --- | --- |
| ARM64 | `terraform/components/swarm/jenkins-agent-arm64/app` | `.config/terraform/components/swarm/jenkins-agent-arm64/app.tfvars` |
| AMD64 | `terraform/components/swarm/jenkins-agent-amd64/app` | `.config/terraform/components/swarm/jenkins-agent-amd64/app.tfvars` |

Terraform provisions **`devices { host_path = "/dev/kvm" }`** and
**`group_add = ["kvm"]`** so Packer/QEMU can use hardware acceleration.
Swarm bind-mounts alone are not sufficient ([moby/moby#24865](https://github.com/moby/moby/issues/24865)).

Agents reach the controller via published ports on the Swarm ingress host
(`JENKINS_URL`, `JENKINS_TUNNEL` in each pool’s `app.tfvars`), not the internal
`jenkins` overlay DNS name.

## KVM on the pool host

Requirements on the **pool host**: working **`/dev/kvm`** and loaded **`kvm`**
kernel modules (see `applications/gha-runner/README.md` host checks).

Give Packer jobs a label that matches KVM-capable agents (for example
`swarm && amd64 && kvm` in the Packer Jenkinsfile).
