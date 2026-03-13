# Radarr SQLite to PostgreSQL Migration Plan

This plan tracks safe migration of legacy Radarr SQLite data from TrueNAS into the Kubernetes PostgreSQL-backed Radarr deployment.

## Safety rules

- Never delete or modify source NAS data under `/mnt/epool/config/radarr`.
- Take backups of PostgreSQL and current k8s `/config` before any truncate/import.
- Pause Argo reconcile during migration to avoid automatic pod recreation.
- Keep migration steps idempotent and verifiable with row-count checks.

## Stage 0 - baseline and discovery

- [x] Confirm `radarr` and `radarr-postgres` workloads are running in Kubernetes.
- [x] Confirm Argo app `radarr` exists and is `Synced/Healthy`.
- [x] Confirm NAS source path `/mnt/epool/config/radarr` exists with expected SQLite files.
- [x] Confirm legacy TrueNAS Radarr media mount parity (`/mnt/epool/media -> /media`) for k8s Radarr.

## Stage 1 - NAS NFS export for Radarr

- [x] Create/verify dedicated TrueNAS NFS share for `/mnt/epool/config/radarr`.
- [x] Enforce requested `775` permissions recursively on source tree and verify.

## Stage 2 - Host mount verification

- [x] Add/verify `/etc/fstab` entry for `192.168.1.100:/mnt/epool/config/radarr -> /mnt/epool/config/radarr`.
- [x] Validate mount source with `findmnt` and file parity with NAS.

## Stage 3 - Source/target data baselines and backups

- [x] Capture SQLite baseline counts from `radarr.db` and `logs.db` (read-only mode).
- [x] Capture PostgreSQL baseline counts from `radarr-main` and `radarr-log`.
- [~] Create backups:
  - PostgreSQL dumps for both databases
  - k8s Radarr `/config` tar backup
  - source metadata/checksums and `config.xml` (full DB copy intentionally skipped due size/time)

## Stage 4 - Migration execution

- [x] Pause Argo reconcile for app `radarr`.
- [x] Scale down `deployment/radarr` (keep postgres up).
- [x] Truncate target PostgreSQL tables while keeping schema.
- [x] Import:
  - `radarr.db` -> `radarr-main` via `pgloader`.
  - `logs.db` -> `radarr-log` via SQLite CSV stream + Postgres `\copy` (fallback after pgloader instability on large log table).
- [x] Scale up `deployment/radarr` and verify startup on Postgres.

## Stage 5 - Validation and restore normal operations

- [x] Verify key row counts in PostgreSQL match SQLite baseline (allowing runtime drift after startup).
- [x] Confirm Radarr logs show Postgres migration/connection success.
- [x] Remove Argo skip annotation and confirm app returns to `Synced/Healthy`.
- [ ] Perform UI spot checks (movies, indexers, profiles, queue/history). (operator follow-up)

## References

- Radarr PostgreSQL setup/migration guide: `https://wiki.servarr.com/radarr/postgres-setup`
- Community migration workflow details: `https://gist.github.com/tobz/929fd4ad8da80ac2ce524af73d4ea615`
- pgloader docs: `https://pgloader.readthedocs.io/en/latest/`

## Lessons learned (from Prowlarr migration)

- Always use dedicated app-specific NFS exports; parent exports can expose stubs for child datasets.
- Validate the active mount source (`findmnt`) before trusting directory contents.
- Set permissions on NAS first (`chmod -R 775`) and verify from both NAS and host.
- Use read-only SQLite connection mode for baseline queries: `mode=ro&immutable=1`.
- Pause Argo reconcile before scaling down app workloads to prevent PVC attach conflicts.
- Expect pgloader cast warnings; judge success by row counts + healthy app startup logs.
- Collect row counts before restarting app; background jobs can alter counts immediately after startup.
- Large logs/media tables can make migration lengthy; preserve backups and avoid destructive shortcuts.
- For very large `logs.db`, streaming `sqlite3 -csv` into Postgres `\copy` is a reliable fallback when pgloader stalls.
- Large `/api/v3/movie` responses can take >60s on big libraries; default ingress timeouts can cause UI load failures (`Failed to load movie from API`) even when Radarr itself is healthy.
- Validate slow API behavior from both paths: direct pod access and ingress access. If ingress is the bottleneck, set per-app ingress `nginx.ingress.kubernetes.io/proxy-read-timeout` and `nginx.ingress.kubernetes.io/proxy-send-timeout` (for example `300`).

## Current status

- As of `2026-03-13`, Radarr is running in Kubernetes against PostgreSQL and app health is `Healthy`.
- Argo `skip-reconcile` annotation was removed and app is `Synced/Healthy`.
- `/media` mount parity is validated in running pod: `192.168.1.100:/mnt/epool/media -> /media`.
- Source vs target counts at migration close:
  - `radarr-main`: source `Movies/History/RootFolders/VersionInfo=53103/271613/6/138`; target matched exactly. `Commands` drifted after app startup due runtime housekeeping.
  - `radarr-log`: source `Logs/UpdateHistory/VersionInfo=17983006/18/138`; target matched baseline, then `Logs` increased slightly after startup (expected runtime drift).
