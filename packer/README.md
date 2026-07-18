# Packer: Ubuntu / Arch / CentOS / Kali cloud images (+ optional desktop)

This directory contains Packer builds that turn official cloud images into the
homelab base images. Pick the distro with `--distro`:

- **`ubuntu`** (default) — official Ubuntu LTS cloud image, selectable via
  `--ubuntu_release` (`24.04` Noble Numbat or `26.04` Resolute Raccoon).
  **amd64 + arm64.**
- **`arch`** — official Arch Linux `cloudimg` qcow2 (pinned snapshot).
  **amd64 only** — Arch upstream publishes no arm64 cloud image, so an arm64
  Arch build fails fast with an explanatory error.
- **`centos`** — official CentOS Stream GenericCloud qcow2, selectable via
  `--centos_stream` (default `10`). **amd64 + arm64.**
- **`kali`** — official Kali Linux `genericcloud` image, selectable via
  `--kali_release` (default `2026.2`). **amd64 + arm64.** Kali ships its cloud
  image as a `.tar.xz` (containing a raw disk), not a bootable qcow2, so
  `scripts/prepare-kali-image.sh` downloads the pinned tarball, verifies its
  upstream SHA256, extracts the raw disk, and converts it to a local qcow2 that
  Packer then provisions. The pinned tarball checksums live in that script;
  bump them together with `--kali_release` to move to a newer Kali image.
  **Kali is intentionally kept near-raw**: it does **not** run the shared
  automation toolchain (`automation_tooling.sh`) and installs no desktop (the
  `--gui` flag is ignored). The only optional add-on is the host
  `--install_node_exporter` service.

Every build:

- uses a temporary `packer` SSH user/key for provisioning only
- sets `nodadyoushutup` as UID/GID `1000:1000` directly in cloud-init
- uploads and runs `scripts/install/automation_tooling.sh` for the shared
  automation toolchain (the install scripts are distro-aware: `apt` / `pacman`
  / `dnf`) — **except `kali`, which is kept raw and skips this entirely**
- optionally installs the host-level Prometheus node_exporter systemd service
  from `scripts/install/node_exporter.sh` via `--install_node_exporter`
  (**off by default**: swarm/k8s hosts already run node_exporter as a container,
  so a host install would double-export; enable only for hosts monitored
  directly)
- optionally installs a desktop environment via `--gui`
  (`headless` default, or `gnome` / `kde` / `xfce`) — **ignored for `kali`**
- runs a cleanup script that removes temporary SSH/provisioning access

The bootstrapping scripts share a small package-manager helper library at
`scripts/install/lib/pkg.sh` (detects `apt`/`pacman`/`dnf`, enables EPEL + CRB on
CentOS, and provides `pkg_install`/`pkg_install_best_effort`).

## Prerequisites

- `packer`
- `qemu-system-x86_64` (amd64 builds)
- `qemu-system-aarch64` (arm64 builds)
- `qemu-img`
- `xorriso`, `curl`, `jq`
- `tar`, `xz`, `sha256sum` (Kali only — used to unpack/verify its `.tar.xz` cloud image)
- KVM support for best performance when selecting `accelerator=kvm` (`/dev/kvm` must be available to the runner/container)

## Build

From repo root (defaults to Ubuntu 24.04):

```bash
./packer/packer.sh --version 0.0.1
```

Build Ubuntu 26.04 instead:

```bash
./packer/packer.sh --version 0.0.1 --ubuntu_release 26.04
```

Run the repo-native build-and-upload pipeline equivalent of the GHA workflow:

```bash
./packer/pipeline/packer.sh --version 0.0.1 --ubuntu_release 26.04
```

Local builds write directly into the NFS-backed `data/packer` directory that the
cloud image repository serves, so **building publishes the artifact** — no upload
step is required. The REST upload is **opt-in** via `--publish` (use it to push
through the public URL, e.g. when building off a host that is not on the homelab
NFS).

The **Packer** workflow (`.github/workflows/packer.yml`) follows the same **prepare → parallel per-arch jobs → publish** shape as Docker **direct** builds: **`prepare`** on `homelab,amd64,build`, then **`build_packer_direct_amd64`** and **`build_packer_direct_arm64`** (each `needs: prepare` only, so they run concurrently when **`build_arch: both`**), then **`publish_packer_artifacts`** downloads all produced artifacts and uploads every `.qcow2` to the cloud image repository host. The publish job is **optional**: it only runs when the workflow is dispatched with **`publish: true`**. Job-level `if` cannot use the `matrix` context, so Packer mirrors Docker with **two jobs** rather than a filtered matrix.

