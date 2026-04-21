# New Application Workflow

This document defines the standard workflow for adding a new application to
this repo.

Use [`docs/rules/applications.md`](./../rules/applications.md) to decide
whether the new app is a `Swarm app` or a `Cluster app`. Use the platform
workflows linked here for the detailed delivery mechanics after that choice.
Use [`docs/workflows/application-networking.md`](./application-networking.md)
when the app is expected to be reachable by domain.

## Standard Flow

When a request says "add a new app", follow this sequence:

1. classify the app as `Swarm app` or `Cluster app`
2. if it is a `Cluster app`, assess whether an upstream `Helm` chart is an easy
   fit or whether a repo-owned custom app is the better pattern
3. if it is a repo-owned custom app, get explicit human direction on
   `standard app` versus `Kustomize app`
4. choose the repo pattern that matches that class
5. implement the workload in the correct directory tree
6. add edge routing and DNS in code if the app exposes a public endpoint
7. apply the change using the platform workflow
8. validate the live result
9. update docs if the app introduces a new stable pattern

Do not start by creating manifests or Terraform files before the platform
decision is explicit. For new Kubernetes apps, do not skip the `Helm` versus
repo-owned custom app assessment, and do not choose `standard app` versus
`Kustomize app` without explicit human direction when the custom-app path is
chosen.

## Step 1: Classify The App

Use [`docs/rules/applications.md`](./../rules/applications.md) first.

Short version:

- choose `Swarm app` for infrastructure, observability, management tooling, or
  anything that should survive Kubernetes failure
- allow a `Cluster app` exception when the human explicitly chooses the
  emerging Kubernetes MCP pattern for a new server such as `mcp-filesystem` or
  `mcp-fortigate` or `mcp-terraform`
- choose `Cluster app` for almost everything else

If the reason for Swarm is weak or mostly convenience, use Kubernetes.

## Step 2: Choose The Repo Pattern

### Swarm app pattern

Use Swarm when the app belongs under `terraform/swarm/`.

Common shapes:

- single-stage service: `terraform/swarm/<service>/app`
- multi-stage service: `terraform/swarm/<service>/{database,app,config}`
- optional image source: `applications/<service>/`

Reference services:

- single-stage: `dozzle/app`, `loki/app`
- multi-stage: `terraform/swarm/grafana/{database,app,config}`,
  `harbor/{app,config}`, `nginx_proxy_manager/{database,app,config}`

If the new Swarm app is an MCP server, use
[`docs/rules/mcp-servers.md`](./../rules/mcp-servers.md) and
[`docs/workflows/mcp-servers.md`](./mcp-servers.md) after choosing the Swarm
pattern.

For custom MCP servers, expect to add `applications/<service>/` when the
upstream needs a repo-local HTTP wrapper or proxy variant so the host Codex
client can consume it by hostname.

### Cluster app pattern

Use Kubernetes when the app belongs under `kubernetes/`.

For a new Kubernetes app, first decide whether this should be a Helm-backed app
or a repo-owned custom app. Most application workloads in this repo should stay
repo-owned because direct `nfs:` mounts and app-specific container or asset
wiring are usually easier to express in our own manifests than through an
upstream chart.

For a new repo-owned Kubernetes app, the `standard app` versus `Kustomize app`
choice is still gated by explicit human input. Agents must not choose that app
shape themselves.

Common shapes:

- Helm-backed app or addon: `kubernetes/<app>/values.yaml` plus any companion
  manifests, with Argo CD pointing at `spec.source.chart`
- Helm-backed wrapper chart: `kubernetes/<app>/{Chart.yaml,values.yaml,templates/}`
  when an upstream chart is still the source of the runtime but the repo needs
  local manifests or wants values to remain repo-owned
- repo-owned `standard app`: `kubernetes/<app>/`
- repo-owned `Kustomize app`: `kubernetes/<family>/base` plus
  `kubernetes/<family>/overlays/<instance>`
- Argo CD objects: `kubernetes/argocd-management/<service>-project.yaml` and
  `kubernetes/argocd-management/<service>-app.yaml`

Reference services:

- Helm-backed: `kubernetes/argocd-management/k10-app.yaml`,
  `kubernetes/argocd-management/snapshot-controller-app.yaml`
- repo-owned `standard app`: `kubernetes/prowlarr`, `radarr`, `privatebin`,
  `clusterplex`, `mcp-ast-grep`, `mcp-bash-pipeline`, `mcp-fortigate`,
  `mcp-git`, `mcp-github`, `mcp-terraform`
- repo-owned `Kustomize app`: `kubernetes/qbittorrent`,
  `kubernetes/cross-seed`

## Step 3A: Implement A Swarm App

For a new Swarm app:

