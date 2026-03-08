# Argo CD notifications + Terraform ownership plan

This plan tracks two linked goals:

1. Add Discord notifications for Argo CD using Vault + External Secrets, delivered through the existing app-of-apps/ApplicationSet flow.
2. Move Argo CD control-plane config objects (`Application`/`ApplicationSet`) to Terraform ownership while keeping the same app-of-apps behavior.

## How to use this plan

- Every task starts unchecked (`[ ]`).
- When completed, mark it checked (`[x]`).
- A task is complete only when its "Mark complete when" condition is true.
- Keep implementation notes updated with command evidence and outcomes so work can resume safely after context compaction.

## Stage 0 - scope lock and preflight

- [x] Confirm final architecture:
  - bootstrap/install script remains minimal (install Argo CD, admin creds, repo auth, terminal enablement)
  - day-2 Argo CD config ownership moves to Terraform
  - app-of-apps behavior remains via `ApplicationSet`
  Mark complete when: this file reflects accepted architecture and no conflicting plan is in progress.
- [x] Confirm current live baseline and capture evidence:
  - `kubectl -n argocd get applications`
  - `kubectl -n argocd get applicationsets`
  - `kubectl -n argocd get pods`
  Mark complete when: baseline health/status is recorded in Implementation notes.
- [x] Restore/validate ArgoCD MCP auth session for discovery/export tasks.
  Mark complete when: MCP calls can read `argocd-bootstrap` and `homelab-addons` successfully.

## Stage 1 - Vault-backed notifications wiring (GitOps-managed)

- [x] Add Vault secret payload in `/mnt/eapp/.tfvars/vault/config.tfvars` for path `secret/k8s/argocd` with key `discord_webhook_url`.
  Mark complete when: Vault config pipeline applies and `secret/k8s/argocd` returns expected key.
- [x] Create Argo notifications manifests under `kubernetes/argocd-notifications/`:
  - `secretstore.yaml` (namespace `argocd`, Vault provider)
  - `externalsecret.yaml` (target `argocd-notifications-secret`, key `discord-webhook-url`)
  - `notifications-cm.yaml` (Discord webhook service/template/trigger definitions)
  Mark complete when: manifests exist and lint cleanly.
- [ ] Add `argocd-notifications` child app entry to `kubernetes/argocd/app-of-apps.yaml` with sync wave after `external-secrets`.
  Mark complete when: ApplicationSet renders and syncs the new child app without CRD ordering errors.
- [x] Ensure namespace-local Vault reader secret bootstrap path exists for `argocd` namespace (installer-managed or documented one-time bootstrap command).
  Mark complete when: `argocd-vault-reader` secret exists with `VAULT_TOKEN` key in `argocd`.

## Stage 2 - Notifications validation

- [x] Verify External Secret lifecycle:
  - `kubectl -n argocd get externalsecret`
  - `kubectl -n argocd get secret argocd-notifications-secret -o yaml`
  Mark complete when: `ExternalSecret` is Ready and target secret contains `discord-webhook-url`.
- [x] Verify notifications controller config uptake:
  - `kubectl -n argocd logs deploy/argocd-notifications-controller`
  Mark complete when: no config/templating errors are present.
- [x] Trigger a controlled Argo app event and confirm Discord message delivery.
  Mark complete when: at least one expected notification appears in the target Discord channel.
- [x] Confirm no regression in Argo CD core health.
  Mark complete when: `argocd-server`, `argocd-repo-server`, `argocd-application-controller`, and apps remain healthy/synced.

## Stage 3 - Terraform scaffold for Argo CD config ownership

- [x] Create Terraform stack layout for Argo CD config (cluster-side, not Swarm app runtime):
  - `terraform/cluster/argocd/config`
  - `terraform/cluster/argocd/config/pipeline/config.sh`
  Mark complete when: stack and pipeline entrypoint exist and follow repo pipeline conventions.
- [x] Add provider and variables for Argo CD API auth in the new stack:
  - provider `argoproj-labs/argocd`
  - tfvars inputs for base URL/token/insecure toggle
  Mark complete when: `terraform init` and `terraform validate` pass.
- [x] Model current live objects in Terraform resources:
  - `argocd_application` for `argocd-bootstrap`
  - `argocd_application_set` for `homelab-addons`
  Mark complete when: HCL matches live intent and plan is stable pre-import.

## Stage 4 - Import, cutover, and ownership handoff

- [x] Import live Argo resources into Terraform state.
  Mark complete when: imports succeed and no recreate/destructive drift appears.
- [x] Run plan/apply to confirm Terraform owns current state without behavior change.
  Mark complete when: apply is no-op or expected metadata-only updates.
- [x] Remove duplicate YAML ownership for migrated objects from GitOps path to avoid controller contention.
  Mark complete when: only one controller owns each object.
- [x] Verify post-cutover health and sync behavior.
  Mark complete when: generated child applications and sync behavior remain unchanged.

## Stage 5 - docs and operator workflow updates

- [ ] Update operator runbook for:
  - where to rotate Discord webhook (Vault path)
  - how auto-refresh propagates via External Secrets
  - Terraform workflow for Argo CD config changes
  Mark complete when: docs include exact command paths and expected outcomes.
