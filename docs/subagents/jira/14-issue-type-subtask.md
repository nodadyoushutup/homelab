# Subtask Issue Type (homelab)

Use for **`Subtask`** on **`HOME`**. Generic subtask rules: **`jira_system_prompt.md`**.

## Field metadata (sampled)

- **`customfield_10103`** / **`customfield_10104`** hold the single requirement line
  and matching **`AC-###`** when generated from a parent requirement
  (**`05-requirements-stage.md`**).

## Create / required

- MCP create: **`project_key`**, **`summary`**, **`issue_type`**; operationally
  **`parent`** required.
- Use **`project_key: "HOME"`**, **`issue_type: "Subtask"`**, unless overridden.
- Never top-level **`Subtask`** without a parent key.

## Operating (HOME)

- Summary matches parent requirement (**`REQ-###`** preserved).
- Short one-sentence description; checklist behavior in **`06-work-execution.md`**.
- Do not manually set **`Rank`**, **`Development`**, **`Design`**, **`Issue color`**
  unless required.
