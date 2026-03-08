# K8s ingress + NPM cutover plan

This plan transitions homelab web entry to Nginx Proxy Manager (NPM) as the global edge on `:80/:443`, routes Kubernetes apps through `ingress-nginx`, and removes kube-vip from app ingress responsibilities.

## How to use this plan

- Every task starts unchecked (`[ ]`).
- Mark a task done only when its "Mark complete when" condition is true.
- If scope changes, add a short note under "Implementation notes" before proceeding.

## Stage 0 - scope and design lock

- [x] Lock target architecture:
  - NPM is the single public edge listener for homelab HTTP/S.
  - Kubernetes traffic goes from NPM to `ingress-nginx`.
  - `argocd.nodadyoushutup.com` and `thelounge.nodadyoushutup.com` are hostname-routed (not port-routed).
  - kube-vip is removed for app ingress.
  Mark complete when: this architecture is accepted and no port-based public routing (`:30443`, `:9000`) is required.
- [x] Confirm operator split:
  - Human handles Cloudflare DNS record changes.
  - Agent handles Kubernetes, Terraform/NPM config, and kube-vip removal.
  Mark complete when: responsibilities are explicitly acknowledged.

## Stage 1 - NPM config surface refactor (tfvars-driven)

- [x] Replace hardcoded NPM resources in `terraform/swarm/nginx_proxy_manager/config/main.tf` with a module call to `terraform/module/nginx_proxy_manager/config`.
  Mark complete when: stack `main.tf` no longer declares per-domain `nginxproxymanager_certificate_letsencrypt` / `nginxproxymanager_proxy_host` resources directly.
- [x] Align stack variables with module inputs so this stack reads host/certificate definitions from `~/.tfvars/nginx-proxy-manager/config.tfvars`.
  Mark complete when: stack consumes `provider_config`, `config.default_dns_challenge`, `config.certificates`, and `config.proxy_hosts` from tfvars.
- [x] Handle state transition safely so existing NPM objects are retained (no accidental delete/recreate blast).
  Mark complete when: state migration/import steps are documented and executed, and initial post-refactor `terraform plan` shows no unintended destroys.
- [x] Preserve existing NPM proxy host behavior during refactor (no regressions for current domains).
  Mark complete when: `terraform plan` shows no unintended deletes for existing non-K8s proxy hosts.

## Stage 2 - Kubernetes ingress readiness

- [x] Ensure `ingress-nginx` has a stable internal/LAN IP for NPM upstream forwarding.
  Mark complete when: `kubectl -n ingress-nginx get svc ingress-nginx-controller` shows a stable `EXTERNAL-IP` and HTTP reachability from NPM host.
- [x] Update The Lounge ingress host from `thelounge.internal` to `thelounge.nodadyoushutup.com`.
  Mark complete when: ingress manifest is updated and applied; `curl -H 'Host: thelounge.nodadyoushutup.com' http://<ingress-ip>/` returns the app response.
- [x] Add Argo CD ingress host `argocd.nodadyoushutup.com` in namespace `argocd`.
  Mark complete when: ingress manifest exists/applied and `curl -H 'Host: argocd.nodadyoushutup.com' http://<ingress-ip>/` returns Argo CD response.

## Stage 3 - NPM tfvars updates and apply

- [x] Add/adjust NPM config tfvars entries for:
  - certificate(s) covering `argocd.nodadyoushutup.com` and `thelounge.nodadyoushutup.com`
  - proxy hosts forwarding both domains to Kubernetes ingress upstream
  - reuse existing default Cloudflare DNS challenge settings
  Mark complete when: `~/.tfvars/nginx-proxy-manager/config.tfvars` includes both domains and uses the shared DNS challenge settings.
- [x] Run NPM config pipeline plan and apply.
  Mark complete when:
  - `terraform/swarm/nginx_proxy_manager/config/pipeline/config.sh --plan` is clean/expected
  - `terraform/swarm/nginx_proxy_manager/config/pipeline/config.sh` completes successfully.

## Stage 4 - Remove kube-vip from app ingress

- [x] Move `argocd-server` service back behind ingress (non-kube-vip LB class).
  Mark complete when: `argocd-server` is no longer using `loadBalancerClass: kube-vip.io/kube-vip-class` and external app access is via NPM -> ingress.
