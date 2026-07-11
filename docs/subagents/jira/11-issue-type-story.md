# Story Issue Type (homelab)

Use for **`Story`** on **`HOME`**. Lifecycle transitions: **`02-issue-flows.md`**;
requirements: **`05-requirements-stage.md`**; fields: **`04-home-project-fields.md`**.

## Field metadata (sampled)

- **`customfield_10103`** **`Requirements`**, **`customfield_10104`** **`Acceptance Criteria`** ( **`REQUIREMENTS`** ).
- **`customfield_10105`** **`Workflow Impact`**, **`customfield_10106`** **`Technical Notes`** ( **`TECH LEAD`** ).
- Integration-style fields (**`Development`**, **`Rank`**, **`Design`**, **`Issue color`**, etc.)—do not set manually unless the user asks or Jira requires it.

## Gates (HOME)

- Before leaving **`REQUIREMENTS`:** populated **`10103`**, matching **`10104`**, one
  subtask per requirement.
- Before leaving **`TECH LEAD`:** **`10105`** and **`10106`** populated.
- Before leaving **`DEVELOPMENT`:** GitHub PR submitted for the story work.
- Post-review default **`DEPLOY`**; optional **`TEST`** per user; then **`DONE`**.

## Defaults

- Default net-new type when unspecified; prefer **`Story`** for features and
  non-bug change (**`jira_system_prompt.md`** issue-type section).
