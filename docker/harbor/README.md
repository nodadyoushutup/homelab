# Harbor Image Factory

This workspace bootstraps custom Harbor images so we can publish our own multi-arch manifests (`linux/amd64` + `linux/arm64`) for Swarm use.

## Layout

- `versions.env`: pinned Harbor source version and default image tag.
- `scripts/sync-components.sh`: syncs upstream Harbor component Docker build files into local component directories.
- `scripts/build-multiarch.sh`: builds, pushes, and creates multi-arch manifests for Harbor runtime components.
- `core/`, `portal/`, `jobservice/`, ...: synced upstream component build files.

## First-use

```bash
./docker/harbor/scripts/sync-components.sh
```

This creates/updates the local component directories from the pinned version in `versions.env`.

## Multi-arch build + publish

```bash
./docker/harbor/scripts/build-multiarch.sh \
  --namespace registry.example.com/homelab \
  --push
```

Notes:
- `--namespace` is required and should be the registry/repository prefix for output images.
- If cross-architecture emulation is not installed, run once with `--install-binfmt`.
- The script publishes arch tags (`:<tag>-amd64`, `:<tag>-arm64`) and manifest tags (`:<tag>`).

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
