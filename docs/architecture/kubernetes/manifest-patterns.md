# Kubernetes manifest patterns

How workloads under **`kubernetes/<app>/`** are shaped and wired into Argo CD.
Read [placement.md](./placement.md) first when adding a service — **classify the
workload and pick a node** before choosing a pattern.

GitOps registration steps live in [argocd/applications-and-sync-waves.md](../argocd/applications-and-sync-waves.md)
— this file covers **manifest layout** only.

## Plain manifest directory

A set of `*.yaml` files at `kubernetes/<name>/` with no Kustomization. Argo
syncs the directory recursively.

**Good for:** small stacks, first-party apps, single-instance media apps.

**Examples:** `kubernetes/langgraph/`, `kubernetes/radarr/`, `kubernetes/seerr/`.

Typical files: `namespace.yaml`, `deployment.yaml`, `service.yaml`,
`ingress.yaml`, `secretstore.yaml`, `externalsecret.yaml`, optional
`postgres-deployment.yaml`.

Use **`argocd.argoproj.io/sync-wave`** on resources so dependencies apply in
order (namespace → secrets → database → app). LangGraph and media apps commonly
use wave `"30"` for the main Deployment.

## Helm values only (`values.yaml` + optional `namespace.yaml`)

The chart lives **upstream**; this repo holds values (and sometimes extra
namespace manifests). Argo **`Application`** uses **multi-source** `spec.sources`:

1. Upstream Helm chart + `helm.valueFiles` pointing at this repo.
2. Git path ref (`$values/kubernetes/<addon>/values.yaml`).
3. Optional third source for extra manifests under `kubernetes/<addon>/`.

**Examples:** `kubernetes/metallb/`, `kubernetes/ingress-nginx/`,
`kubernetes/external-secrets/`, `kubernetes/democratic-csi-iscsi/`.

See `kubernetes/argocd-management/applications/metallb.yaml` for the
`$values/...` ref pattern.

## Kustomize (`base/` + `overlays/`)

Use when **many instances** share most of the spec but differ by namespace,
node, env, or secrets.

**Layout:**

```
kubernetes/qbittorrent/
  base/
    kustomization.yaml
    deployment.yaml
    ...
  overlays/
    movie-0/
      kustomization.yaml
      deployment-node-patch.yaml
    ...
```

Root `kustomization.yaml` may aggregate overlays (see `kubernetes/cross-seed/`).
Argo targets **one overlay path per `Application`**.

**Examples:** `kubernetes/qbittorrent/`, `kubernetes/cross-seed/`.

Node spreading: each overlay’s `deployment-node-patch.yaml` — see
[placement.md](./placement.md).

## Hybrid Helm + Git manifests

Some add-ons ship upstream Helm **and** extra manifests from this repo in one
Argo `Application`.

**Example:** `kubernetes/velero/` (`values.yaml`, `vui-values.yaml`,
`manifests/*.yaml`) — multiple charts plus a Git manifest source.

## External Secrets

| Layer | Location |
| --- | --- |
| **Operator install** | `kubernetes/external-secrets/` (Helm values pattern) |
| **Per-app stores** | `secretstore.yaml` + `externalsecret.yaml` beside the app |

Do not commit raw secret values. Use `*.example.yaml` where the repo already
does for operator or store config.

Cluster-wide credentials for the operator are separate from per-app
`ExternalSecret` paths.

## Relationship to `applications/`

| Repo path | Role |
| --- | --- |
| **`applications/<app>/`** | Source code, Docker build context, image publish target |
| **`kubernetes/<workload>/`** | Runtime contract — replicas, env, volumes, ingress, probes, image pin |

Image tags in Kubernetes manifests (or Helm values) must match what **CI**
publishes. After `docker_build_push.yml` succeeds, bump the pin, commit, push,
and Argo sync — [docker-build-github-actions.md](../../workflows/docker-build-github-actions.md).

**Build in `applications/`, run in `kubernetes/`** — same split as Swarm’s
`applications/` + `terraform/swarm/`, but manifests instead of Terraform
`main.tf` for image pins.

## Pick a neighbor

| If you are adding… | Mirror |
| --- | --- |
| Platform Helm add-on | `kubernetes/metallb/` + `argocd-management/applications/metallb.yaml` |
| Single media / web app | `kubernetes/radarr/` or `kubernetes/thelounge/` |
| First-party Deployment + Ingress | `kubernetes/langgraph/` |
| Many similar instances | `kubernetes/qbittorrent/overlays/` |
| App with local Postgres | `kubernetes/radarr/` (`postgres-deployment.yaml` pattern) |

Do not introduce a new delivery style when an existing neighbor already matches.

## What belongs in Git vs operator config

| Concern | Location |
| --- | --- |
| Deployments, Services, Ingress, PVCs | `kubernetes/<app>/` |
| Container **image** tag or digest | Manifest `image:` or Helm `values.yaml` in repo |
| Live secret **values** | Vault / secret backend via External Secrets — not committed |
| Argo `Application` + `AppProject` | `kubernetes/argocd-management/applications/<app>.yaml` |
| Bootstrap root Application | `kubernetes/bootstrap/` (one-time seed only) |