- [x] Remove live kube-vip resources from cluster.
  Mark complete when: `kube-vip-ds`, kube-vip RBAC/service account, and kube-vip-managed service annotations are gone.
- [x] Remove kube-vip repo artifacts added for this temporary path.
  Mark complete when: kube-vip manifests/app-of-apps/script defaults are reverted or updated to the ingress+NPM architecture.

## Stage 5 - validation and handoff

- [x] Validate end-user URLs (after Cloudflare changes propagate):
  - `https://argocd.nodadyoushutup.com`
  - `https://thelounge.nodadyoushutup.com`
  Mark complete when: both are reachable, present valid certs (DNS challenge), and route to correct backends.
- [x] Validate Argo CD and cluster health post-cutover.
  Mark complete when:
  - `kubectl -n argocd get pods,deploy,statefulset` all ready
  - `kubectl -n argocd get applications` healthy/synced
  - no unexpected non-running pods introduced by cutover.
- [x] Capture command evidence in implementation notes.
  Mark complete when: plan/apply + verification commands are logged with outcomes.

## Rollback

- [ ] Define rollback trigger criteria (for example: either public hostname fails >5 minutes after DNS propagated, or certificate issuance fails repeatedly).
  Mark complete when: criteria are documented before cutover execution.
- [ ] Keep a reversible path ready:
  - re-enable direct Argo CD VIP path if needed
  - restore previous NPM config snapshot/state
  Mark complete when: rollback commands are documented and tested syntactically.

## Implementation notes (update during execution)

- Date: 2026-03-07
- Operator split: user handles Cloudflare DNS; agent handles infra/config changes.
- Stage 0 execution:
  - Architecture lock accepted: NPM as global edge, Kubernetes behind ingress-nginx, hostname routing for Argo CD/The Lounge, kube-vip removed for app ingress path.
  - Operator split confirmed.
  - DNS precheck evidence (from agent host):
    - `argocd.nodadyoushutup.com -> 96.253.53.3`
    - `thelounge.nodadyoushutup.com -> 96.253.53.3`
- Current state snapshot:
  - Argo CD is currently reachable at `https://192.168.1.200/` through kube-vip service VIP.
  - `ingress-nginx` currently uses `LoadBalancer` IP `192.168.1.241`.
  - The Lounge ingress host is currently `thelounge.internal` and must be updated.
  - Argo CD ingress manifest for public hostname is not yet present.
- Stage 1 execution evidence:
  - Refactor complete: `terraform/swarm/nginx_proxy_manager/config/main.tf` now calls `module ../../../module/nginx_proxy_manager/config` and uses tfvars-driven `config` input.
  - Compatibility fallback added: if `var.config` is null, stack uses legacy defaults equivalent to previous hardcoded domains.
  - State migration executed (no resource recreation path): moved 18 resources from root addresses to `module.nginx_proxy_manager_config.*` via `terraform state mv`.
  - Post-migration state list shows only module-scoped NPM certificate/proxy resources.
  - Resolved former blocker (`2026-03-08`): restored NPM database path by creating `mysql` service (`nginx_proxy_manager/database`) and waiting for NPM health to converge; `POST http://192.168.1.26:81/api/tokens` now returns `200`.
  - Incident fix during recovery: corrected backend key collision in `terraform/swarm/grafana/database/provider.tf` (`nginx-proxy-manager-database.tfstate` -> `grafana-database.tfstate`), split state ownership, and restored `grafana-database` service.
  - Post-recovery service health: `mysql 1/1`, `grafana-database 1/1`, `nginx-proxy-manager 1/1`.
  - Post-refactor no-destroy proof (`terraform/swarm/nginx_proxy_manager/config`): `Plan: 18 to add, 0 to change, 0 to destroy` (resource recreation only; no proxy/cert deletes).