- [ ] Add rollback notes:
  - disable trigger/subscription
  - revert Terraform-managed objects to YAML ownership (if needed)
  Mark complete when: rollback path is documented and tested at least once in dry run.

## Implementation notes

- Date: 2026-03-08
- Operator: Codex + user
- Scope notes:
  - User confirmed preference to preserve app-of-apps behavior.
  - User confirmed this plan is the continuity anchor to avoid context-compaction loss.
  - User confirmed Terraform should manage Argo CD control objects while preserving ApplicationSet behavior.
- Current observed baseline:
  - `argocd-bootstrap` application is `Synced/Healthy`.
  - `homelab-addons` ApplicationSet exists and child apps are `Synced/Healthy`.
  - `argocd-notifications-controller` pod is running.
  - `argocd-notifications-cm` and `argocd-notifications-secret` are currently default/empty.
- Stage 0 execution evidence:
  - `kubectl -n argocd get applications.argoproj.io -o wide` (all listed apps `Synced/Healthy`)
  - `kubectl -n argocd get applicationsets.argoproj.io -o wide` (`homelab-addons` present)
  - `kubectl -n argocd get pods -o wide` (Argo core + notifications controller Running)
  - Rotated `mcp-argocd` token and updated `/mnt/eapp/.tfvars/mcp-argocd/app.tfvars`.
  - Ran `./terraform/swarm/mcp-argocd/app/pipeline/app.sh` (apply completed: `0 added, 1 changed, 0 destroyed`).
  - Verified Swarm task status via `ssh swarm-cp-0.local docker service ps mcp-argocd --no-trunc` (current task Running).
  - Performed hard reset `ssh swarm-cp-0.local docker service scale mcp-argocd=0 && ...=1`; service converged healthy with new task.
  - Post-reset MCP calls still failed with client-held session error: `Invalid or expired session ID ...`.
  - `curl -sk -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -X POST https://mcp.argocd.nodadyoushutup.com/mcp --data-binary @/tmp/mcp_init.json` returned `200` + new `mcp-session-id`.
  - `tools/call` `get_application` for `argocd-bootstrap` succeeded (`Synced/Healthy` payload returned).
  - `tools/call` `get_application_managed_resources` for `argocd-bootstrap` with filters `kind=ApplicationSet,name=homelab-addons` succeeded (live/target state returned for `homelab-addons`).
  - Stage 0 is complete; continuing with Stage 1.
  - Added `k8s/argocd.discord_webhook_url` in `/mnt/eapp/.tfvars/vault/config.tfvars`.
  - Current `discord_webhook_url` value is placeholder (`https://discord.com/api/webhooks/REPLACE_ME`) and must be replaced with the real Discord webhook URL before Stage 2 delivery validation.
  - Ran `./terraform/swarm/vault/config/pipeline/config.sh` (apply completed: `1 added, 0 changed, 0 destroyed`).
  - Verified Vault payload via `curl ... /v1/secret/data/k8s/argocd` (`keys=discord_webhook_url`).
  - Created namespace-local reader secret with one-time bootstrap command:
    - `source /mnt/eapp/.tfvars/vault/.env && kubectl -n argocd create secret generic argocd-vault-reader --from-literal=VAULT_TOKEN=\"$VAULT_TOKEN\" --dry-run=client -o yaml | kubectl apply -f -`
  - Confirmed bootstrap secret key exists (`kubectl -n argocd get secret argocd-vault-reader -o jsonpath='{.data.VAULT_TOKEN}' | wc -c` -> non-zero).
  - Added manifests under `kubernetes/argocd-notifications/` and validated with `kubectl apply --dry-run=server -f kubernetes/argocd-notifications`.
  - Applied notifications manifests live (`kubectl apply -f kubernetes/argocd-notifications`) and confirmed:
    - `SecretStore argocd-vault` is `Valid/Ready`
    - `ExternalSecret argocd-notifications-secret` is `SecretSynced/Ready`
    - `argocd-notifications-secret` contains `discord-webhook-url`
  - Added `argocd-notifications` ApplicationSet element in `kubernetes/argocd/app-of-apps.yaml` with sync wave `29` (after `external-secrets`).
  - Applied local `app-of-apps.yaml` for immediate validation; ApplicationSet controller generated the child app once, but Argo bootstrap self-heal reconciled back to Git HEAD and removed it because the repo change is not pushed yet.
  - Updated notification trigger subscriptions to only `on-sync-failed-discord` and `on-health-degraded-discord` to avoid sync-success noise.
  - Updated notification `when` guards to be nil-safe (`app.status != nil ...`) to prevent templating errors on newly-created apps.
  - Stage 2 lifecycle checks:
    - `kubectl -n argocd get externalsecret argocd-notifications-secret -o wide` -> `SecretSynced`, `READY=True`
    - `kubectl -n argocd get secret argocd-notifications-secret -o yaml` -> includes `data.discord-webhook-url`
  - Stage 2 controller uptake checks:
    - `kubectl -n argocd logs deploy/argocd-notifications-controller --since=40s | rg "failed to execute when condition|cannot fetch|config referenced|notification service 'webhook' is not supported"` -> no matches.
  - Stage 2 controlled event:
    - Created temporary `Application` `argocd-notify-probe` with an invalid source path and forced sync operation to produce a controlled sync-failure condition.
    - Notification trigger fired for `argocd-notify-probe` (`Trigger 'on-sync-failed-discord' TRIGGERED`) and attempted outbound POST to configured Discord webhook URL.
    - After webhook rotation, a new probe (`argocd-notify-probe-1773005341`) triggered `on-sync-failed-discord` and performed outbound webhook POST without notification-delivery errors in controller logs.
    - User confirmed the Discord message arrived in `#argocd` (screenshot evidence in chat, March 8, 2026).
    - Deleted probe app after validation (`kubectl -n argocd delete application argocd-notify-probe --wait=true`).
  - Stage 2 Argo core health check:
    - `kubectl -n argocd get pods -o wide` -> `argocd-server`, `argocd-repo-server`, `argocd-application-controller`, `argocd-notifications-controller` all Running.
    - `kubectl -n argocd get applications -o wide` / `kubectl -n argocd get applicationsets -o wide` -> existing apps remain `Synced/Healthy`, `homelab-addons` present.
  - Stage 3 scaffolded Terraform stack at `terraform/cluster/argocd/config` with:
    - `provider.tf` (S3 backend key `argocd-config.tfstate`, provider `argoproj-labs/argocd` v`7.15.0`)
    - `variables.tf` (`argocd_base_url`, `argocd_api_token`, `argocd_insecure_skip_verify`)
    - `main.tf` resources for `argocd_application.argocd_bootstrap` and `argocd_application_set.homelab_addons`
    - `pipeline/config.sh` using repo-standard `scripts/terraform/swarm_pipeline.sh` entrypoint pattern.
  - Stage 3 live object export refresh:
    - `kubectl -n argocd get application argocd-bootstrap -o yaml > /tmp/argocd-bootstrap.live.yaml`
    - `kubectl -n argocd get applicationset homelab-addons -o yaml > /tmp/homelab-addons.live.yaml`
  - Stage 3 tfvars wiring:
    - Created `/mnt/eapp/.tfvars/argocd/config.tfvars` from existing MCP Argo CD credentials (`argocd_base_url`, `argocd_api_token`, `argocd_insecure_skip_verify`).
  - Stage 3 validation/plan evidence:
    - `terraform -chdir=terraform/cluster/argocd/config init -backend=false -input=false` succeeded.
    - `terraform -chdir=terraform/cluster/argocd/config validate` succeeded.
    - `terraform -chdir=terraform/cluster/argocd/config init -reconfigure -input=false -backend-config=/mnt/eapp/.tfvars/minio.backend.hcl` succeeded.
    - `terraform -chdir=terraform/cluster/argocd/config plan -input=false -refresh=false -var-file=/mnt/eapp/.tfvars/argocd/config.tfvars` returned stable pre-import result: `2 to add, 0 to change, 0 to destroy`.
  - Provider schema nuance handled in Stage 3:
    - `argocd_application_set.spec.template.spec` requires at least one `source` block in Terraform schema; base template source was added and helm branch sets `source: null` in `template_patch` before defining `sources` to preserve live generated app behavior.
  - Stage 4 import evidence:
    - `terraform -chdir=terraform/cluster/argocd/config import ... argocd_application.argocd_bootstrap argocd-bootstrap:argocd` succeeded.
    - `terraform -chdir=terraform/cluster/argocd/config import ... argocd_application_set.homelab_addons homelab-addons:argocd` succeeded.
    - Import ID format is `name:namespace` for both resources.
  - Stage 4 provider/auth adjustments:
    - Updated provider config to normalize `argocd_base_url` into host-only `server_addr` and enabled `grpc_web = true` for ingress-backed Argo CD API access.
    - Added `lifecycle.ignore_changes` for `argocd_application_set.homelab_addons` fields that are controller/provider-normalized (`metadata.annotations`, `spec.template_patch`) to keep plans stable after import.
  - Stage 4 ownership cutover actions:
    - Deleted Git-owned duplicate manifest [`kubernetes/argocd/app-of-apps.yaml`].
    - Applied live cutover guard on bootstrap app:
      - `kubectl -n argocd patch application argocd-bootstrap --type=merge -p '{"spec":{"source":{"directory":{"exclude":"app-of-apps.yaml"}}}}'`
    - Removed legacy tracking annotation from live ApplicationSet:
      - `kubectl -n argocd annotate applicationset homelab-addons argocd.argoproj.io/tracking-id- --overwrite`
  - Stage 4 convergence/health evidence:
    - `terraform -chdir=terraform/cluster/argocd/config plan -input=false -var-file=/mnt/eapp/.tfvars/argocd/config.tfvars` -> `No changes.`
    - `kubectl -n argocd get application argocd-bootstrap -o wide` -> `Synced/Healthy`.
    - `kubectl -n argocd get applications -o wide` -> generated child applications remain `Synced/Healthy`.
    - `kubectl -n argocd get pods -o wide` -> Argo core components remain Running.
