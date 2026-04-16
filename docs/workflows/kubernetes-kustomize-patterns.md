# Kubernetes Kustomize Patterns

This document describes the repo pattern for multi-instance Kubernetes
applications built with `base/` plus `overlays/`, using
[`kubernetes/qbittorrent`](/mnt/eapp/code/homelab/kubernetes/qbittorrent:1) as
the main reference implementation.

Use [docs/workflows/kubernetes.md](./kubernetes.md) for the broader Kubernetes
delivery flow and [docs/rules/kubernetes.md](./../rules/kubernetes.md) for
layout and guardrails.

## When This Pattern Is Used

Use this pattern when:

- there are many near-identical app instances
- the workload shape is stable
- instance differences are mostly namespace, hostname, ports, node placement,
  and secrets
- copying full manifest trees would create drift

In this repo, `qbittorrent` is the main example. The same pattern also appears
in other multi-instance families.

## High-Level Shape

The qBittorrent family is structured like this:

```text
kubernetes/qbittorrent/
  base/
    kustomization.yaml
    deployment.yaml
    service.yaml
    service-torrent-nodeport.yaml
    ingress.yaml
    pvc.yaml
    qbittorrent-config-template.yaml
  overlays/
    movie-0/
      kustomization.yaml
      namespace.yaml
      runtime-config.yaml
      ingress-patch.yaml
      deployment-node-patch.yaml
      secretstore.yaml
      externalsecret.yaml
    movie-10/
      ...
    television-0/
      ...
  kustomization.yaml
```

Reference files:

- base root:
  [`kubernetes/qbittorrent/base/kustomization.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/base/kustomization.yaml:1)
- family aggregate:
  [`kubernetes/qbittorrent/kustomization.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/kustomization.yaml:1)
- example overlay:
  [`kubernetes/qbittorrent/overlays/movie-10/kustomization.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/overlays/movie-10/kustomization.yaml:1)

## Base Responsibilities

The base contains the resources that are shared by every instance:

- deployment shape
- persistent volume claim
- HTTP service
- torrent `NodePort` service
- ingress skeleton
- config template used by the init container

That means the base should stay generic. It should not hardcode per-instance:

- namespace
- hostname
- node assignment
- unique torrent ports
- unique `nodePort` values
- instance-specific Vault secret path

Concrete examples:

- the base deployment defines a generic `qbittorrent` workload and default
  ports:
  [`kubernetes/qbittorrent/base/deployment.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/base/deployment.yaml:1)
- the base ingress uses a placeholder host:
  [`kubernetes/qbittorrent/base/ingress.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/base/ingress.yaml:1)
- the base torrent service defines default `NodePort` values that overlays
  replace:
  [`kubernetes/qbittorrent/base/service-torrent-nodeport.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/base/service-torrent-nodeport.yaml:1)

## Overlay Responsibilities

Each overlay owns the instance-specific parts.

For qBittorrent, every overlay normally contains seven files:

- `kustomization.yaml`
- `namespace.yaml`
- `runtime-config.yaml`
- `ingress-patch.yaml`
- `deployment-node-patch.yaml`
- `secretstore.yaml`
- `externalsecret.yaml`

Example overlay:

- [`kubernetes/qbittorrent/overlays/movie-10`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/overlays/movie-10:1)

### `namespace.yaml`

Defines the namespace and instance labels.

Example:

- [`kubernetes/qbittorrent/overlays/movie-0/namespace.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/overlays/movie-0/namespace.yaml:1)

### `runtime-config.yaml`

Defines the per-instance runtime values that Kustomize fans out into multiple
resources:

- `WEBUI_PORT`
- `TORRENTING_PORT`
- `TORRENTING_NODE_PORT_TCP`
- `TORRENTING_NODE_PORT_UDP`

Examples:

- [`movie-0/runtime-config.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/overlays/movie-0/runtime-config.yaml:1)
- [`movie-10/runtime-config.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/overlays/movie-10/runtime-config.yaml:1)
- [`television-0/runtime-config.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/overlays/television-0/runtime-config.yaml:1)

### `ingress-patch.yaml`

Overrides the host for the instance.

Example:

- [`kubernetes/qbittorrent/overlays/movie-10/ingress-patch.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/overlays/movie-10/ingress-patch.yaml:1)

### `deployment-node-patch.yaml`

Pins the workload to the target node.

Example:

- [`kubernetes/qbittorrent/overlays/movie-0/deployment-node-patch.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/overlays/movie-0/deployment-node-patch.yaml:1)

### `secretstore.yaml` and `externalsecret.yaml`

Wire the instance to Vault through External Secrets.

Examples:

- [`kubernetes/qbittorrent/overlays/movie-10/secretstore.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/overlays/movie-10/secretstore.yaml:1)
- [`kubernetes/qbittorrent/overlays/movie-10/externalsecret.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/overlays/movie-10/externalsecret.yaml:1)

For the detailed Vault workflow, use
[docs/workflows/kubernetes-vault-secrets.md](./kubernetes-vault-secrets.md).

## How the Overlay Works

The overlay kustomization does four things:

1. imports the shared base
2. adds overlay-only resources such as namespace, runtime config, and secret
   wiring
3. applies small patches for hostname and node placement
4. uses `replacements` to copy runtime values into every resource that needs
   them

Example:

