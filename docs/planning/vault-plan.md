# Vault app/config + unseal workflow plan

This plan tracks introducing HashiCorp Vault into Docker Swarm using the existing homelab Terraform/GitOps pattern, with automated bootstrap/unseal/seal handled by host-side scripts that write local artifacts under `/mnt/eapp/.tfvars/vault`.

## How to use this plan

- Every task starts unchecked (`[ ]`).
- When a task is done, change it to checked (`[x]`).
- A task is only complete when its "Mark complete when" condition is true.
- If scope changes, add a short "Scope change" note in the relevant stage before proceeding.

## Stage 0 - scope, prerequisites, and design lock

- [x] Confirm service taxonomy and states: `vault/app` (Swarm runtime) + `vault/config` (Vault provider resources), each with separate Terraform state.
  Mark complete when: stage boundaries and state split are documented in this file and accepted.
- [x] Lock workflow mode to bash-only deployment for now (no Jenkins dependency).
  Mark complete when: this plan explicitly treats Jenkins as out of scope for execution and uses shell entrypoints as source of truth.
- [x] Confirm provider/tooling approach:
  - `kreuzwerker/docker` for app stage resources.
  - `hashicorp/vault` for config stage resources.
  - shell scripts for bootstrap/unseal/seal (`scripts/vault/bootstrap.sh`, `scripts/vault/unseal.sh`, `scripts/vault/seal.sh`).
  Mark complete when: provider choices and script responsibilities are explicitly documented here.
- [x] Define tfvars/backend paths and verify existence/readiness:
  - backend: `/mnt/eapp/.tfvars/minio.backend.hcl`
  - app tfvars: `/mnt/eapp/.tfvars/vault/app.tfvars`
  - config tfvars: `/mnt/eapp/.tfvars/vault/config.tfvars`
  - bootstrap artifact dir: `/mnt/eapp/.tfvars/vault/`
  Mark complete when: `ls -l` proof for these paths is captured in implementation notes (with sensitive values redacted).
- [x] Lock initialization/operations mode:
  - Vault runs in normal mode (not dev mode).
  - bootstrap script performs one-time init and exports artifacts to host-local `/mnt/eapp/.tfvars/vault`.
  - config stage runs only after successful bootstrap + unseal.
  Mark complete when: these constraints are explicitly documented and referenced in stage ordering.

### Interview decisions locked (2026-03-07)

- [x] Deployment topology: single Vault node in Swarm for now.
  Mark complete when: app stage sets `replicas = 1` and placement targets `swarm-cp-0` (or equivalent node label/constraint that resolves there).
- [x] Storage durability: persisted data volume is required.
  Mark complete when: app stage defines persistent Docker volume(s) for Vault storage and restart preserves data.
- [x] Bootstrap execution mode: automatic after app deploy.
  Mark complete when: `vault/app` pipeline invokes `scripts/vault/bootstrap.sh` after successful Terraform apply, and reruns are safe/idempotent.
- [x] Unseal/seal execution mode: unseal runs automatically in config pipeline, with standalone manual scripts available; seal remains manual by operator.
  Mark complete when: `config.sh` runs `unseal.sh` automatically, while `unseal.sh` and `seal.sh` remain directly runnable for manual operations.
- [x] Config authentication source: root token from bootstrap artifacts for now.
  Mark complete when: `vault/config` uses root token sourced from local bootstrap artifacts/env (no repo-committed token).
- [x] Config safety gate: hard-fail when Vault is sealed.
  Mark complete when: config pipeline attempts auto-unseal first, then exits with a clear message to run `scripts/vault/unseal.sh` manually if Vault remains sealed.
- [x] Unseal behavior: fully automatic (non-interactive) using required key shares from `init.json`.
  Mark complete when: `scripts/vault/unseal.sh` runs non-interactively and no-ops when already unsealed.
- [x] Seal behavior default: local Vault target only.
  Mark complete when: `scripts/vault/seal.sh` defaults to local service endpoint without requiring a host argument.
- [x] Network exposure: publish Vault port externally for now.
  Mark complete when: app stage publishes Vault API/UI port on the chosen node.
- [x] Published port selection: use default Vault port `8200` unless conflict is detected.
  Mark complete when: app stage maps/publishes `8200` and docs/scripts reference the same default.
