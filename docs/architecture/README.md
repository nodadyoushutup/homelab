# Architecture docs

Short, **topic-per-file** notes about how this repository is organized. They
complement execution workflows under `docs/workflows/` and the technology shelf
under `docs/resources/`.

## Topics

| File | What it covers |
| --- | --- |
| [01-repository-layout.md](./01-repository-layout.md) | Top-level directories, what belongs where, and how major areas relate. |
| [02-terraform-layout.md](./02-terraform-layout.md) | `terraform/` domains, the **`app` / `config` / `database`** slice pattern, and helper modules. |
| [03-kubernetes-layout.md](./03-kubernetes-layout.md) | `kubernetes/` folders, manifest patterns (plain YAML, Helm values, Kustomize), and link to `applications/`. |
| [04-argocd-gitops.md](./04-argocd-gitops.md) | Argo CD: bootstrap, `argocd-management`, AppProject vs Application, sync waves, ApplicationSet add-ons, Terraform’s role. |
| [05-democratic-csi-truenas-iscsi.md](./05-democratic-csi-truenas-iscsi.md) | TrueNAS-backed **block** storage: democratic-csi iSCSI driver, ZFS zvols, StorageClass, snapshots, contrast with NFS CSI. |

## Related material

- Terraform conventions (including slice file layout) are spelled out for the
  Code specialist in
  [`docs/subagents/code/12-terraform.md`](../subagents/code/12-terraform.md).
  The architecture notes stay high-level; that file is the detailed checklist
  when editing HCL.
