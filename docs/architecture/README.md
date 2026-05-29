# Architecture docs

Short, **topic-per-file** notes about how this repository is organized. They
complement execution workflows under `docs/workflows/` and the technology shelf
under `docs/resources/`.

## Topics

| File | What it covers |
| --- | --- |
| [01-repository-layout.md](./01-repository-layout.md) | Top-level directories, what belongs where, and how major areas relate. |
| [terraform/](./terraform/README.md) | **`terraform/`** layout: [index](./terraform/README.md), [Swarm placement](./terraform/swarm-placement.md), [Swarm slices](./terraform/swarm-slices.md). |
| [kubernetes/](./kubernetes/README.md) | **`kubernetes/`** layout: [index](./kubernetes/README.md), [placement](./kubernetes/placement.md), [manifest patterns](./kubernetes/manifest-patterns.md). |
| [argocd/](./argocd/README.md) | **Argo CD / GitOps**: [layout](./argocd/gitops-layout.md), [applications & sync waves](./argocd/applications-and-sync-waves.md), [TrueNAS iSCSI storage](./argocd/storage-truenas-iscsi.md). |

## Related material

- Terraform layout and Swarm guides: [`terraform/`](./terraform/README.md).
- Kubernetes layout and placement: [`kubernetes/`](./kubernetes/README.md).
- Argo CD GitOps and TrueNAS storage: [`argocd/`](./argocd/README.md).
- Terraform HCL conventions for the Code specialist:
  [`docs/subagents/code/12-terraform.md`](../subagents/code/12-terraform.md).
  Architecture notes stay high-level; that file is the detailed checklist when
  editing HCL.
