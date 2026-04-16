# Git Workflow

This document defines the default Git workflow for normal repo changes. Use
[docs/rules/repo.md](./../rules/repo.md) for repo-wide Git rules and safety
constraints. Use platform workflows such as
[docs/workflows/kubernetes.md](./kubernetes.md),
[docs/workflows/argocd.md](./argocd.md), and
[docs/workflows/terraform.md](./terraform.md) for platform-specific validation
before the Git publish step.

## Standard Flow

For normal code or docs changes in this repo:

1. make the change
2. validate the thing you changed
3. stage all files relevant to that change
4. create a clear commit
5. push the commit to the current branch

For now, do not create a new branch unless a human explicitly asks for one.

## Staging Rule

Stage the files that are actually part of the change.

Typical examples:

- implementation files
- matching tests
- matching docs when the stable pattern changed
- related deployment wiring when the change spans runtime and delivery config

Do not leave obviously related files unstaged when they are part of the same
change. Do not stage unrelated work just because it is already present in the
working tree.

## Commit Rule

Use a short commit subject that names the service or area and the intent.

Current repo patterns include:

- `clusterplex: enable local relay for stable distributed transcodes`
- `metallb: harden speaker/controller probes and scheduling priority`
- `k10: scope ignore-differences to probes only`
- `docs: rework Argo CD and Git workflows`

Good shapes:

- `<service>: <change>`
- `docs: <change>`

Avoid subjects such as:

- `updates`
- `fixes`
- `misc changes`

## Push Rule

After committing, push to the current tracked branch.

In this repo, commit-only local state is usually not enough to finish the task:

- Argo CD cannot reconcile unpushed Kubernetes changes
- GitHub Actions cannot react to unpushed workflow-triggering changes
- another operator cannot inspect the new revision remotely

The default expectation is that a completed change is staged, committed, and
pushed unless a human explicitly asks to stop before push.

## Branch Rule

For now, stay on the current branch. Do not create a new branch as part of the
default workflow.

If the repo is already on a feature branch, continue on that branch unless a
human asks to change it.

## Validation Before Push

Use the smallest validation that closes the risk of the change.

Examples:

- run targeted tests for code changes
- render or dry-run Kubernetes manifests
- run the relevant Terraform stage plan/apply flow
- lint or syntax-check docs/scripts if the task depends on them

Do not skip validation when the platform workflow already defines the required
checks.

## When Not To Push Yet

Pause before push only when:

- a human explicitly asked for a patch without publishing it
- validation is still incomplete
- unrelated repo state needs clarification first

Otherwise, pushing the finished commit is the normal end state.
