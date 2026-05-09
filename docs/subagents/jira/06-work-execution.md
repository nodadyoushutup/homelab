# Work Execution

These instructions apply when the user asks to perform work for a Jira issue,
continue an in-progress Jira issue, or complete a specific requirement.

## Subtasks As The Work Checklist

- Treat requirement-generated subtasks as the working todo list for the parent
  `Story`, `Bug`, or `Task`.
- Use the parent issue fields, especially `Requirements` (`customfield_10103`)
  and `Acceptance Criteria` (`customfield_10104`), plus the child subtasks to
  understand what work needs to be performed.
- Each `REQ-###` requirement should have a matching child `Subtask` with the
  same `REQ-###` prefix. Use that subtask as the unit of work for that
  requirement.
- When a subtask's work is completed, transition that subtask to `Done`.
- Do not treat parent issue transitions as part of this checklist rule. Parent
  issue status movement is a separate workflow decision.

## Starting Or Resuming Work

- When pulling a Jira issue for work, read the parent issue and its subtasks
  before starting.
- Identify which subtasks are already `Done` and which remain open.
- If the issue is partially complete, quickly review prior work, comments,
  status, and relevant repository state, then continue from the remaining open
  subtasks.
- Do not redo completed subtasks unless the user explicitly asks for rework or
  the current evidence shows the previous work is invalid.
- Work through open subtasks in a sensible order based on their `REQ-###`
  sequence and dependencies.

## Completing A Requirement

- If the user asks to complete a specific requirement, locate the matching
  `REQ-###` entry and child subtask.
- Perform only the work needed for that requirement unless the user authorizes a
  broader pass or the requirement cannot be completed without adjacent changes.
- After completing the specific requirement, transition only the matching
  subtask to `Done`.
- Summarize what changed and which requirement/subtask was completed.

## Execution Behavior

- Use subtasks to keep progress visible while work is happening.
- Mark a subtask `Done` only after the necessary implementation, documentation,
  validation, or operational work for that requirement has actually been
  completed.
- If a subtask cannot be completed, leave it open and explain the blocker.
- If completing a subtask reveals missing or incorrect requirements, report that
  and update the parent issue only when the user asks or the workflow requires
  the correction before continuing.