If the workflow requests **`kvm`** but the runner has no usable **`/dev/kvm`** (common for Docker-in-Docker self-hosted runners), each build job **falls back to `tcg`** automatically so QEMU can start (slower). Prefer exposing KVM to the runner, or dispatch with **`tcg`** when you accept software emulation.

Build Arch (amd64 only), CentOS Stream 10 (amd64 + arm64), or Kali 2026.2 (amd64 + arm64):

```bash
./packer/packer.sh --version 0.0.1 --distro arch --build_arch amd64
./packer/packer.sh --version 0.0.1 --distro centos --build_arch both
./packer/packer.sh --version 0.0.1 --distro kali --build_arch amd64
./packer/packer.sh --version 0.0.1 --distro kali --kali_release 2026.2 --build_arch both
```

An arm64 Arch build is rejected immediately (no upstream image):

```bash
./packer/packer.sh --version 0.0.1 --distro arch --build_arch arm64
# ERROR: Arch Linux publishes no official arm64 cloud image; ... Use --build_arch amd64.
```

By default no desktop is installed (headless image). Select a desktop
environment with `--gui` (`headless` | `gnome` | `kde` | `xfce`), on any distro:

```bash
./packer/packer.sh --version 0.0.3 --gui kde
./packer/packer.sh --version 0.0.3 --distro centos --gui gnome
./packer/packer.sh --version 0.0.3 --distro arch --gui xfce
```

Build with GHA-equivalent selectors:

```bash
./packer/packer.sh --version 0.0.3 \
  --distro ubuntu \
  --ubuntu_release 24.04 \
  --gui headless \
  --target cloud-image-repository \
  --build_arch both \
  --amd64_accelerator kvm \
  --arm64_accelerator kvm
```

Build only one architecture:

```bash
./packer/packer.sh --version 0.0.3 --build_arch amd64 --amd64_accelerator kvm
./packer/packer.sh --version 0.0.3 --build_arch arm64 --arm64_accelerator tcg
```

Enable verbose Packer debug logs for troubleshooting:

```bash
./packer/packer.sh --version 0.0.3 --build_arch arm64 --arm64_accelerator kvm --packer_log
```

Build and also push over REST (opt-in publish):

```bash
./packer/packer.sh --version 0.0.3 --publish
```

Upload-only (existing built artifacts for a version, read from `data/packer`):

```bash
./packer/upload.sh 0.0.1 --target cloud-image-repository --build_arch both
./packer/upload.sh 0.0.1 --build_arch amd64
./packer/upload.sh 0.0.1 --distro centos --build_arch both
```

The tracked Jenkins wrapper for the same flow lives at:

```text
packer/pipeline/packer.jenkins
```

## Output

Local builds write artifacts to the NFS-backed `data/packer` directory (served
by the cloud image repository at `/`). The image prefix is
`<distro>-[<release>-]ndysu`:

```text
data/packer/ubuntu-24.04-ndysu/0.0.1/amd64/ubuntu-24.04-ndysu-0.0.1-amd64.qcow2
data/packer/ubuntu-24.04-ndysu/0.0.1/arm64/ubuntu-24.04-ndysu-0.0.1-arm64.qcow2
data/packer/ubuntu-26.04-ndysu/0.0.1/amd64/ubuntu-26.04-ndysu-0.0.1-amd64.qcow2
data/packer/arch-ndysu/0.0.1/amd64/arch-ndysu-0.0.1-amd64.qcow2
data/packer/centos-10-ndysu/0.0.1/amd64/centos-10-ndysu-0.0.1-amd64.qcow2
data/packer/centos-10-ndysu/0.0.1/arm64/centos-10-ndysu-0.0.1-arm64.qcow2
data/packer/kali-2026.2-ndysu/0.0.1/amd64/kali-2026.2-ndysu-0.0.1-amd64.qcow2
data/packer/kali-2026.2-ndysu/0.0.1/arm64/kali-2026.2-ndysu-0.0.1-arm64.qcow2
```

Override the output base directory with `PACKER_OUTPUT_ROOT` (CI leaves the
Packer default of `packer/output/...` and publishes via the optional REST step).

Run log is written to:

```text
packer/logs/build-<utc-timestamp>-v0.0.1.log
```

Artifact upload destinations:

```text
https://cloud-image-repository.nodadyoushutup.com/ubuntu-24.04-ndysu-0.0.1-amd64.qcow2
https://cloud-image-repository.nodadyoushutup.com/ubuntu-24.04-ndysu-0.0.1-arm64.qcow2
```

