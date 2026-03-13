# Seerr (Overseerr) SQLite to PostgreSQL Migration Plan

This plan tracks migration of legacy NAS-hosted Overseerr data into Kubernetes-hosted Seerr backed by PostgreSQL, using the same safety and validation model used for Radarr/Sonarr/Prowlarr.

## Safety rules

- Never delete, rename, or overwrite source NAS data under `/mnt/epool/config/overseerr`.
- Take backups of Kubernetes Seerr `/app/config` and PostgreSQL before truncate/import operations.
- Pause Argo reconcile during migration to avoid pod recreation while Seerr is intentionally scaled down.
- Keep migration actions reversible; validate each stage before moving on.

## Stage 0 - baseline and discovery

- [ ] Confirm Kubernetes `seerr` and `seerr-postgres` workloads are running and healthy.
- [ ] Confirm Argo app `seerr` status is `Synced/Healthy`.
- [ ] Confirm source path `/mnt/epool/config/overseerr` exists and contains expected files (`db/db.sqlite3`, `.env`, config assets).
- [ ] Confirm target Seerr is configured for PostgreSQL (`DB_TYPE=postgres`) and can connect successfully.

## Stage 1 - NAS NFS export and host mount parity

- [ ] Create/verify dedicated TrueNAS NFS share for `/mnt/epool/config/overseerr`.
- [ ] Enforce requested `775` permissions recursively on source tree and verify from NAS + host.
- [ ] Add/verify `/etc/fstab` entry for `192.168.1.100:/mnt/epool/config/overseerr -> /mnt/epool/config/overseerr`.
- [ ] Validate mount source with `findmnt` and file parity with NAS.

## Stage 2 - backups and baselines

- [ ] Capture SQLite baseline counts from source `db.sqlite3` (read-only mode).
- [ ] Capture PostgreSQL baseline counts from target Seerr DB.
- [ ] Create migration backup set:
  - PostgreSQL dump of Seerr DB
  - Kubernetes Seerr `/app/config` tar backup
  - source metadata/checksum snapshot

## Stage 3 - migration execution

- [ ] Pause Argo reconcile for app `seerr`.
- [ ] Scale down `deployment/seerr` (keep `deployment/seerr-postgres` running).
- [ ] Truncate Seerr PostgreSQL tables while preserving schema.
- [ ] Import source SQLite into PostgreSQL.
  - Preferred method (official Seerr docs): `pgloader` SQLite -> Postgres.
  - Fallback method (ARR-proven): table-by-table SQLite CSV stream into Postgres `\copy` if pgloader is unstable.
- [ ] Scale `deployment/seerr` back to 1 and validate startup.

## Stage 4 - validation and stabilization

- [ ] Verify key source-vs-target row counts (allow expected runtime drift after startup jobs).
- [ ] Verify Seerr logs show PostgreSQL connectivity and clean startup.
- [ ] Verify UI/API behavior (requests, users, settings, notifications, integrations).
- [ ] Remove Argo skip annotation and verify app returns to `Synced/Healthy`.

## Arr migration lessons to apply

- Use dedicated per-app NFS exports (`/mnt/epool/config/<app>`), not parent exports.
- Verify active mount source with `findmnt` before trusting host file content.
- Set NAS permissions before migration and verify from both NAS and host.
- Pause Argo reconcile before scaling down to prevent autosync from fighting migration state.
- Take backups before any truncate/import operation.
- Collect row counts before app restart; expect immediate drift in some tables after restart.
- For large datasets, keep `pgloader` as first choice and fall back to SQLite CSV + `\copy` when needed.

## References

- Seerr Docker + PostgreSQL configuration: `https://docs.seerr.dev/installation/docker`
- Seerr migration guide (Overseerr -> Seerr): `https://docs.seerr.dev/migration-guide`
- Seerr SQLite -> PostgreSQL migration flow (`pgloader`): `https://docs.seerr.dev/installation/database-configuration`
- pgloader documentation: `https://pgloader.readthedocs.io/en/latest/`