- [x] App deploy preflight: fail fast if port `8200` is already in use on `swarm-cp-0`.
  Mark complete when: `vault/app/pipeline/app.sh` performs a port-availability check and exits with clear remediation guidance before Terraform apply.
- [x] Post-deploy health gate: app pipeline validates Vault health endpoint.
  Mark complete when: `vault/app/pipeline/app.sh` checks `/v1/sys/health` after apply/bootstrap and exits non-zero if service is unhealthy/unreachable.
- [x] Config apply trigger mode: manual invocation only (not chained from app pipeline).
  Mark complete when: app pipeline stops after bootstrap and does not run config automatically.
- [x] Config pipeline behavior: auto-run unseal before Terraform config apply.
  Mark complete when: `vault/config/pipeline/config.sh` invokes `scripts/vault/unseal.sh` before Terraform operations and proceeds when already unsealed.
- [x] Config pipeline failure policy: fail fast when auto-unseal fails.
  Mark complete when: `config.sh` exits immediately on unseal failure and does not run any Terraform commands.
- [x] Script reuse model: `unseal.sh` and `seal.sh` are standalone operator tools and reusable by pipelines.
  Mark complete when: scripts support direct manual execution and are called by pipeline steps without code duplication.
- [x] Unseal no-op UX: emit explicit status when Vault is already unsealed.
  Mark complete when: `unseal.sh` and config pipeline logs clearly state "already unsealed, continuing" on no-op path.
- [x] Image policy: pin an explicit current stable Vault image tag at implementation time.
  Mark complete when: Terraform resource references an explicit Vault image tag directly (no local indirection).
- [x] Day-1 transport mode: internal HTTP only (TLS deferred).
  Mark complete when: app/config docs and scripts default to `http://` endpoint and note TLS as future enhancement.
- [x] Bootstrap env artifact: generate `/mnt/eapp/.tfvars/vault/.env`.
  Mark complete when: bootstrap script writes/refreshes `/mnt/eapp/.tfvars/vault/.env` with required values (at minimum `VAULT_ADDR`, `VAULT_TOKEN`) and permissions are restricted.
- [x] Bootstrap directory creation: auto-create `/mnt/eapp/.tfvars/vault/` when missing.
  Mark complete when: bootstrap script creates the directory before writing artifacts and handles reruns cleanly.
- [x] Bootstrap env refresh policy: overwrite `/mnt/eapp/.tfvars/vault/.env` on every run.
  Mark complete when: `.env` is regenerated each bootstrap execution with current values.
- [x] Config env loading: `config.sh` auto-sources `/mnt/eapp/.tfvars/vault/.env`.
  Mark complete when: config pipeline loads env values automatically without requiring manual `source` commands.
- [x] Input path policy: fixed tfvars/backend naming for Vault (no per-run overrides).
  Mark complete when: app/config pipelines resolve only the canonical Vault tfvars/backend paths and reject/ignore override flags.
- [x] Unseal env fallback policy: if `/mnt/eapp/.tfvars/vault/.env` is missing, use default `VAULT_ADDR=http://swarm-cp-0.local:8200` with an explicit warning message.
  Mark complete when: `unseal.sh` logs fallback usage and continues with the default address.
- [x] Config env fallback policy: if `/mnt/eapp/.tfvars/vault/.env` is missing, use default `VAULT_ADDR=http://swarm-cp-0.local:8200` with warning; hard-fail if `VAULT_TOKEN` is unavailable.
  Mark complete when: `config.sh` can proceed with address fallback but exits before Terraform when token input is missing.
- [x] Vault storage backend: integrated Raft.
  Mark complete when: app stage renders Vault server configuration with `storage "raft"` using persistent volume-backed data path.
- [x] UI mode: enabled on day 1.
  Mark complete when: Vault server configuration sets `ui = true` and published endpoint supports UI access.
- [x] Unseal key strategy: `key-shares=3`, `key-threshold=2`.
  Mark complete when: bootstrap init command uses these values and unseal automation submits exactly the threshold number of keys.
