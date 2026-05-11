# Jira Issue Flows (homelab)

Generic net-new vs update rules, intake habits, transition minimalism, and ADF
comment pitfalls are in **`jira_system_prompt.md`**. This file is the **HOME**
workflow graph and default project behavior.

## Defaults

- Unspecified project/board → **`Homelab` / `HOME`** (see **`01-runtime.md`**).
- Net-new issues start in backlog **`TO DO`**. Default issue type **`Story`** when
  the user does not specify (see **`03-workflow-types.md`** and **`11`–`14`**).

## New issue flow

- Create in **`TO DO`** with short summary and baseline description; full
  scoping happens in **`REQUIREMENTS`** (**`05-requirements-stage.md`**).
- After creation, ask about moving to the active board and starting **only** if
  the user did not already express immediate-start intent.
- With immediate-start intent: create, then move off backlog into active work, then
  transition to **`REQUIREMENTS`** (or the closest valid transition if Jira
  exposes different names—use live transitions, do not invent moves).
- For **`Story`**, **`Bug`**, and **`Task`**, **`REQUIREMENTS`** is the normal first
  active working status after backlog **`TO DO`**.

## Existing issue flow (status sequence)

Handle comments, assignments, fields, and transitions in this agent. Do not leave
**`REQUIREMENTS`** until **`05-requirements-stage.md`** completion rules are met.

- **`REQUIREMENTS` → `TECH LEAD`:** when requirements, acceptance criteria, and
  requirement subtasks are complete for **`Story`**, **`Bug`**, or **`Task`**.
- **`TECH LEAD` → `REQUIREMENTS`:** when technical review finds serious
  requirements or acceptance problems—add a Jira comment with reasons and
  rework guidance (**`07-tech-lead-stage.md`**).
- **`TECH LEAD` → `DEVELOPMENT`:** when technically sound and Tech Lead fields are
  populated (**`07-tech-lead-stage.md`**).
- **`DEVELOPMENT` → `CODE REVIEW`:** when a GitHub pull request exists for the
  work (**`08-development-stage.md`**).
- **`CODE REVIEW` → `DEVELOPMENT`:** when review fails.
- **`CODE REVIEW` → `DEPLOY`:** when review passes or PR is approved (default).
- Optional **`TEST`** before **`DEPLOY`** when the user asks and Jira exposes that
  transition (**`09-review-deploy-stage.md`**).
- **`DEPLOY` → `DONE`:** when deployment is complete.

Team **fast-path:** implementation may commit directly to **`main`** and still move
Jira through downstream stages as a lightweight formality (**`03-workflow-types.md`**).

After substantive work, summarize current stage, what changed, and the recommended
next stage.
