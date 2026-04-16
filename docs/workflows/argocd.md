# Argo CD Workflow

This document defines the operator workflow for repo-managed Argo CD changes and
for normal GitOps delivery of Kubernetes applications in this repo. Use
[docs/rules/argocd.md](./../rules/argocd.md) for the steady-state structure,
[docs/workflows/git.md](./git.md) for the default staging and push behavior,
[docs/workflows/kubernetes.md](./kubernetes.md) for workload-specific delivery,
and [docs/workflows/terraform.md](./terraform.md) when the Argo CD control
plane itself is managed through Terraform.

## Scope

Use this workflow when the task changes:

- Kubernetes workload manifests under `kubernetes/`
- repo-managed `AppProject` or `Application` objects under
  `kubernetes/argocd-management`
- repo-managed Argo CD config such as ingress, notifications, or secret wiring

Do not use this workflow as the primary execution path for
`terraform/cluster/argocd/config`; that stage follows the Terraform workflow.

## Standard GitOps Flow

For Kubernetes apps managed by Argo CD, the normal sequence is:

1. identify which layer owns the change
2. update all relevant repo files
3. validate locally before publishing
4. stage all files relevant to the change
5. create a clear commit
6. push the commit
7. watch Argo CD autosync the pushed revision
8. validate workload health and Argo CD sync state

The stable delivery path is commit plus push. Argo CD then reconciles the new
remote revision.

## Step 1: Choose the Owning Layer

Use the layer that already owns the behavior:

- `terraform/cluster/argocd/config` for the root app and Terraform-owned addon
  `ApplicationSet`
- `kubernetes/argocd-management` for repo-managed `AppProject`,
  `Application`, Argo CD ingress, notifications, and related manifests
- `kubernetes/<app>` or `kubernetes/<family>/overlays/<instance>` for the
  workload itself

If the change spans workload and Argo CD definitions, update both in one
coherent change.

## Step 2: Update the Full Change Set

Do not treat the workload directory as the only file set.

Common combinations:

- app-only change:
  `kubernetes/<app>/...`
- overlay plus application wiring:
  `kubernetes/<family>/overlays/<instance>/...` and
  `kubernetes/argocd-management/<instance>-app.yaml`
- new namespace family:
  workload manifests, `*-app.yaml`, and `*-project.yaml`
- stable process change:
  manifests plus matching docs under `docs/`

If Argo CD would need a changed `Application.spec.source.path`,
`destination.namespace`, or project whitelist, include that manifest change in
the same commit as the workload change.

## Step 3: Validate Locally Before Push

Validate the exact unit you changed before publishing it.

Examples:

```bash
kubectl kustomize kubernetes/qbittorrent/overlays/movie-10
kubectl apply --dry-run=server -f kubernetes/prowlarr/
kubectl apply --dry-run=server -f kubernetes/argocd-management/prowlarr-app.yaml
```

Useful checks:

- render output for Kustomize overlays
- schema or server dry-run validation
- secret path and namespace alignment
- ingress host and service target alignment
- `Application` path, project, and destination namespace correctness

## Step 4: Commit the Change Properly

Stage every file that is part of the Kubernetes/Argo CD change and only those
files.

Commit subject guidance should match the repo’s current style:

- `<service>: <change>`
- `argocd: <change>`

Examples:

- `radarr: tighten postgres startup ordering`
- `qbittorrent: add movie-11 overlay`
- `argocd: add autosync workflow docs`

Avoid vague commit titles such as `updates` or `fix stuff`.

## Step 5: Push and Let Argo CD Reconcile

Push the commit to the tracked remote branch so the revision referenced by Argo
CD exists remotely.

For repo-managed Kubernetes apps, this is the point where the change becomes
eligible for autosync. Until the push happens:

- Argo CD cannot fetch the revision
- an MCP inspection can only show the old remote state
- any manual local apply is temporary operator action, not the GitOps source of
  truth

## Step 6: Observe Sync and Health

After push, watch the application converge.

Common checks:

```bash
kubectl get applications.argoproj.io -n argocd
kubectl describe application -n argocd <app>
kubectl get pods -n <namespace>
kubectl get ingress,svc -n <namespace>
kubectl get externalsecret,secretstore -n <namespace>
```

If the Argo CD CLI or MCP server is available, use it to inspect:

- sync status
- health status
- last applied revision
- sync errors or diff details

## When MCP or Manual Actions Are Appropriate

Argo CD MCP or manual CLI actions are useful for:

- checking sync and health without leaving the repo workflow
- forcing a refresh when the remote revision was just pushed
- investigating a degraded application
- restarting or recovering control-plane components

Direct `kubectl apply`, `argocd app sync`, or other manual intervention is an
exception path for:

- first bootstrap before normal automation is established
- urgent recovery
- debugging a failing change

If you use a manual exception path, follow it with the real source-of-truth
change in Git and push that change as soon as possible.

## Validation Checklist

Before closing an Argo CD-backed Kubernetes change:

1. the workload manifests are committed
2. any needed `Application` or `AppProject` changes are committed
3. the commit is pushed
4. Argo CD shows the app synced to the expected revision
5. the workload is healthy in the target namespace
6. any related ingress, secret, storage, or database dependencies were checked

## Troubleshooting Direction

If the app does not converge after push, inspect in this order:

1. `Application` path, project, and destination namespace
2. Argo CD sync errors or permission denials
3. missing CRDs or sync-wave ordering issues
4. workload pod failures in the destination namespace
5. secrets, storage, service, and ingress dependencies

For repo-wide disruption, also verify the Argo CD control plane itself:

- `argocd-server`
- `argocd-repo-server`
- `argocd-application-controller`