- [x] Missing bootstrap artifact policy: hard-fail if Vault is initialized but `/mnt/eapp/.tfvars/vault/init.json` is missing.
  Mark complete when: bootstrap script detects this condition and exits with clear restore/remediation guidance instead of attempting re-init.
- [x] Artifact permissions policy (temporary): use permissive `775` on generated Vault local artifacts.
  Mark complete when: bootstrap-generated files/directories are set or normalized to `775`, with a documented follow-up to tighten permissions later.
- [x] Secrets authoring model: grouped declarative payloads in config tfvars (`secrets.<group>.<name> = { ... }`) created via Terraform loops.
  Mark complete when: `/mnt/eapp/.tfvars/vault/config.tfvars` supports grouped maps (for example `secrets.k8s.thelounge` and `secrets.website.google`) and config module loops create one Vault KV secret per `<group>/<name>` entry.
- [x] Secret path convention (day 1): write grouped entries to `secret/<group>/<name>`.
  Mark complete when: config loop maps tfvars groups directly to Vault KV paths (for example `secret/k8s/thelounge`, `secret/website/google`) without hardcoding group names.
- [x] Secret key naming guardrails: enforce safe `<group>`/`<name>` identifiers.
  Mark complete when: Terraform validation restricts group and secret names to lowercase alphanumeric plus `-`/`_`, and rejects `/` characters.
- [x] Empty payload policy (temporary): allow empty secret objects.
  Mark complete when: config schema accepts `{}` payloads without failing validation, with a note that production hardening may require non-empty values later.
- [x] Empty scalar policy (temporary): allow empty string values within secret payloads.
  Mark complete when: config schema/logic accepts values like `password = \"\"` without validation failure.
- [x] Secret lifecycle policy: tfvars is authoritative; removing an entry deletes the corresponding Vault secret.
  Mark complete when: removing `secrets.<group>.<name>` from tfvars produces a Terraform destroy for that secret path on apply.
- [x] TheLounge payload keys (day 1): use `username` and `password`.
  Mark complete when: example schema/docs and initial tfvars entries for `secrets.k8s.thelounge` use exactly `username` and `password`.
- [x] Day-1 secret scope: only `secrets.k8s.thelounge` is seeded initially.
  Mark complete when: initial config tfvars/examples include only TheLounge entry, while additional groups/secrets are documented as future additions.
- [x] Day-1 TheLounge seed values: use placeholders (`username = "admin"`, `password = "password"`).
  Mark complete when: initial `/mnt/eapp/.tfvars/vault/config.tfvars` example/seed uses placeholder values and docs include a follow-up step to rotate to real credentials.
- [x] Secret rotation workflow: Terraform-managed via tfvars updates.
  Mark complete when: docs/runbook specify editing `/mnt/eapp/.tfvars/vault/config.tfvars` then rerunning `terraform/swarm/vault/config/pipeline/config.sh` (instead of manual `vault kv put`) for standard secret updates.
- [x] Seal script UX: no confirmation flag/prompt required.
  Mark complete when: `scripts/vault/seal.sh` performs immediate seal action on execution (with status logging) without `--yes` gating.
- [x] Config pipeline execution mode: single-run `terraform init/plan/apply` (same as existing Swarm pipelines).
  Mark complete when: `terraform/swarm/vault/config/pipeline/config.sh` performs init, plan, and apply in one invocation after successful auto-unseal.

## Stage 1 - app stage scaffold (Terraform)

- [x] Create stack entrypoint layout:
  - `terraform/swarm/vault/app`
  - `terraform/swarm/vault/app/pipeline/app.sh`
  Mark complete when: directories/files exist and wire up through shared swarm pipeline helpers (bash path only) without module indirection.
- [x] Implement Swarm app resources:
  - overlay network
  - persistent volume(s) for Vault data (Raft data directory)
  - Vault service definition with explicit image in resource (no local indirection)
  - single replica placement on `swarm-cp-0` (or equivalent constraint)
  - published Vault API/UI port (`8200`)
  - healthcheck and placement constraints/platforms
  Mark complete when: Terraform validation passes with no schema/provider errors for app stage configuration.
- [x] Render Vault server configuration for single-node integrated Raft.
  Mark complete when: app stage provides Vault config file/env wiring that sets listener/API address, `ui = true`, and `storage "raft"` against the persisted data path.