- [`kubernetes/qbittorrent/overlays/movie-0/kustomization.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/overlays/movie-0/kustomization.yaml:1)

The important detail is that the overlay does not duplicate the deployment or
service manifests. It only supplies the values and patches that differ.

## Replacement Pattern

The qBittorrent overlays use `replacements` instead of duplicating port values
in many files.

Source object:

- `ConfigMap/qbittorrent-runtime`

Values copied from that ConfigMap:

- `WEBUI_PORT`
- `TORRENTING_PORT`
- `TORRENTING_NODE_PORT_TCP`
- `TORRENTING_NODE_PORT_UDP`

Those values are pushed into:

- deployment container ports
- service ports
- ingress backend service port
- torrent `NodePort` values

This keeps one source of truth for each instance’s port mapping.

For example, in `movie-10`:

- `TORRENTING_PORT` is `10106`
- `TORRENTING_NODE_PORT_TCP` is `32106`
- `TORRENTING_NODE_PORT_UDP` is `32206`

After `kubectl kustomize`, those values appear in the rendered deployment and
services instead of the base defaults.

## Runtime Config vs Render-Time Config

qBittorrent uses two configuration layers:

1. Kustomize replacement-time configuration through `runtime-config.yaml`
2. container startup-time configuration through the init container

The base deployment’s init container:

- reads `WEBUI_PORT` and `TORRENTING_PORT` from `qbittorrent-runtime`
- reads `WEBUI_PASSWORD_PBKDF2` from `qbittorrent-secrets`
- renders `qBittorrent.conf` from the template ConfigMap

Reference files:

- deployment:
  [`kubernetes/qbittorrent/base/deployment.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/base/deployment.yaml:1)
- template:
  [`kubernetes/qbittorrent/base/qbittorrent-config-template.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/base/qbittorrent-config-template.yaml:1)

That split is intentional:

- Kustomize handles resource wiring across manifests
- the init container handles app-specific config file rendering

## What Belongs in Base vs Overlay

Put something in `base/` when it is structurally true for every instance.

Good base candidates:

- main deployment shape
- common probes
- common PVC definition
- common service names
- common media mount layout
- generic ingress/service skeletons
- config template content

Put something in the overlay when it varies by instance.

Good overlay candidates:

- namespace
- hostname
- node selector override
- unique torrent/listener ports
- unique `NodePort` values
- secret path references
- instance labels

If a change would cause every overlay to repeat the same YAML block, it usually
belongs in `base/`.

## Family Aggregate vs Instance Entry Point

The top-level
[`kubernetes/qbittorrent/kustomization.yaml`](/mnt/eapp/code/homelab/kubernetes/qbittorrent/kustomization.yaml:1)
aggregates all overlays into one family root.

That file is useful for:

- viewing the entire family layout
- rendering or auditing the whole family at once

But the operational deployment unit is normally the individual overlay.

Direct apply example:

```bash
kubectl apply -k kubernetes/qbittorrent/overlays/movie-10
```

Rendered output example:

```bash
kubectl kustomize kubernetes/qbittorrent/overlays/movie-10
```

## Argo CD Pattern

Each qBittorrent instance is usually its own Argo CD `Application` pointing at
one overlay path, not at the family root.

Reference app:

- [`kubernetes/argocd-management/qbittorrent-movie-10-app.yaml`](/mnt/eapp/code/homelab/kubernetes/argocd-management/qbittorrent-movie-10-app.yaml:1)

The shared project whitelists all qBittorrent namespaces:

- [`kubernetes/argocd-management/qbittorrent-project.yaml`](/mnt/eapp/code/homelab/kubernetes/argocd-management/qbittorrent-project.yaml:1)

That means the normal delivery unit is:

- one overlay directory
- one Argo CD `Application`
- one destination namespace

## Standard Workflow For a New Instance

To add a new instance following this pattern:

1. create `kubernetes/qbittorrent/overlays/<instance>/`
2. copy a nearby overlay that matches the same family shape
3. update `namespace.yaml`
4. update `runtime-config.yaml`
5. update `ingress-patch.yaml`
6. update `deployment-node-patch.yaml` if node placement changes
7. update `externalsecret.yaml` to the correct Vault path and property names
8. add the overlay path to `kubernetes/qbittorrent/kustomization.yaml`
9. add or update the Argo CD `Application` for that overlay
10. update the qBittorrent `AppProject` destinations if the namespace is new
11. apply the overlay directly with `kubectl apply -k ...`
12. validate the rendered app, service, ingress, `NodePort`, and secrets

## Validation Checklist

For an overlay change, validate the rendered output before live apply:

```bash
kubectl kustomize kubernetes/qbittorrent/overlays/<instance>
```

Check that the render includes the expected:

- namespace
- ingress host
- deployment node selector
- service ports
- torrent `NodePort` values
- `ExternalSecret` path

Then apply:

```bash
kubectl apply -k kubernetes/qbittorrent/overlays/<instance>
```

Then validate live:

```bash
kubectl get pods -n <namespace>
kubectl get svc -n <namespace>
kubectl get ingress -n <namespace>
kubectl get externalsecret,secretstore -n <namespace>
```

For torrent-facing instances, also validate the direct port mapping end to end.

## qBittorrent-Specific Notes

- The base defines both the regular service and the torrent `NodePort` service,
  because every instance needs both.
- The overlay `runtime-config.yaml` is the source of truth for port fan-out.
- The ingress host is intentionally patched per instance instead of generated.
- The node pin is intentionally a small overlay patch rather than a per-instance
  copy of the whole deployment.
- The secret path should follow the Vault workflow doc. Some older overlays use
  legacy deeper Vault key paths, but new work should follow the supported
  tfvars-driven key shape.

## Anti-Patterns

Do not use this pattern in these ways:

- copying the full base manifests into every overlay
- hardcoding per-instance ports directly into the base
- making the family root the only Argo CD deployment target when each instance
  needs independent sync and ownership
- introducing runtime values in multiple files when one `runtime-config.yaml`
  can drive replacements
- adding new instance-specific secrets directly as plain Kubernetes `Secret`
  manifests when the family already uses Vault + External Secrets