1. create the Terraform stage directory or directories under
   `terraform/swarm/<service>/`
2. add `main.tf`, `provider.tf`, `variables.tf`, and a pipeline entrypoint under
   `pipeline/`
3. define the image directly in the resource instead of abstracting it to a
   local
4. if the app needs its own image build context, add `applications/<service>/`
5. add or update the matching tfvars under `/mnt/eapp/.tfvars/<service>/`
6. if the service has dependency order, keep it explicit as
   `database -> app -> config` or `app -> config`
7. run the stage pipeline scripts
8. validate the running service

Use [`docs/workflows/terraform.md`](./terraform.md) for stage execution and
[`docs/rules/terraform.md`](./../rules/terraform.md) for structure rules.

## Step 3B: Implement A Cluster App

For a new Cluster app:

1. assess `Helm` versus repo-owned custom app before writing manifests
2. if the workload needs direct `nfs:` mounts, repo-specific assets, or
   app-specific container wiring, prefer the repo-owned custom path
3. if using the repo-owned custom path, get explicit human direction on
   `standard app` versus `Kustomize app`
4. create the workload directory under `kubernetes/`
5. if it is a Helm-backed app, add `values.yaml` and any companion manifests
   that the chart needs
6. if it is a `standard app`, use `kubernetes/<app>/`
7. if it is a `Kustomize app`, use `kubernetes/<family>/base` plus
   `kubernetes/<family>/overlays/<instance>`
8. add `namespace.yaml`
9. add secrets manifests if needed
10. add storage and database manifests if needed
11. add `deployment.yaml`, `service.yaml`, and `ingress.yaml` as needed when
    the workload is repo-owned
12. if this is a new Argo CD app family, add the matching `AppProject` and
    `Application` files under `kubernetes/argocd-management`
13. validate the workload manifests locally with render or dry-run checks
14. commit all relevant workload and Argo CD files with a clear commit subject
15. push and let Argo CD autosync the new revision
16. validate the workload and Argo CD application state

Use [`docs/workflows/kubernetes.md`](./kubernetes.md) for the main flow,
[`docs/workflows/argocd.md`](./argocd.md) for the GitOps commit/push flow,
[`docs/workflows/kubernetes-kustomize-patterns.md`](./kubernetes-kustomize-patterns.md)
for `Kustomize app` families, and
[`docs/rules/kubernetes.md`](./../rules/kubernetes.md) for structure rules.

## Step 4: Handle Secrets And Storage

Pick the existing platform pattern instead of inventing a new one.

Swarm:

- use the service's Terraform inputs and existing secret/config handling
- keep stage-specific tfvars and companion config files under
  `/mnt/eapp/.tfvars/<service>/`

Cluster:

- prefer the existing Vault plus External Secrets pattern where applicable
- use `secretstore.yaml` plus `externalsecret.yaml` when the app fits that
  model
- create new Kubernetes-related datasets only under `eapp/k8s/...`

For the detailed Kubernetes secret flow, use
[`docs/workflows/kubernetes-vault-secrets.md`](./kubernetes-vault-secrets.md).

## Step 5: Add Edge Routing When Needed

If the app exposes an external HTTP endpoint:

1. add or update the workload-side ingress or published app target
2. update `/mnt/eapp/.tfvars/nginx-proxy-manager/config.tfvars`
3. update `/mnt/eapp/.tfvars/cloudflare/config.tfvars`
4. run the Terraform edge stages
5. validate the final domain with `curl` or equivalent

Default new app hostnames to internal-only DNS targets unless a human
explicitly asks for public exposure or the app follows the documented MCP
hostname pattern.

Every app that is expected to be reachable through a domain must have explicit
bound subdomains created in code. Do not rely on only the wildcard record.

This applies to both Swarm and Cluster apps.

If the app is an MCP server, the delivery is not complete until the hostname
and `~/.codex/config.toml` entry are both aligned with the final MCP route.

If the app is a BitTorrent client, do not use the HTTP route flow for peer
traffic. Follow the direct L4 forwarding workflow instead.

## Step 6: Validate In Platform Order

Validate the thing you changed in dependency order.

Swarm:

1. dependency stage, if any
2. app stage
3. config stage, if any
4. public route, if any

Cluster:

1. namespace and secrets
2. storage
3. database, if any
4. app deployment
5. service reachability
6. ingress and public route, if any
7. Argo CD application health, if applicable

## Step 7: Close The Task Cleanly

Before considering the app onboarding done:

- the platform decision is documented in the change itself
- the implementation lives only in the correct repo area
- external routing and DNS are in code if needed
- the final domain was tested successfully if the app is meant to be reachable
  through a hostname
- live validation was performed
- any new repeatable pattern is added to `docs/`