- [x] Define app outputs needed by operations/config stage (service name, address/port, namespace labels, etc.).
  Mark complete when: outputs are present and consumed/documented by downstream steps.

## Stage 2 - operational scripts (bootstrap/unseal/seal)

- [x] Add bootstrap script:
  - `scripts/vault/bootstrap.sh`
  - waits for Vault readiness
  - auto-creates `/mnt/eapp/.tfvars/vault/` when missing
  - checks initialization status first (idempotent no-op when already initialized)
  - hard-fails if Vault is already initialized but `/mnt/eapp/.tfvars/vault/init.json` is missing
  - runs `vault operator init -key-shares=3 -key-threshold=2 -format=json` via `docker exec` and writes output on host to `/mnt/eapp/.tfvars/vault/init.json`
  - overwrites local automation env file `/mnt/eapp/.tfvars/vault/.env` on every run for downstream steps
  - sets local artifact permissions per temporary policy (`chmod 775`)
  Mark complete when: rerunning bootstrap does not reinitialize Vault and all expected local files are created/validated.
- [x] Wire bootstrap execution into app deploy flow.
  Mark complete when: `terraform/swarm/vault/app/pipeline/app.sh` automatically runs `scripts/vault/bootstrap.sh` after successful apply.
- [x] Add app pipeline preflight checks.
  Mark complete when: `terraform/swarm/vault/app/pipeline/app.sh` validates target node/port assumptions (including host port `8200` availability) before Terraform apply.
- [x] Add app pipeline post-deploy health validation.
  Mark complete when: `terraform/swarm/vault/app/pipeline/app.sh` validates Vault health endpoint after apply/bootstrap and fails with actionable diagnostics on unhealthy state.
- [x] Add unseal script:
  - `scripts/vault/unseal.sh`
  - waits for Vault readiness
  - checks seal status first (idempotent no-op when already unsealed)
  - sources `/mnt/eapp/.tfvars/vault/.env` when present; otherwise logs fallback and uses `VAULT_ADDR=http://swarm-cp-0.local:8200`
  - emits explicit no-op status message when already unsealed
  - reads unseal key shares from `/mnt/eapp/.tfvars/vault/init.json` (or equivalent local bootstrap artifact)
  - runs non-interactively using the required number of key shares
  Mark complete when: running script twice is safe and second run no-ops cleanly.
- [x] Add seal script:
  - `scripts/vault/seal.sh`
  - defaults to local Vault service target
  - executes immediately without interactive confirmation prompt
  - validates target and authentication before sealing
  Mark complete when: script seals an unsealed instance and reports clear status/errors.
- [x] Add usage docs and safety notes:
  - where keys/tokens live (outside git, local-only under `/mnt/eapp/.tfvars/vault`)
  - expected operator flow: app apply (auto bootstrap) -> config apply (auto unseal + terraform apply)
  - standard secret updates: edit `/mnt/eapp/.tfvars/vault/config.tfvars` and rerun `config.sh`
  - manual fallback flow: `scripts/vault/unseal.sh` -> `config.sh`
  - no container mount of host `/mnt/eapp/.tfvars`; bootstrap captures output to host via `docker exec ... > /mnt/eapp/.tfvars/vault/init.json`
  - temporary artifact permission policy (`775`) and follow-up hardening task
  Mark complete when: docs include exact command examples and secret-handling warnings.

## Stage 3 - config stage scaffold (Terraform Vault provider)

- [x] Create stack entrypoint layout:
  - `terraform/swarm/vault/config`
  - `terraform/swarm/vault/config/pipeline/config.sh`
  Mark complete when: directories/files exist and pipeline wiring matches existing app/config services (bash path only) without module indirection.
- [x] Implement provider configuration and bootstrap inputs:
  - Vault address and root token sourced from local bootstrap artifacts/env (not repo-committed values)
  - day-1 endpoint defaults to HTTP (`http://...`) and consumes `/mnt/eapp/.tfvars/vault/.env` via automatic sourcing in `config.sh`
  - `config.sh` falls back to `VAULT_ADDR=http://swarm-cp-0.local:8200` if `.env` is missing, but fails fast when `VAULT_TOKEN` cannot be resolved
  - explicit precondition: `/mnt/eapp/.tfvars/vault/init.json` exists and Vault is reachable before config apply
  - config pipeline runs auto-unseal first; Terraform step hard-fails with clear guidance if Vault remains sealed
  Mark complete when: `terraform init/plan` succeeds only when bootstrap + unseal are complete; failure mode is clear when auto-unseal cannot resolve the seal state.
