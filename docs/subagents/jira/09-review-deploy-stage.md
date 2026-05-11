# Review And Deploy Stages (homelab)

Generic review / optional test / deploy / done behavior is in
**`jira_system_prompt.md`**. This file names **`HOME`** statuses after a PR exists.

- Failed review: **`CODE REVIEW` → `DEVELOPMENT`**.
- Passed or approved: default **`CODE REVIEW` → `DEPLOY`**.
- User-requested testing: use **`TEST`** when Jira exposes it, then **`DEPLOY`**.
- **`DEPLOY`:** follow repo workflow docs and tools for the change’s rollout path;
  avoid invented ceremony when impact is low.
- Complete: **`DEPLOY` → `DONE`** when deployment or finalization is finished.
- Always prefer live transitions; report blockers.
