# Requirements Stage (homelab)

Applies when an issue is in **`REQUIREMENTS`** on **`HOME`**. Generic
requirements workshopping and BA behavior are in **`jira_system_prompt.md`**.

`REQUIREMENTS` is where the ticket is fleshed out before **`TECH LEAD`**.

## Gathering

- Start from current Jira context (baseline description from **`TO DO`**, comments,
  fields).
- Workshopping, autogeneration, and “one question at a time” follow the framework
  prompt; keep questions focused on material gaps.

## Requirements format

- Store in **`Requirements`**, **`customfield_10103`**.
- Markdown unordered list; each item prefixed with stable **`REQ-###`**
  (starting at **`REQ-001`**), ordered sensibly for the work.

```markdown
- REQ-001: The system must ...
- REQ-002: The workflow must ...
```

## Acceptance criteria

- After requirements are locked, default to generating acceptance criteria unless
  the user wants to own them.
- Exactly **one** **`AC-###`** per **`REQ-###`** with the same numeric index.
- Store in **`Acceptance Criteria`**, **`customfield_10104`**, markdown list:

```markdown
- AC-001: Given ..., when ..., then ...
```

## Requirement subtasks

- After requirements settle, create one **`Subtask`** per requirement before leaving
  **`REQUIREMENTS`**.
- Subtask summary matches the requirement text (keep **`REQ-###`** prefix).
- Set each subtask’s **`customfield_10103`** to that single requirement line and
  **`customfield_10104`** to the matching **`AC-###`** line.
- One-sentence subtask description; no duplicates if a matching subtask already
  exists.

## Completion before `TECH LEAD`

- **`customfield_10103`** populated with well-formed **`REQ-###`** list.
- **`customfield_10104`** populated with matching **`AC-###`** for every requirement.
- Every requirement has a child **`Subtask`**.
- Do not exit with only the rough **`TO DO`** overview for **`Story`**, **`Bug`**,
  or **`Task`**.
- Then transition parent **`REQUIREMENTS` → `TECH LEAD`** (or closest valid
  transition; report if missing).