- [x] Add baseline declarative resources:
  - KV v2 mount for general secret storage (day 1 baseline)
  - tfvars schema for grouped secret values (map-of-maps-of-maps), for example:
    - `secrets.k8s.thelounge = { username = "...", password = "..." }`
    - (additional groups/secrets deferred until after day-1 rollout)
  - Terraform loop/flatten logic that writes each `<group>/<name>` entry as one KV secret object at `secret/<group>/<name>`
  - Terraform validations for `<group>` and `<name>` keys (lowercase alnum + `-`/`_` only; no `/`)
  - allow empty payload objects (`{}`) for initial placeholder entries
  - allow empty scalar values (`\"\"`) inside payload objects
  - enforce authoritative lifecycle: absent tfvars entries are destroyed in Vault by Terraform
  - document state exposure tradeoff (secret values live in Terraform state for this homelab pattern)
  - document that new groups are data-driven (for example `authenticators`) and require tfvars-only changes
  Mark complete when: adding a new secret object to tfvars produces only the expected incremental plan diff and applies without code changes.

## Stage 4 - pipeline strategy and Jenkins retirement

- [x] Inventory known Jenkins pipeline surfaces currently in repo:
  - `*.jenkins` wrappers under `terraform/swarm/**/pipeline/`
  - Jenkins job registry definitions under `terraform/module/jenkins/config`
  - documentation references that imply Jenkins is the primary path
  Mark complete when: an explicit inventory list is captured in implementation notes.
- [x] Remove or disable known Jenkins pipeline surfaces for now.
  Mark complete when: Jenkins wrappers/registry entries targeted by this effort are removed or clearly disabled, and no Vault work depends on Jenkins.
- [x] Define bash-first deployment runbook order in docs:
  - app pipeline (`app.sh`)
  - automatic bootstrap script invocation (`bootstrap.sh`) from app pipeline
  - config pipeline (`config.sh`) with automatic unseal invocation (`unseal.sh`)
  - optional manual script usage (`unseal.sh`, `seal.sh`) for operator interventions
  Mark complete when: sequence is documented in planning docs with copy/paste commands.
- [x] Ensure shell pipeline entrypoints use fixed Vault tfvars/backend inputs.
  Mark complete when: `app.sh` and `config.sh` use canonical `/mnt/eapp/.tfvars/vault/{app.tfvars,config.tfvars}` plus `/mnt/eapp/.tfvars/minio.backend.hcl` without per-run override switches.
- [x] Wire unseal into config pipeline flow.
  Mark complete when: `terraform/swarm/vault/config/pipeline/config.sh` calls `scripts/vault/unseal.sh` before Terraform `init/plan/apply`, logs explicit no-op when already unsealed, and exits immediately (without Terraform) if unseal fails.

## Stage 5 - validation and handoff

- [x] Agent validation evidence:
  - app plan/apply output
  - bootstrap/unseal/seal script dry-run or execution logs (redacted)
  - config plan/apply output
  Mark complete when: results are recorded in this plan (or linked notes) with pass/fail status.
- [x] Human validation checklist:
  - verify Vault UI/API reachable internally
  - read/write test secret through configured engine
  - restart scenario test (confirm expected reseal/unseal behavior for chosen mode)
  Mark complete when: each test has explicit outcome and date.
- [x] Final docs update:
  - add/update Vault docs in the current docs structure (or equivalent section)
  - cross-link from relevant workflow pages
  Mark complete when: documentation links resolve and reflect actual implemented behavior.

## Implementation notes (update as work progresses)

