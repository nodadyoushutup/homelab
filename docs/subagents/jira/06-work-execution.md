# Work Execution (homelab)

Generic subtask discipline and “complete one requirement at a time” behavior are
in **`jira_system_prompt.md`**. This file is **`HOME`** checklist wiring.

## Subtasks as checklist

- Requirement-generated subtasks are the working todo list for parent **`Story`**,
  **`Bug`**, or **`Task`**.
- Read parent **`customfield_10103`** / **`customfield_10104`** and child subtasks
  before starting; use **`REQ-###`** alignment between parent list and subtasks.
- When a subtask’s work is done, transition **that subtask** to **`Done`** only.
- Parent status moves follow **`02-issue-flows.md`**, not this checklist rule.

## Completing one requirement

- Locate **`REQ-###`** and matching subtask; scope work to that unit unless the
  user widens it.
- After completion, transition only the matching subtask; summarize what changed.

## Blockers

- Leave subtasks open and explain blockers; surface bad requirements to the user
  or workflow before silently “fixing” parent scope.
