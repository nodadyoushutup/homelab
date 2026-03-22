# Packer: Ubuntu 24.04 + Docker + KDE (amd64 + arm64)

This directory contains a minimal Packer build that:

- starts from the official Ubuntu 24.04 cloud image (`noble`)
- uses a temporary `packer` SSH user/key for provisioning only
- sets `nodadyoushutup` as UID/GID `1000:1000` directly in cloud-init
- uploads and runs `scripts/install/packages.sh` (base packages)
- uploads and runs `scripts/install/docker.sh`
- uploads and runs `scripts/install/packer.sh`
- uploads and runs `scripts/install/kde.sh`
- runs a cleanup script that removes temporary SSH/provisioning access

## Prerequisites

- `packer`
- `qemu-system-x86_64`
- `qemu-system-aarch64`
- `qemu-img`
- KVM support for best performance when selecting `accelerator=kvm` (`/dev/kvm` must be available to the runner/container)

## Build

From repo root:

```bash
./packer/build.sh --version 0.0.1
```

By default, KDE is not installed (headless image). To enable KDE:

```bash
./packer/build.sh --version 0.0.3 --kde_profile=desktop
```

Build with GHA-equivalent selectors:

```bash
./packer/build.sh --version 0.0.3 \
  --target webserver \
  --build_arch both \
  --amd64_accelerator kvm \
  --arm64_accelerator kvm
```

Build only one architecture:

```bash
./packer/build.sh --version 0.0.3 --build_arch amd64 --amd64_accelerator kvm
./packer/build.sh --version 0.0.3 --build_arch arm64 --arm64_accelerator tcg
```

Enable verbose Packer debug logs for troubleshooting:

```bash
./packer/build.sh --version 0.0.3 --build_arch arm64 --arm64_accelerator kvm --packer_log
```

Upload-only (existing built artifacts for a version):

```bash
./packer/upload.sh 0.0.1 --target webserver --build_arch both
./packer/upload.sh 0.0.1 --build_arch amd64
```

## Output

Artifacts are written to:

```text
packer/output/ubuntu-24.04-ndysu/0.0.1/amd64/ubuntu-24.04-ndysu-0.0.1-amd64.qcow2
packer/output/ubuntu-24.04-ndysu/0.0.1/arm64/ubuntu-24.04-ndysu-0.0.1-arm64.qcow2
```

Run log is written to:

```text
packer/logs/build-<utc-timestamp>-v0.0.1.log
```

Artifact upload destinations:

```text
https://webserver.image.nodadyoushutup.com/ubuntu-24.04-ndysu-0.0.1-amd64.qcow2
https://webserver.image.nodadyoushutup.com/ubuntu-24.04-ndysu-0.0.1-arm64.qcow2
```

If the HTTPS proxy returns `413`, `build.sh` retries each artifact upload directly to:

```text
http://192.168.1.120:18088/ubuntu-24.04-ndysu-0.0.1-amd64.qcow2
http://192.168.1.120:18088/ubuntu-24.04-ndysu-0.0.1-arm64.qcow2
```

Override fallback target if needed:

```bash
UPLOAD_FALLBACK_BASE_URL=http://<host>:<port> ./packer/build.sh --version 0.0.1
```

Override primary upload target if needed:

```bash
UPLOAD_BASE_URL=http://192.168.1.120:18088 ./packer/build.sh --version 0.0.1
```

Temporary packer SSH keypair:

```text
packer/keys/packer-nodadyoushutup
packer/keys/packer-nodadyoushutup.pub
```

## Notes

- Packer SSH user is `packer` (ephemeral).
- `cloud-init/user-data` pins `nodadyoushutup` to `1000:1000`.
- Password SSH login is disabled (`ssh_pwauth: false`).
- `packer/scripts/cleanup-image.sh` removes the temporary `packer` user and any temporary keys/files.
- `packer/build.sh` requires `--version <X.Y.Z>`.
- `packer/build.sh` passes version to Packer via `-var image_version=<version>`.
- `packer/build.sh` accepts `--target webserver`, `--build_arch amd64|arm64|both`, `--amd64_accelerator kvm|tcg|none`, and `--arm64_accelerator kvm|tcg|none`.
- `packer/build.sh` reserves architecture filtering; pass `--build_arch` instead of raw Packer `-only`/`-except`.
- `packer/build.sh` enables Packer debug logs by default (`PACKER_LOG=1`); disable with `--no_packer_log`.
- `packer/upload.sh` accepts `--target webserver` and `--build_arch amd64|arm64|both`.
