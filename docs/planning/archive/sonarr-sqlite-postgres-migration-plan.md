# Sonarr SQLite to PostgreSQL Migration Plan

This plan tracks safe migration of legacy Sonarr SQLite data from TrueNAS into the Kubernetes PostgreSQL-backed Sonarr deployment without destructive changes to source data.

## Safety rules

- Never delete, rename, or overwrite source NAS data under `/mnt/epool/config/sonarr`.
- Take backups of current Kubernetes Sonarr config and PostgreSQL before truncate/import operations.
- Pause Argo reconcile during migration to avoid pod recreation while app is intentionally scaled down.
- Keep all migration steps reversible and validate each stage before proceeding.

## Stage 0 - baseline and discovery

- [x] Confirm Kubernetes `sonarr` and `sonarr-postgres` deployments are running and healthy.
- [x] Confirm Argo app `sonarr` status is `Synced/Healthy`.
- [x] Confirm source path `/mnt/epool/config/sonarr` exists and contains expected DB/config files (`sonarr.db`, `logs.db`, `config.xml`).
- [x] Confirm legacy TrueNAS Sonarr media mount mapping (host path -> container path) so k8s mount parity can be enforced.

## Stage 1 - NAS NFS export and permissions

- [x] Create/verify dedicated TrueNAS NFS share for `/mnt/epool/config/sonarr`.
- [x] Enforce requested `775` permissions recursively on source tree and verify from NAS + host.

## Stage 2 - Host mount verification

- [x] Add/verify `/etc/fstab` entry for `192.168.1.100:/mnt/epool/config/sonarr -> /mnt/epool/config/sonarr`.
- [x] Mount and verify file parity (`ls`, DB sizes, key files) between NAS and host.

## Stage 3 - Backups and baselines

- [x] Capture SQLite baseline counts (read-only mode) from `sonarr.db` and `logs.db`.
- [x] Capture PostgreSQL baseline counts from Sonarr main/log databases.
- [x] Create backups before migration:
  - PostgreSQL dumps (main + log DBs)
  - Kubernetes Sonarr `/config` backup tar
  - source metadata/checksum snapshot and `config.xml`

## Stage 4 - Migration execution

- [x] Pause Argo reconcile for app `sonarr`.
- [x] Scale down `deployment/sonarr` (keep `sonarr-postgres` running).
- [x] Truncate target PostgreSQL tables while preserving schema.
- [x] Import data:
  - `sonarr.db` -> Sonarr main PostgreSQL DB
  - `logs.db` -> Sonarr log PostgreSQL DB
  - `pgloader` attempted first and failed due SBCL instability/duplicate handling on this dataset.
  - Final method used: table-by-table `sqlite3 -csv` stream into PostgreSQL `\copy` (main and log DBs).
- [x] Reset PostgreSQL sequences to table max IDs post-import.
- [x] Scale `deployment/sonarr` back to 1.

## Stage 5 - Validation and stabilization

- [x] Verify key source-vs-target row counts (allowing expected runtime drift after app startup).
- [x] Verify Sonarr startup logs show PostgreSQL connectivity/migrations succeeded.
- [x] Verify media mount parity in running Sonarr pod (same effective path semantics as legacy app).
- [x] Verify Sonarr ingress/API behavior; ensure heavy catalog endpoints do not hit ingress timeout.
- [x] Remove Argo skip annotation and verify app returns to `Synced/Healthy`.
- [ ] Complete UI spot checks (series list, history, queue, indexers, download clients, root folders). (operator follow-up)

## References

- Sonarr PostgreSQL setup and migration docs: `https://wiki.servarr.com/sonarr/postgres-setup`
- `pgloader` docs: `https://pgloader.readthedocs.io/en/latest/`
- Community ARR migration workflow: `https://gist.github.com/tobz/929fd4ad8da80ac2ce524af73d4ea615`

## Lessons learned carried forward (Prowlarr + Radarr)

- Use dedicated per-app NFS exports (`/mnt/epool/config/<app>`), not parent exports.
- Always verify active mount source with `findmnt` before trusting directory content.
- Set NAS permissions before migration and verify from both sides (`chmod -R 775` + spot checks).
- Pause Argo reconcile before scale-down to prevent autosync from fighting migration state.
- Take backups before any truncate/import step.
- Compare DB counts before app restart; after restart, some tables drift immediately due background jobs.
- For very large `logs.db`, prefer SQLite CSV streaming + Postgres `\copy` if pgloader stalls.
- If UI API loads fail but pod is healthy, check ingress timeout logs (`504/499`) and raise per-app ingress proxy timeouts.

## Sonarr execution notes

- Backup directory: `/tmp/sonarr-migration-20260312-224049`
- Source Sonarr (TrueNAS app) was confirmed `STOPPED` during copy to keep SQLite source stable.
- Source baseline at cutover:
  - main: `Series=1434`, `Episodes=100758`, `EpisodeFiles=71732`, `History=237534`, `RootFolders=3`, `Commands=2169`, `VersionInfo=211`
  - log: `Logs=1009014`, `UpdateHistory=15`, `VersionInfo=211`, `LogsMaxId=137382359`
- Target validation:
  - main matched baseline exactly after import.
  - log matched baseline; after Sonarr startup, `Logs` and `LogsMaxId` incremented slightly (expected runtime drift).
- Kubernetes Sonarr updates applied during migration:
  - `/media` NFS mount parity added (`192.168.1.100:/mnt/epool/media -> /media`)
  - ingress timeouts set to `proxy-read-timeout=300` and `proxy-send-timeout=300`
