# Repo Rules

This document defines repo-wide rules that are not specific to one platform.

Use this for baseline repo behavior. Use
[`docs/rules/applications.md`](./applications.md),
[`docs/rules/kubernetes.md`](./kubernetes.md) and
[`docs/rules/terraform.md`](./terraform.md) for platform-specific rules.

## Docs-Driven Rule

This is a docs-driven repo.

- Treat `docs/` as the source of truth for repeatable repo rules and workflows.
- If a task depends on a documented workflow, follow the doc instead of
  inventing a local variant.
- If a change introduces a new stable pattern, update the relevant docs as part
  of the task.

## Legacy Docs Rule

- Legacy wiki docs were intentionally removed and are being rebuilt.
- Do not reference old wiki paths until replacement docs exist in `docs/`.

## Repo and Host Assumptions

- Repo path is `~/code/homelab` everywhere via NFS from `truenas.internal`.
- Use `python3` explicitly. Do not assume a `python` shim exists.
- Because of NFS `root_squash`, running repo scripts directly via `sudo` can
  fail with `Permission denied`; pipe them into `sudo bash -s` or copy them to
  `/tmp` first.

## Scope Control Rule

- Treat everything under `_old/` as out-of-scope legacy content unless a human
  explicitly asks for `_old/` work.
- Do not read, modify, refactor, lint, test, or include `_old/` files in normal
  agent changes.
- Do not add `_old/` to `.gitignore`.

## Git Hygiene Rule

- If unrelated untracked or modified files from other agents are present,
  ignore them and only stage, commit, or push files relevant to the current
  task unless a human explicitly asks otherwise.
- For normal repo work, it is acceptable and expected to stage relevant files,
  commit them, and push them after validation.
- For now, do not create a new branch unless a human explicitly asks for one.
- Use clear commit subjects that name the service, area, or intent instead of
  vague subjects such as `updates` or `misc changes`.

## Compose-Only Stack Rule

- The MinIO backend and Renovate stacks are compose-only.
- They run on `swarm-cp-0.local` under `applications/minio/` and
  `applications/renovate/`.
- Images used there must support `linux/aarch64`.

## Dataset Safety Rule

- Never delete, destroy, rename, or purge any TrueNAS/ZFS dataset in any pool.
- Never run destructive dataset actions through Terraform or shell, including
  `zfs destroy`, `midclt call pool.dataset.delete`, or equivalent operations.
- Creating new Kubernetes-related datasets is allowed only under `eapp`
  (for example `eapp/k8s/...`) and must not modify or remove existing datasets.
- Dataset deletion is manual-only by a human operator.
