# Jenkins Agent Image

This directory builds the custom inbound Jenkins agent image used by the Swarm
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
- `target_registry=harbor` or `target_registry=github`
- a required `version`

The workflow publishes a multi-arch image for both `linux/amd64` and
`linux/arm64`, which is required by the split Swarm Jenkins agent stages.
