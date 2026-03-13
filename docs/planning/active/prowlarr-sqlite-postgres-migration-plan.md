# Prowlarr SQLite to PostgreSQL Migration Plan

This plan tracks a safe migration of legacy Prowlarr data from NAS-hosted SQLite files into the Kubernetes PostgreSQL-backed Prowlarr deployment, with zero destructive actions.

## Safety rules

- Never delete or overwrite source data on TrueNAS (`/mnt/epool/config/prowlarr`) without a backup.
- Keep the existing SQLite files intact even after migration.
- Use stop/copy/start sequencing for app components to avoid DB corruption.
- Validate all checkpoints before proceeding to the next stage.

## Stage 0 - baseline and discovery

- [x] Confirm Kubernetes `prowlarr` and `prowlarr-postgres` workloads are running.
- [x] Confirm TrueNAS source path exists and contains expected Prowlarr files (`config.xml`, `prowlarr.db`, `logs.db`, etc.).
- [x] Confirm current NFS exports do not yet include `/mnt/epool/config/prowlarr`.

## Stage 1 - NAS NFS export for Prowlarr

- [x] Create TrueNAS NFS share for `/mnt/epool/config/prowlarr`.
  Mark complete when: `midclt call sharing.nfs.query` shows enabled export for that exact path.
- [x] Ensure source tree permissions are `775` as requested.
  Mark complete when: spot checks on files and directories return mode `775`.

## Stage 2 - Host-side mount verification

- [x] Add/verify `/etc/fstab` entry for `192.168.1.100:/mnt/epool/config/prowlarr -> /mnt/epool/config/prowlarr`.
- [x] Mount and verify host can see full source file set from NAS.
  Mark complete when: local `ls -la /mnt/epool/config/prowlarr` matches NAS-side key files.

## Stage 3 - Migration procedure and backups

- [x] Pull official Prowlarr docs for SQLite to PostgreSQL migration procedure.
  Mark complete when: source links and exact command/env requirements are captured here.
- [x] Back up Kubernetes-side current `/config` and PostgreSQL databases before migration.
  Mark complete when: backup artifacts exist and are readable.

### Migration references used

- Prowlarr migration guide (community-maintained by Servarr contributor): `https://gist.github.com/Roxedus/6ee57558006de89ae41229388b4c0085`
- `pgloader` reference for command and options (`--with "quote identifiers"` and `--with "data only"`): `https://pgloader.readthedocs.io/en/latest/ref/pgsql.html`

## Stage 4 - Execute migration into Kubernetes PostgreSQL

- [x] Pause reconcile/rollout controls as needed to keep app state stable during migration.
- [x] Apply documented migration method from SQLite to PostgreSQL using source DB from NAS.
- [x] Bring workloads back online and verify app health.

### Execution notes

- Argo app was paused via annotation `argocd.argoproj.io/skip-reconcile=true`, then restored.
- `prowlarr` deployment was scaled down during import; `prowlarr-postgres` remained up.
- Existing PostgreSQL rows were truncated (schema preserved) before import.
- Imported via `pgloader` pod:
  - `/mnt/epool/config/prowlarr/prowlarr.db` -> `prowlarr-main`
  - `/mnt/epool/config/prowlarr/logs.db` -> `prowlarr-log`
- Post-import count spot checks matched expected source data for key tables.

## Stage 5 - Validation

- [x] Verify Prowlarr starts cleanly with PostgreSQL backend and migrated data visible.
- [ ] Validate indexers/apps/settings/history spot checks in UI/API/logs.
- [x] Re-enable normal reconcile settings and confirm Argo app `Synced/Healthy`.

## Lessons learned

- Use a dedicated NFS export per app path (`/mnt/epool/config/<app>`) instead of relying on a parent export; child dataset boundaries can present empty/stub directories.
- Verify mount source and activation with `findmnt` before trusting directory contents; confirm the mounted source path matches the intended export exactly.
- Set NAS permissions before migration (`chmod -R 775`) and verify from both NAS and host sides; ownership may still appear as numeric IDs on the client and that is expected.
- Pause Argo reconciliation (`argocd.argoproj.io/skip-reconcile=true`) before scaling app deployments down; otherwise autosync can recreate pods and block exclusive PVC attach operations.
- Back up first, then migrate: PostgreSQL dumps + current k8s `/config` tar + SQLite source files should be captured before any truncation/import.
- For read-only SQLite access checks, use SQLite URI mode (`mode=ro&immutable=1`) to avoid journal/write attempts on mounted NAS files.
- `pgloader` type-cast warnings are expected when importing into existing Servarr PostgreSQL schemas; validate success by row counts and app startup logs rather than warning count.
- Compare source and target table counts immediately after import, before restarting the app; after startup, some tables (commands/logs) can change as background jobs begin.
- Keep large historical backup artifacts out of initial migrations unless required; they increase transfer time and risk filling PVCs without helping core cutover.
- For large ARR libraries, API endpoints that return full catalog payloads can exceed default ingress timeouts; verify response latency both direct-to-pod and via ingress.
- If UI shows `Failed to load ... from API` while backend is healthy, inspect ingress logs for `504/499` timeout chains and raise per-app ingress `proxy-read-timeout` and `proxy-send-timeout` as needed.

## Reusable ARR checklist (template for Radarr/Sonarr/Lidarr)

1. Export specific NAS config path via dedicated NFS share.
2. Mount dedicated path on host and verify file parity.
3. Back up k8s app config PVC + PostgreSQL DB.
4. Run official SQLite->Postgres migration method for that ARR.
5. Validate app behavior and DB connectivity.
6. Archive plan and copy checklist for next ARR.
