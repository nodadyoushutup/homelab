# Harbor Image Factory

This workspace bootstraps custom Harbor images so we can publish our own multi-arch manifests (`linux/amd64` + `linux/arm64`) for Swarm use.

## Layout

- `versions.env`: pinned Harbor source version and default image tag.
- `scripts/sync-components.sh`: syncs upstream Harbor component Docker build files into local component directories.
- `scripts/build-multiarch.sh`: builds, pushes, and creates multi-arch manifests for Harbor runtime components.
- `core/`, `portal/`, `jobservice/`, ...: synced upstream component build files.

## First-use

```bash
./applications/harbor/scripts/sync-components.sh
```

This creates/updates the local component directories from the pinned version in `versions.env`.

## Multi-arch build + publish

```bash
./applications/harbor/scripts/build-multiarch.sh \
  --namespace registry.example.com/homelab \
  --push
```

Notes:
- `--namespace` is required and should be the registry/repository prefix for output images.
- `--path-mode namespace-component` keeps the default `<namespace>/<component>:<tag>` layout (used for Harbor with `--namespace <registry>/homelab`).
- `--path-mode project-per-image` publishes paths like
  `<registry>/<component>/<component>:<tag>` (legacy one-Harbor-project-per-component layout).
- If the build host does not have GNU Make installed, the script falls back to
  a disposable `docker:27-cli` helper container and installs build tools there.
- If cross-architecture emulation is not installed, run once with `--install-binfmt`.
- The script publishes arch tags (`:<tag>-amd64`, `:<tag>-arm64`) and manifest tags (`:<tag>`).

## GitHub Actions publish

The shared publish workflow now includes a `harbor-runtime-set` target:

- Workflow: `.github/workflows/docker_build_push.yml`
- Inputs:
  - `build_target=harbor-runtime-set`
  - `target_registry=github` for `ghcr.io/<owner>/<component>:<tag>`
  - `target_registry=harbor` for
    `harbor.nodadyoushutup.com/homelab/<component>:<tag>`

## Runtime image set

The publish script currently covers:

- `harbor-core`
- `harbor-portal`
- `harbor-jobservice`
- `harbor-registryctl`
- `harbor-db`
- `registry-photon`
- `redis-photon`
- `nginx-photon`
- `harbor-log`
- `trivy-adapter-photon`
- `harbor-exporter`
- `prepare`
