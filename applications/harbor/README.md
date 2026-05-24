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

Harbor runtime images use a dedicated workflow (not the generic app image workflow):

- Workflow: `.github/workflows/harbor_build_push.yml`
- Per architecture: **one sequential job** runs upstream `make compile` + `make build`
  (full runtime set in Harbor order), then `publish_manifest` merges arch tags.
  amd64 and arm64 jobs can run in parallel on their native runner pools.
- **Required** GitHub secrets **`DOCKERHUB_USERNAME`** / **`DOCKERHUB_PASSWORD`**
  (free Docker Hub account). Harbor builds tool images (`swagger`, photon bases) that
  `FROM` `golang`, `node`, and `photon` on Docker Hub — anonymous pulls always 429 in CI.
- amd64 and arm64 runtime jobs share a concurrency lock so both arches do not pull from
  Hub at the same time (same homelab public IP).
- Inputs:
  - `version` — publish tag (`:<version>-amd64`, `:<version>-arm64`, manifest `:<version>`)
  - `target_registry=github` for `ghcr.io/<owner>/<component>:<tag>`
  - `target_registry=harbor` for `harbor.nodadyoushutup.com/homelab/<component>:<tag>`
- Each dispatch builds the **full** runtime set (12 images); there is no partial component input.
- **`target_registry`**:
  - `github` → `ghcr.io/<owner>/<component>:<version>` (per-arch `:<version>-amd64` / `-arm64`, then manifest)
  - `harbor` → `harbor.nodadyoushutup.com/homelab/<component>:<version>`
  - `both` → build once to GHCR, retag/push the same layers to Harbor (no second compile)
- **Publish names** always use the `harbor-` prefix (for example `harbor-registry-photon`).
  Photon/Makefile may tag `registry-photon` locally; the script retags to the publish name before push.

## Runtime image set

The publish script currently covers:

- `harbor-core`
- `harbor-portal`
- `harbor-jobservice`
- `harbor-registryctl`
- `harbor-db`
- `harbor-registry-photon`
- `harbor-redis-photon`
- `harbor-nginx-photon`
- `harbor-log`
- `harbor-trivy-adapter-photon`
- `harbor-exporter`
- `harbor-prepare`
