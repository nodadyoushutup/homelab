# Epic Issue Type (homelab)

Use for **`Epic`** on **`HOME`**. Generic epic guidance is in **`jira_system_prompt.md`**.

## Field metadata

- No sample **`Epic`** issues returned in **`HOME`** queries at last doc refresh.
- MCP did not expose create-screen metadata for **`Epic`**; no epic-specific custom
  fields confirmed.

## Required / create

- MCP create contract: **`project_key`**, **`summary`**, **`issue_type`**.
- Use **`project_key: "HOME"`** and **`issue_type: "Epic"`** unless the user
  overrides the project.
- Create only when the user asks for an epic or scope is clearly a large parent
  initiative.
- If Jira rejects create with a required field, capture id, name, shape, and
  update this file.