- Date: 2026-03-07
- Operator: Codex (with user direction)
- Scope change notes: Stage 1 through Stage 3 executed in sequence using direct stack resources only (module indirection removed). Stage 4 Jenkins-retirement cleanup completed. Stage 5 validation completed with additional runtime hardening fixes discovered during live rollout (Vault raft path alignment, entrypoint arg fix, healthcheck behavior, remote-docker script support).
- Command evidence (redacted):
  - `terraform fmt -recursive terraform/swarm/vault/app terraform/swarm/vault/config`
  - `terraform -chdir=terraform/swarm/vault/app init -backend=false -input=false`
  - `terraform -chdir=terraform/swarm/vault/app validate` (pass)
  - image pin lookup: `docker buildx imagetools inspect hashicorp/vault:1.21.4`
  - `bash -n scripts/vault/bootstrap.sh scripts/vault/unseal.sh scripts/vault/seal.sh terraform/swarm/vault/app/pipeline/app.sh` (pass)
  - `bash -n terraform/swarm/vault/config/pipeline/config.sh` (pass)
  - `terraform -chdir=terraform/swarm/vault/config init -backend=false -input=false`
  - `terraform -chdir=terraform/swarm/vault/config validate` (pass)
  - Jenkins inventory + removal:
    - removed all `terraform/**/*.jenkins` wrapper files (17 files across `cluster` + `swarm`)
    - set `local.jenkins_jobs`, `local.multi_stage_services`, and `local.single_stage_jobs` to empty maps in `terraform/module/jenkins/config/main.tf`
    - updated Docker Swarm workflow documentation to reflect bash-first workflow and Jenkins-wrapper disabled status
  - `terraform -chdir=terraform/module/jenkins/config init -backend=false -input=false`
  - `terraform -chdir=terraform/module/jenkins/config validate` (pass)
  - tfvars path proof:
    - `ls -ld /mnt/eapp/.tfvars /mnt/eapp/.tfvars/minio.backend.hcl`
    - `mkdir -p /mnt/eapp/.tfvars/vault && ls -ld /mnt/eapp/.tfvars/vault`
    - `ls -l /mnt/eapp/.tfvars/vault/app.tfvars /mnt/eapp/.tfvars/vault/config.tfvars`
  - runtime hardening during Stage 5:
    - updated app storage path to `/vault/file` (image entrypoint-managed permissions)
    - removed duplicate `-config` runtime arg from Vault container args
    - healthcheck now accepts `vault status` exit codes `0/1/2` to avoid restart loops before bootstrap
    - app preflight now fails on unreachable SSH manager target
    - bootstrap/unseal scripts auto-select local vs remote docker runtime (via SSH manager host)
  - live app pipeline validation:
    - `VAULT_SWARM_MANAGER_HOST=nodadyoushutup@192.168.1.26 VAULT_ADDR=http://127.0.0.1:18200 ./terraform/swarm/vault/app/pipeline/app.sh` (pass; no changes; bootstrap idempotent; health gate passed with HTTP 503)
  - live config pipeline validation:
    - `VAULT_SWARM_MANAGER_HOST=nodadyoushutup@192.168.1.26 ./terraform/swarm/vault/config/pipeline/config.sh` (pass; auto-unseal + KV mount + `secret/k8s/thelounge` apply)
    - repeated `config.sh` run returned no diff (`No changes`) and completed successfully
  - standalone script validation:
    - `./scripts/vault/seal.sh` (pass)
    - `VAULT_SWARM_MANAGER_HOST=nodadyoushutup@192.168.1.26 ./scripts/vault/unseal.sh` (pass)
    - second unseal run: no-op message confirmed ("already unsealed")
  - API/UI and secret validation:
    - `curl ... /v1/sys/health` via tunnel returned `200` (unsealed)
    - `curl ... /ui/` via tunnel returned `200`
    - `curl ... /v1/secret/data/k8s/thelounge` confirmed keys `username,password` and `username=admin`
  - restart behavior validation:
    - `docker service update --force vault` (via SSH manager)
    - post-restart `vault status` showed `Initialized=true`, `Sealed=true`
    - `unseal.sh` restored unsealed state successfully
- Open risks/follow-ups:
  - Day-1 environment currently uses local SSH tunnel (`127.0.0.1:18200`) from this control host to reach Vault API on `swarm-cp-0`; direct host-route reachability may vary by operator machine/network.
  - Temporary `775` artifact permissions remain intentionally permissive; tighten in a hardening follow-up.
