# GitHub Actions Workflow

This document covers repo-managed GitHub Actions workflows that perform
repository maintenance.

Use [docs/workflows/git.md](./git.md) for the default change/publish flow and
[docs/rules/repo.md](./../rules/repo.md) for repo-wide safety rules.

## Purge Offline Repository Runners

The repository maintenance workflow for stale self-hosted runners lives at:

```text
.github/workflows/purge_offline_runners.yml
```

It exists to remove repository-level self-hosted runners whose GitHub status is
already `offline`.

Current behavior:

- runs on pushes that change `.github/workflows/**`
- runs on pushes that change `terraform/swarm/gha-runner*/**`
- runs nightly on a schedule
- can also be started manually through `workflow_dispatch`
- supports a `dry_run` input for listing offline runners without deleting them
- deletes only runners whose repository API status is exactly `offline`
- runs on `ubuntu-latest` so cleanup does not depend on the self-hosted runner
  pool being healthy

## Credential Requirement

GitHub's repository self-hosted runner delete endpoint requires repository
administration permission. Configure a repository secret named
`RUNNER_ADMIN_TOKEN` with a token that has the required repository admin access.

The workflow does not rely on `GITHUB_TOKEN` for runner administration.
GitHub's repository runner list/delete endpoints require repository
`Administration` permission, and that permission is outside the normal workflow
token permission set.

Behavior when the secret is missing:

- `push` and `schedule` runs log a warning and skip cleanup
- manual `workflow_dispatch` runs fail fast with an explicit setup message

## Validation

After changing this workflow:

1. Use manual dispatch with `dry_run=true` to confirm the workflow can list
   repository runners.
2. Confirm the workflow log shows the expected offline runner set.
3. Run the live path only when the listed offline runners are safe to remove.