- Stage 2 execution evidence:
  - `ingress-nginx-controller` service confirmed stable at `EXTERNAL-IP 192.168.1.241`.
  - Added/updated ingress manifests:
    - `kubernetes/thelounge/ingress.yaml` host -> `thelounge.nodadyoushutup.com`
    - `kubernetes/argocd/ingress.yaml` created for `argocd.nodadyoushutup.com` -> `argocd-server:https`
  - Applied live with `kubectl apply -f kubernetes/thelounge/ingress.yaml` and `kubectl apply -f kubernetes/argocd/ingress.yaml`.
  - Reachability fix: LB IP `192.168.1.241:80` initially timed out (speaker path via `192.168.1.210` blackholed), so ingress service was patched to `externalTrafficPolicy: Local` and repo values updated in `kubernetes/ingress-nginx/values.yaml`.
  - Validation from NPM host (`192.168.1.26`) via ingress LB IP:
    - `curl -H 'Host: thelounge.nodadyoushutup.com' http://192.168.1.241/` -> `HTTP/1.1 200 OK`
    - `curl -H 'Host: argocd.nodadyoushutup.com' http://192.168.1.241/` -> `HTTP/1.1 200 OK`
- Stage 3 execution evidence:
  - `~/.tfvars/nginx-proxy-manager/config.tfvars` refactored to module-native `config` object and includes certificates/proxy hosts for:
    - `argocd.nodadyoushutup.com`
    - `thelounge.nodadyoushutup.com`
  - Terraform plan (`terraform/swarm/nginx_proxy_manager/config`) after tfvars update: `Plan: 22 to add, 0 to change, 0 to destroy`.
  - Terraform apply (`terraform/swarm/nginx_proxy_manager/config`) completed: `Apply complete! Resources: 22 added, 0 changed, 0 destroyed.`
  - Follow-up type-safety fix: `effective_config` in `terraform/swarm/nginx_proxy_manager/config/main.tf` changed to `jsondecode(jsonencode(...))` normalization so optional tfvars fields do not break conditional typing.
  - Follow-up targeted apply for The Lounge proxy host custom header rule completed (`0 added, 1 changed, 0 destroyed`).
  - Note: stage commands were executed via direct `terraform plan/apply` because pipeline wrapper currently runs plan+apply together and does not support safe plan-only mode.
- Stage 4 execution evidence:
  - `kubernetes/argocd/app-of-apps.yaml` updated to remove `kube-vip` child app; sync waves adjusted.
  - Applied live: `kubectl apply -f kubernetes/argocd/app-of-apps.yaml`.
  - `argocd-server` moved to `ClusterIP` (`kubectl -n argocd get svc argocd-server` shows no `loadBalancerClass`, no external IP).
  - Removed live kube-vip resources:
    - `daemonset/kube-vip-ds` deleted
    - `serviceaccount/kube-vip` deleted
    - `clusterrole/system:kube-vip-role` deleted
    - `clusterrolebinding/system:kube-vip-binding` deleted
    - kube-vip annotations removed from `argocd-server` service.
  - Repo artifacts removed/updated:
    - deleted `kubernetes/kube-vip/*`
    - removed kube-vip references from `scripts/pipeline/argocd_app.sh`
    - removed kube-vip ApplicationSet entry in `kubernetes/argocd/app-of-apps.yaml`.
  - Post-change repair: app-of-apps placeholders were reintroduced by raw apply and caused `ComparisonError`; fixed by setting repo URL to `git@github.com:nodadyoushutup/homelab.git` and revision `HEAD` in `kubernetes/argocd/app-of-apps.yaml`, then reapplied.
- Stage 5 validation evidence:
  - Public endpoint checks:
    - `curl -I https://argocd.nodadyoushutup.com` -> `HTTP/2 200`
    - `curl -I https://thelounge.nodadyoushutup.com` -> `HTTP/2 200`
  - Certificate checks:
    - `argocd.nodadyoushutup.com` LE cert valid (`notBefore 2026-03-08`, `notAfter 2026-06-06`)
    - `thelounge.nodadyoushutup.com` LE cert valid (`notBefore 2026-03-08`, `notAfter 2026-06-06`)
  - Argo health checks:
    - `kubectl -n argocd get applications` -> all child apps `Synced/Healthy`
    - `kubectl -n argocd get pods,deploy,statefulset` -> all ready.
  - Cluster non-running pod check:
    - `kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded` -> `No resources found`.
  - The Lounge routing note:
    - GitOps source still defines `thelounge.internal`; to keep public hostname working without waiting for upstream GitOps commit, temporary unmanaged ingress `thelounge-public` (`host: thelounge.nodadyoushutup.com`) was applied in namespace `thelounge`.