If the HTTPS proxy returns `413`, `packer.sh` retries each artifact upload directly to:

```text
http://192.168.1.120:18088/ubuntu-24.04-ndysu-0.0.1-amd64.qcow2
http://192.168.1.120:18088/ubuntu-24.04-ndysu-0.0.1-arm64.qcow2
```

Override fallback target if needed:

```bash
UPLOAD_FALLBACK_BASE_URL=http://<host>:<port> ./packer/packer.sh --version 0.0.1
```

Override primary upload target if needed:

```bash
UPLOAD_BASE_URL=http://192.168.1.120:18088 ./packer/packer.sh --version 0.0.1
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
- `packer/packer.sh` requires `--version <X.Y.Z>`.
- `packer/packer.sh` passes version to Packer via `-var image_version=<version>`.
- `packer/packer.sh` accepts `--distro ubuntu|arch|centos|kali`, `--gui headless|gnome|kde|xfce`, `--install_node_exporter` / `--no_install_node_exporter` (default off), `--ubuntu_release 24.04|26.04` (ubuntu), `--centos_stream 10` (centos), `--arch_snapshot <id>` (arch), `--kali_release 2026.2` (kali), `--target cloud-image-repository`, `--build_arch amd64|arm64|both`, `--amd64_accelerator kvm|tcg|none`, and `--arm64_accelerator kvm|tcg|none`.
- `--install_node_exporter` is **off by default**. The host node_exporter systemd service double-exports on swarm/k8s hosts (they run node_exporter as a container), so only enable it for hosts you monitor directly. The flag maps to the `install_node_exporter` Packer var and threads through `packer/pipeline/packer.sh` (same flag), `packer/pipeline/packer.jenkins` (`INSTALL_NODE_EXPORTER` boolean param), and the GitHub Actions workflow (`install_node_exporter` boolean input).
- **Arch is amd64-only**: `--distro arch` with `--build_arch arm64|both` fails fast with an explanatory error. **CentOS and Kali are amd64 + arm64** (full parity with Ubuntu).
- **Kali** does not publish a bootable qcow2 cloud image, only a `.tar.xz` holding a raw disk. `scripts/prepare-kali-image.sh` downloads the pinned tarball, verifies its upstream SHA256, extracts the raw disk, converts it to a qcow2 under `packer/.cache/kali/` (git-ignored), and feeds that local image to Packer via `-var kali_local_image_<arch>` / `-var kali_<arch>_image_checksum`. `packer/packer.sh` and the GitHub Actions/Jenkins pipelines all run this preparation automatically before building.
- `--gui` replaces the old `--kde_profile` flag (hard cut). Each distro ships its own `gnome.sh` / `kde.sh` / `xfce.sh` install script; `headless` installs nothing.
- Each new distro pins its base image URL + `sha256` in the template (`arch-ndysu.pkr.hcl`, `centos-ndysu.pkr.hcl`) or, for Kali, in `scripts/prepare-kali-image.sh`; bump the snapshot/release + checksum together to move to a newer base image.
- `packer/packer.sh` reserves architecture filtering; pass `--build_arch` instead of raw Packer `-only`/`-except`.
- `packer/packer.sh` enables Packer debug logs by default (`PACKER_LOG=1`); disable with `--no_packer_log`.
- `packer/upload.sh` accepts `--distro ubuntu|arch|centos|kali`, `--ubuntu_release 24.04|26.04`, `--centos_stream 10`, `--kali_release 2026.2`, `--target cloud-image-repository`, and `--build_arch amd64|arm64|both`.
- `packer/packer.sh` writes to the NFS-backed `data/packer` dir by default and
  only uploads over REST when `--publish` is passed.
- `packer/pipeline/packer.sh` mirrors the GitHub Actions
  `packer` workflow inputs (`--distro`, `--gui`, per-distro release), runs
  `packer/packer.sh`, and runs `packer/upload.sh` only when `--publish` is passed.
- `packer/pipeline/packer.jenkins` is the in-repo Jenkins Pipeline
  wrapper for the same flow. It exposes a single **`OS`** dropdown
  (`ubuntu-24.04` | `ubuntu-26.04` | `centos-10` | `arch` | `kali-2026.2`) plus `GUI` and
  `ARCH_SNAPSHOT`, and maps the OS choice to `--distro`/`--ubuntu_release`/`--centos_stream`/`--kali_release`.
- The **Packer** GitHub Actions workflow exposes the same single **`os`** dropdown
  plus a `gui` dropdown and an `install_node_exporter` boolean (default off); the
  arm64 build job is gated off for `arch` (Kali builds both architectures).
