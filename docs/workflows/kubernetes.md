# Kubernetes Workflows

This document describes how Kubernetes changes are actually delivered and
validated in this repo. Use [docs/rules/kubernetes.md](./../rules/kubernetes.md)
for the steady-state layout and guardrails. If the first question is whether a
new app belongs in Kubernetes or Swarm, start with
[docs/workflows/new-application.md](./new-application.md).
Use [docs/workflows/application-networking.md](./application-networking.md) for
the standard domain, DNS, and reverse-proxy flow.

## Standard Delivery Flow

Kubernetes changes usually follow this pattern:

1. update manifests under `kubernetes/`
2. if needed, add or update Argo CD `AppProject` and `Application` objects under
   `kubernetes/argocd-management`
3. apply the manifests directly with `kubectl apply` for immediate rollout or validation
4. verify the workload is healthy
5. allow Argo CD to reconcile from Git afterward

This repo does not treat "wait for GitOps eventually" as the only deployment
path during active work.

## Choosing the Right Pattern

For a new Kubernetes app, first assess whether an upstream `Helm` chart is a
real fit or whether the workload should be a repo-owned custom app. In this
repo, most application workloads should stay repo-owned because direct `nfs:`
mounts, local asset wiring, and app-specific container layout are usually
clearer in our own manifests than through a chart.

Use Helm when the chart already matches the desired deployment shape with small
value overrides. The repo examples are `k10` and `snapshot-controller`.

Use a repo-owned custom app when the workload needs direct storage bindings,
custom containers, or tighter control of the manifests. The repo examples are
`radarr`, `sonarr`, `privatebin`, `clusterplex`, and `qbittorrent`.

If the repo-owned custom path is chosen, the human must still explicitly say
whether it is a `standard app` or a `Kustomize app`. Agents should not make
that shape choice on their own.

### Add or update a single-instance app

Use a plain app directory when the workload is mostly self-contained.

Typical flow:

1. create or update `namespace.yaml`
2. add secrets manifests if needed
3. add storage manifests if needed
4. add `deployment.yaml`, `service.yaml`, and `ingress.yaml` as needed
5. create or update the matching `AppProject` and `Application`
6. apply and validate

Reference-style apps already in the repo include:

- `prowlarr`
- `radarr`
- `sonarr`
- `seerr`
- `privatebin`

### Add or update a multi-instance family

Use `base/` plus `overlays/` when the human has said the workload is a
`Kustomize app` and the repo expects many similar instances.

For the repo-specific pattern, use
[docs/workflows/kubernetes-kustomize-patterns.md](./kubernetes-kustomize-patterns.md).

Typical flow:

1. update the shared base
2. create or update the per-instance overlay
3. wire runtime-specific values with patches or replacements
4. add or update the matching Argo CD `Application`
5. apply the overlay and validate that instance

`qbittorrent` is the main reference implementation for a `Kustomize app`
pattern.

## Argo CD Workflow

When onboarding a new app to Argo CD:

1. create or update `kubernetes/argocd-management/<service>-project.yaml`
2. create or update `kubernetes/argocd-management/<service>-app.yaml`
3. set `spec.source.path` to the concrete app directory or overlay path
4. keep the Argo destination namespace aligned with the workload namespace
5. apply the Argo CD resources

The bootstrap chain is:

1. `kubernetes/bootstrap/argocd-management-app.yaml` seeds the root app
2. `kubernetes/argocd-management` defines projects and applications
3. those applications point at the actual workload directories

## Direct Apply Workflow

For immediate rollout or troubleshooting, apply the Kubernetes manifests
directly instead of waiting for Argo CD to notice Git changes.

Examples:

```bash
kubectl apply -f kubernetes/prowlarr/
kubectl apply -f kubernetes/argocd-management/prowlarr-project.yaml
kubectl apply -f kubernetes/argocd-management/prowlarr-app.yaml
kubectl apply -k kubernetes/qbittorrent/overlays/movie-0
```

Use `-f` for `standard app` flat manifest folders and `-k` for `Kustomize app`
overlays or roots.

## Validation Workflow

After applying a change, validate the thing you actually changed.

Common checks:

- `kubectl get pods -n <namespace>`
- `kubectl describe pod -n <namespace> <pod>`
- `kubectl logs -n <namespace> <pod>`
- `kubectl get ingress -n <namespace>`
- `kubectl get svc -n <namespace>`
- `kubectl get externalsecret,secretstore -n <namespace>`

Validate in dependency order:

1. namespace and secrets
2. storage
3. backing database, if present
4. primary deployment
5. service reachability
6. ingress or external routing

## Secret and Database Workflow

For the detailed Vault -> External Secrets workflow, use
[docs/workflows/kubernetes-vault-secrets.md](./kubernetes-vault-secrets.md).

The short version is:

1. update `/mnt/eapp/.tfvars/vault/config.tfvars`
2. run `terraform/swarm/vault/config/pipeline/config.sh`
3. apply `SecretStore`
4. apply `ExternalSecret`
5. confirm the generated Kubernetes `Secret` exists
6. apply the database init `ConfigMap`, if present
7. apply the postgres deployment and service
8. apply the main application deployment

Validate the secret chain before debugging the workload:

- `kubectl get secretstore,externalsecret -n <namespace>`
- `kubectl get secret -n <namespace>`
- `kubectl describe externalsecret -n <namespace> <name>`

## Endpoint Workflow

When the app exposes an HTTP endpoint:

1. add or update the Kubernetes `Ingress`
2. add or update Nginx Proxy Manager tfvars
3. add or update Cloudflare tfvars
4. run the Terraform edge stages
5. validate the final hostname with `curl` or equivalent

Default the DNS target to an internal RFC1918 address unless a human explicitly
asks for public exposure.

Every app that is intended to be reachable through a domain must have explicit
bound subdomains created in code.

The Kubernetes manifest alone is not the full delivery workflow for a public app.

## Torrent Workflow

For BitTorrent clients such as qBittorrent:

1. expose peer traffic with a dedicated `NodePort` service for TCP and UDP
2. keep the per-instance torrent port and nodePort values unique
3. update FortiGate VIP and WAN-to-LAN policy code
4. apply the Kubernetes manifests
5. apply the FortiGate Terraform stages
6. validate both internal `nodeIP:nodePort` reachability and external public
   forwarded-port reachability

Do not route torrent peer traffic through Nginx Proxy Manager.

## After Cluster-Level Disruption

If the work disrupted the cluster broadly, do not stop at workload validation.
Also verify Argo CD recovered:

- `argocd-server`
- `argocd-repo-server`
- `argocd-application-controller`
- application health and sync status

This is required before closing out broad cluster-impacting work.
