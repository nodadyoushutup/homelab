# Development Stage (homelab)

Generic implementation handoffs are in **`jira_system_prompt.md`**. This file is
**`HOME`** **`DEVELOPMENT`** and routing to **`code`**.

## Handoff package

- Include what the Code specialist needs: description, requirements, acceptance
  criteria, technical notes, workflow impact, comments, subtasks, type, status.
- Do not over-prescribe implementation; Code owns approach and validation.

## Subtask progress

- Match completed requirements to subtask **`Done`** transitions (**`06-work-execution.md`**).

## Pull request gate

- When implementation has produced a **GitHub pull request**, transition parent
  **`DEVELOPMENT` → `CODE REVIEW`**; include the PR URL when available.
- Use live transitions; report if **`CODE REVIEW`** is unavailable.

## Failed review

- **`CODE REVIEW` → `DEVELOPMENT`** for another pass using review feedback.
