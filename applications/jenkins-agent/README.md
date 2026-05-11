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

## KVM and Packer on Swarm

Swarm stacks **`terraform/swarm/jenkins-agent-amd64`** and **`terraform/swarm/jenkins-agent-arm64`** bind-mount **`/dev/kvm`** from each scheduled node into the agent container (same idea as the GHA runner services). The image installs QEMU/Packer via `automation_tooling.sh`; the **`jenkins`** user is added to the **`kvm`** group in the Dockerfile so jobs can open the device when it is `root:kvm` on the host.

Requirements on the **node**: a working **`/dev/kvm`** and loaded **`kvm`** kernel support (see `applications/gha-runner/README.md` host checks). If a node has no KVM device, the bind mount can prevent the service from starting—fix the host or temporarily remove the mount in Terraform.

Give Packer (or other) jobs an agent label that matches **KVM-capable** nodes only, for example the Packer Jenkinsfile default uses `swarm && amd64 && kvm`; ensure JCasC agent **`labelString`** includes **`kvm`** where appropriate.
