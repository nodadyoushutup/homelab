---
name: jira-workflow
description: Use this skill to classify Jira work, apply issue-type-specific workflow rules, and reason about allowed status transitions before Jira mutations.
---

# Jira Workflow

## Overview

This skill helps the Jira agent decide whether the request is about net-new
work or an existing issue, apply the right Jira guardrails before any
mutation, enforce issue-type-specific workflow rules, and keep Jira work moving
forward through the current stage.

Start with the issue type, then use the matching workflow map before proposing
or applying a status change.

## Instructions

1. Decide whether the request is about creating net-new Jira work or changing existing Jira work.
2. Treat "create", "open", "file", "log", "raise", "submit", "add", "make", or "write up" a Jira issue, ticket, task, story, bug, or epic as a request for new work.
3. Prefer net-new issue handling whenever there is no existing issue key and the user wants the work tracked in Jira.
4. For net-new issue handling, start in `TO DO` and lock a short summary plus the issue type before gathering deeper fields.
5. Classify the issue type using the issue-type selection rules in this skill instead of relying on generic defaults.
6. For existing issue work, confirm the issue key and map the requested change to supported edit surfaces before mutation.
7. Use direct Jira reads first when workflow, field, or transition context is missing.
8. Before changing status or asking a follow-up, identify the issue type and current stage and check the issue-type workflow map in this skill.
9. Treat each requested Jira action as being in service of completing, unblocking, or advancing the current stage.
10. If you cannot explain how the requested action helps the current stage, inspect more Jira context before acting instead of asking a generic readiness question.
11. If the requested transition is not explicitly allowed by the workflow map, do not assume it is valid. Read Jira transition options first or ask a focused follow-up.
12. Treat workflow maps in this skill as the repo-side source of truth for how we expect Jira work to move unless live Jira data proves otherwise.
13. Ask follow-up questions only for real stage blockers, and tie each question to the missing information needed to complete or exit the current stage.
14. When the requested work completes the current stage, explicitly say so and invite the caller to move to the most likely next stage from the workflow map.
15. If several next transitions are valid, recommend the most likely next step and mention the other valid branch only when it materially affects the decision.
16. If the user does not specify a project for a new issue, use the runtime's configured default project unless Jira metadata or the task context shows a different project is required.

## Stage-Aware Operating Pattern

- Determine the issue's current stage from Jira status, or establish the starting
  stage for net-new work, before deciding what to do next.
- Treat every Jira task as serving one of three purposes:
  - complete the current stage
  - unblock the current stage
  - advance to the next valid stage
- Avoid generic "are we ready to move to the next stage?" questions when the
  workflow map plus live Jira state already show the likely answer.
- Ask a follow-up only when stage-exit information is truly missing and cannot
  be inferred from Jira, the workflow map, or the supplied context.
- When stage-completing work is done, say that the stage is complete and invite
  the caller to move the issue forward.
- For `Story` and `Bug`, a completed `TO DO` stage should usually lead to an
  invitation to move into `REQUIREMENTS`.
- For `Story`, a completed `REQUIREMENTS` stage should usually lead to an
  invitation to move into `TECH LEAD`.
- For `Bug`, a completed `REQUIREMENTS` stage should usually lead to an
  invitation to move into `REPLICATE` when reproduction work is needed, or
  `TECH LEAD` when it is not.
- For `Bug`, a completed `REPLICATE` stage should usually lead back to
  `REQUIREMENTS` if new gaps were uncovered, otherwise into `TECH LEAD`.
- For `Story` and `Bug`, a completed `TECH LEAD` stage should usually lead to
  an invitation to move into `DEVELOPMENT`.
- For `Task`, a completed `TO DO` stage should usually lead to an invitation to
  move into `REQUIREMENTS`, and a completed `REQUIREMENTS` stage plus completed
  work should usually lead to an invitation to move into `DONE`.
- For `Subtask`, keep the workflow minimal, but still invite `DONE` when the
  work is complete.

## Issue Type Selection Rules

Use these rules when deciding what Jira issue type to create.

### `Story`

- Use `Story` when code work or new features are requested.
- Use `Story` for net-new implementation work, enhancements, and general change requests that are not bug fixes.
- A `Story` is the normal choice when the user wants something built or changed and there is no broken behavior to fix.
- `Story` behaves much like `Bug`, except there is no replication stage because there is no bug to replicate.

### `Bug`

- Use `Bug` when something is broken and needs fixing.
- Use `Bug` for problem-solving, repairs, breakages, regressions, and maintenance work that is specifically about fixing behavior.
- `Bug` behaves very much like `Story`, but it is specifically for fixes and broken behavior.

### `Task`

- Use `Task` for simple one-off work items.
- Use `Task` when the work can be requirements-gathered and then marked done without the larger lifecycle ceremony.
- `Task` is the normal choice for simple chores, straightforward actions, or operational one-offs.
- A `Task` may also be used for code work when the user explicitly wants a `Task` or "quick task" specifically to avoid the larger lifecycle rigmarole.
- That shortcut is valid, but do not make it the default habit for normal code work.
- If the request sounds like normal feature work or normal bug-fix work, prefer `Story` or `Bug` unless the user clearly wants the lighter `Task` path.

### `Subtask`

- Use `Subtask` only for child work under an existing parent issue.
- Use `Subtask` when the user explicitly wants checklist-like child items under a `Story`, `Bug`, or `Task`.
- Treat `Subtask` as a rare exception, not a default planning tool.
- In general, avoid creating `Subtask` issues unless the user specifically directs it or the amount of work is unusually large and clearly benefits from explicit child tracking.
- `Subtask` is best thought of as a bullet-point-like checklist issue under a parent, not as a normal top-level issue choice.

## Story Workflow

Use this map for Jira issues of type `Story`.

### Story Statuses

- `TO DO`
- `REQUIREMENTS`
- `TECH LEAD`
- `DEVELOPMENT`
- `TEST`
- `CODE REVIEW`
- `DEPLOY`
- `DONE`
- `CANCELED`

### Story Primary Flow

`START -> TO DO -> REQUIREMENTS -> TECH LEAD -> DEVELOPMENT -> CODE REVIEW -> DEPLOY -> DONE`

The workflow also includes direct returns and resolution paths:

- `REQUIREMENTS -> TO DO`
- `TECH LEAD -> REQUIREMENTS`
- `DEVELOPMENT -> TECH LEAD`
- `DEVELOPMENT -> TEST`
- `TEST -> DEVELOPMENT`
- `CODE REVIEW -> DEVELOPMENT`
- `CODE REVIEW -> TEST`
- `REQUIREMENTS -> DONE`
- `Any -> CANCELED`

### Story Explicit Transitions

- `START -> TO DO`
- `TO DO -> REQUIREMENTS`
- `REQUIREMENTS -> TO DO`
- `REQUIREMENTS -> TECH LEAD`
- `REQUIREMENTS -> DONE`
- `TECH LEAD -> REQUIREMENTS`
- `TECH LEAD -> DEVELOPMENT`
- `DEVELOPMENT -> TECH LEAD`
- `DEVELOPMENT -> TEST`
- `DEVELOPMENT -> CODE REVIEW`
- `CODE REVIEW -> DEVELOPMENT`
- `CODE REVIEW -> TEST`
- `CODE REVIEW -> DEPLOY`
- `TEST -> DEVELOPMENT`
- `DEPLOY -> DONE`
- `Any -> CANCELED`

### Story Workflow Notes

- This Story workflow is different from the earlier draft and does not include `METADATA`.
- `REQUIREMENTS` is a central decision point. Stories can return to `TO DO`, move into `TECH LEAD`, or resolve directly to `DONE`.
- `TECH LEAD` and `DEVELOPMENT` both have backward feedback paths, so Stories can move between planning and implementation more than once.
- `TEST` is a distinct Story status and loops back into `DEVELOPMENT`.
- `CODE REVIEW` can send work back to `DEVELOPMENT`, route it into `TEST`, or advance it to `DEPLOY`.
- `CANCELED` appears to be globally reachable from any Story status.

### How To Use This Map

- When creating a new `Story`, default the initial status to `TO DO` unless live Jira behavior shows a different creation default.
- When summarizing a `Story`, call out whether it is still in planning flow (`REQUIREMENTS` or `TECH LEAD`), in implementation (`DEVELOPMENT`, `TEST`, `CODE REVIEW`, or `DEPLOY`), or already resolved (`DONE` or `CANCELED`).
- When asked to transition a `Story`, prefer the named next step from this workflow and preserve the screenshot's explicit feedback loops instead of assuming a simple straight-line flow.
- If a requested Story transition conflicts with this map, inspect the live Jira transitions before making the change.

### Story Lifecycle Rules

Use these rules in addition to the status map above.

#### Story Type Selection

- Use `Story` for new features, improvements, and general code changes that are not bug fixes.
- When the user asks to create a new Jira issue and it is clearly about new functionality, enhancement work, or non-bug implementation work, select issue type `Story`.
- A newly created `Story` starts in `TO DO`.

#### Relationship To Bug Workflow

- The `Story` lifecycle should be treated as nearly the same as the `Bug` lifecycle.
- The main functional difference is that `Story` does not include the `REPLICATE` stage.
- Otherwise, the same expectations for baseline capture, requirements expansion, tech-lead review, implementation handoff, and downstream lightweight status progression apply.

#### `TO DO`

- `TO DO` is the baseline capture stage for a story.
- In `TO DO`, guide the user toward a brief, high-level summary of what needs to be built or changed.
- Keep the summary short and not explicitly detailed.
- The goal in `TO DO` is to create the issue with a baseline summary, not to fully elaborate the story.
- Once that baseline summary exists, the story can be created in `TO DO`.

#### `REQUIREMENTS`

- `REQUIREMENTS` is the requirements-gathering stage for the story.
- In this stage, ask clarifying questions when needed and compile the answers when they are already available.
- Lock the following sections for the Jira issue description:
- `Overview`
- `Scope`
- `Requirements`
- `Acceptance Criteria`
- `Overview` should be a somewhat brief summary of the full story ticket.
- `Scope` should describe the bounded area of behavior, systems, or changes in scope.
- `Requirements` should be an ordered list.
- Prefix each requirement item with identifiers such as `REQ-1`, `REQ-2`, or `REQ-1A`.
- `Acceptance Criteria` should be an ordered list.
- Prefix each acceptance criterion with identifiers such as `AC-1`, `AC-2`, or `AC-1A`.
- Use sub-items when needed so the team can refer to entries precisely as `1A`, `1B`, `REQ-1A`, or `AC-1A`.
- When requirements gathering is complete, update the Jira description with the locked `Overview`, `Scope`, `Requirements`, and `Acceptance Criteria` sections.
- Use `REQUIREMENTS` to expand the brief original idea into a fully actionable story definition.
- Fill any other required or helpful Jira fields in this stage.
- There are no extra required fields right now, but the Jira agent should be prepared for future required fields.
- `REQUIREMENTS -> DONE` is valid when the issue is closed outright without being canceled.

#### `TECH LEAD`

- `TECH LEAD` is the technical validation stage.
- In `TECH LEAD`, investigate the code at a broad-strokes level and assess whether the requested story is technically sound and achievable.
- The goal is not to solve the story yet. The goal is to validate the ask, identify the likely implementation area, and surface clarification gaps.
- If the technical review raises new questions, move the story back to `REQUIREMENTS`.
- If the story is ready to proceed, update the Jira description with a `Tech Lead Notes` section.
- `Tech Lead Notes` should cite specific files and code line numbers where possible.
- `Tech Lead Notes` should summarize the relevant findings and outline a reasonable implementation plan for the developer.
- The plan should be directive and well reasoned, but it does not need to be excessively exhaustive.
- Also add a `Test Plans` section to the Jira description.
- Build `Test Plans` from the issue information and the tech-lead findings.
- `Test Plans` should include `Pre Conditions`.
- `Test Plans` should then include labeled test steps.
- Treat the tech-lead output as the developer handoff package.

#### `DEVELOPMENT`

- `DEVELOPMENT` is the implementation stage.
- In `DEVELOPMENT`, the assignee should use the total sum of issue information, tech-lead notes, and test plans to perform the code work.
- When the Jira workflow reaches real implementation, prefer delegating the execution to the `Code` specialist with the Jira ticket context and the locked story details.
- When preparing that development handoff, explicitly preserve these current execution rules:
- stay on the `main` branch
- make a git commit with a reasonable message
- push the resulting commit
- stage and commit only the files relevant to the work
- ignore unrelated dirty files that are outside the story work

#### Temporary Delivery Shortcut

- For now, the team is intentionally moving fast and may manually cheese `TEST`, `CODE REVIEW`, and `DEPLOY`.
- In practice, development may go straight from implemented code to a final Jira resolution while still moving the Jira status through the expected workflow shape.
- The Jira agent should preserve the workflow states in Jira, but it may treat `TEST`, `CODE REVIEW`, and `DEPLOY` as lightweight status progression rather than gates that block shipping.
- For now, after implementation is complete, it is acceptable to move the story through the downstream workflow as if review, deploy, and validation occurred, even when the team effectively commits directly to `main`.

#### `CANCELED`

- `CANCELED` is available from any stage.
- Use `CANCELED` when the story should be abandoned rather than completed.

### Story Description Template

When the story reaches `REQUIREMENTS`, structure the Jira description with these sections:

- `Overview`
- `Scope`
- `Requirements`
- `Acceptance Criteria`

When the story reaches `TECH LEAD`, extend that same Jira description with:

- `Tech Lead Notes`
- `Test Plans`

Formatting expectations:

- Keep `Overview` concise.
- Keep `Requirements` as an ordered list using `REQ-*` identifiers.
- Keep `Acceptance Criteria` as an ordered list using `AC-*` identifiers.
- Include cited files and code line numbers in `Tech Lead Notes` when available.
- Include `Pre Conditions` plus labeled test steps in `Test Plans`.

## Bug Workflow

Use this map for Jira issues of type `Bug`.

### Bug Statuses

- `TO DO`
- `REQUIREMENTS`
- `REPLICATE`
- `TECH LEAD`
- `DEVELOPMENT`
- `TEST`
- `CODE REVIEW`
- `DEPLOY`
- `DONE`
- `CANCELED`

### Bug Primary Flow

`START -> TO DO -> REQUIREMENTS`

From `REQUIREMENTS`, the bug can move through investigation and triage:

- `REQUIREMENTS -> REPLICATE -> TECH LEAD`
- `REQUIREMENTS -> TECH LEAD`

After triage, the main delivery flow continues:

`TECH LEAD -> DEVELOPMENT -> CODE REVIEW -> DEPLOY -> DONE`

The workflow also includes direct returns and resolution paths:

- `REQUIREMENTS -> TO DO`
- `REPLICATE -> REQUIREMENTS`
- `TECH LEAD -> REQUIREMENTS`
- `DEVELOPMENT -> TECH LEAD`
- `DEVELOPMENT -> TEST`
- `TEST -> DEVELOPMENT`
- `CODE REVIEW -> DEVELOPMENT`
- `CODE REVIEW -> TEST`
- `REQUIREMENTS -> DONE`
- `Any -> CANCELED`

### Bug Explicit Transitions

- `START -> TO DO`
- `TO DO -> REQUIREMENTS`
- `REQUIREMENTS -> TO DO`
- `REQUIREMENTS -> REPLICATE`
- `REQUIREMENTS -> TECH LEAD`
- `REQUIREMENTS -> DONE`
- `REPLICATE -> REQUIREMENTS`
- `REPLICATE -> TECH LEAD`
- `TECH LEAD -> REQUIREMENTS`
- `TECH LEAD -> DEVELOPMENT`
- `DEVELOPMENT -> TECH LEAD`
- `DEVELOPMENT -> TEST`
- `DEVELOPMENT -> CODE REVIEW`
- `CODE REVIEW -> DEVELOPMENT`
- `CODE REVIEW -> TEST`
- `CODE REVIEW -> DEPLOY`
- `TEST -> DEVELOPMENT`
- `DEPLOY -> DONE`
- `Any -> CANCELED`

### Bug Workflow Notes

- This Bug workflow is more investigation-heavy than the earlier draft and does not include `METADATA`.
- `REQUIREMENTS` is a central decision point. Bugs can return to `TO DO`, move into `REPLICATE`, move directly to `TECH LEAD`, or resolve directly to `DONE`.
- `REPLICATE` is a Bug-specific investigation state with feedback into `REQUIREMENTS` and forward progress into `TECH LEAD`.
- `TECH LEAD` and `DEVELOPMENT` both have backward feedback paths, which means Bugs can move between triage and implementation more than once.
- `TEST` is a distinct Bug status and loops back into `DEVELOPMENT`.
- `CODE REVIEW` can send work back to `DEVELOPMENT`, route it into `TEST`, or advance it to `DEPLOY`.
- `CANCELED` appears to be globally reachable from any Bug status.

### How To Use This Map

- When creating a new `Bug`, default the initial status to `TO DO` unless live Jira behavior shows a different creation default.
- When summarizing a `Bug`, call out whether it is still in investigation flow (`REQUIREMENTS` or `REPLICATE`), in triage (`TECH LEAD`), in implementation (`DEVELOPMENT`, `TEST`, `CODE REVIEW`, or `DEPLOY`), or already resolved (`DONE` or `CANCELED`).
- When asked to transition a `Bug`, prefer the named next step from this workflow and preserve the screenshot's explicit feedback loops instead of assuming a simple straight-line flow.
- If a requested `Bug` transition conflicts with this map, inspect the live Jira transitions before making the change.

### Bug Lifecycle Rules

Use these rules in addition to the status map above.

#### Bug Type Selection

- Use `Bug` when something is broken and needs fixing.
- When the user asks to create a new Jira issue and it is clearly about a bug that needs fixing, select issue type `Bug`.
- A newly created `Bug` starts in `TO DO`.

#### `TO DO`

- `TO DO` is the baseline capture stage for a bug.
- In `TO DO`, guide the user toward a brief, high-level summary of what is broken.
- Keep the summary short and not explicitly detailed.
- The goal in `TO DO` is to create the issue with a baseline summary, not to fully elaborate the bug.
- Once that baseline summary exists, the bug can be created in `TO DO`.

#### `REQUIREMENTS`

- `REQUIREMENTS` is the requirements-gathering stage for the bug.
- In this stage, ask clarifying questions when needed and compile the answers when they are already available.
- Lock the following sections for the Jira issue description:
- `Overview`
- `Scope`
- `Requirements`
- `Acceptance Criteria`
- `Overview` should be a somewhat brief summary of the full bug ticket.
- `Scope` should describe the bounded area of behavior, systems, or changes in scope.
- `Requirements` should be an ordered list.
- Prefix each requirement item with identifiers such as `REQ-1`, `REQ-2`, or `REQ-1A`.
- `Acceptance Criteria` should be an ordered list.
- Prefix each acceptance criterion with identifiers such as `AC-1`, `AC-2`, or `AC-1A`.
- Use sub-items when needed so the team can refer to entries precisely as `1A`, `1B`, `REQ-1A`, or `AC-1A`.
- When requirements gathering is complete, update the Jira description with the locked `Overview`, `Scope`, `Requirements`, and `Acceptance Criteria` sections.
- Use `REQUIREMENTS` to expand the brief original idea into a fully actionable bug definition.
- Fill any other required or helpful Jira fields in this stage.
- There are no extra required fields right now, but the Jira agent should be prepared for future required fields.
- `REQUIREMENTS -> DONE` is valid when the issue is closed outright without being canceled, such as when the bug turns out to be a user-training issue rather than an actual bug.

#### `REPLICATE`

- `REPLICATE` is optional.
- Use `REPLICATE` when reproducing the bug will materially help validate the problem or narrow the fix.
- If the team chooses to skip replication, add a Jira comment explicitly saying replication was skipped.
- If replication work is performed, post the replicate results as a Jira comment.
- If replication uncovers new questions or missing context, move the bug back to `REQUIREMENTS`.

#### `TECH LEAD`

- `TECH LEAD` is the technical validation stage.
- In `TECH LEAD`, investigate the code at a broad-strokes level and assess whether the requested fix is technically sound and achievable.
- The goal is not to solve the bug yet. The goal is to validate the ask, identify the likely implementation area, and surface clarification gaps.
- If the technical review raises new questions, move the bug back to `REQUIREMENTS`.
- If the bug is ready to proceed, update the Jira description with a `Tech Lead Notes` section.
- `Tech Lead Notes` should cite specific files and code line numbers where possible.
- `Tech Lead Notes` should summarize the relevant findings and outline a reasonable implementation plan for the developer.
- The plan should be directive and well reasoned, but it does not need to be excessively exhaustive.
- Also add a `Test Plans` section to the Jira description.
- Build `Test Plans` from the issue information, any replicate results, and the tech-lead findings.
- `Test Plans` should include `Pre Conditions`.
- `Test Plans` should then include labeled test steps.
- Treat the tech-lead output as the developer handoff package.

#### `DEVELOPMENT`

- `DEVELOPMENT` is the implementation stage.
- In `DEVELOPMENT`, the assignee should use the total sum of issue information, replicate comments, tech-lead notes, and test plans to perform the code work.
- When the Jira workflow reaches real implementation, prefer delegating the execution to the `Code` specialist with the Jira ticket context and the locked bug details.
- When preparing that development handoff, explicitly preserve these current execution rules:
- stay on the `main` branch
- make a git commit with a reasonable message
- push the resulting commit
- stage and commit only the files relevant to the work
- ignore unrelated dirty files that are outside the bug fix

#### Temporary Delivery Shortcut

- For now, the team is intentionally moving fast and may manually cheese `TEST`, `CODE REVIEW`, and `DEPLOY`.
- In practice, development may go straight from implemented code to a final Jira resolution while still moving the Jira status through the expected workflow shape.
- The Jira agent should preserve the workflow states in Jira, but it may treat `TEST`, `CODE REVIEW`, and `DEPLOY` as lightweight status progression rather than gates that block shipping.
- For now, after implementation is complete, it is acceptable to move the bug through the downstream workflow as if review, deploy, and validation occurred, even when the team effectively commits directly to `main`.

#### `CANCELED`

- `CANCELED` is available from any stage.
- Use `CANCELED` when the bug should be abandoned rather than completed.

### Bug Description Template

When the bug reaches `REQUIREMENTS`, structure the Jira description with these sections:

- `Overview`
- `Scope`
- `Requirements`
- `Acceptance Criteria`

When the bug reaches `TECH LEAD`, extend that same Jira description with:

- `Tech Lead Notes`
- `Test Plans`

Formatting expectations:

- Keep `Overview` concise.
- Keep `Requirements` as an ordered list using `REQ-*` identifiers.
- Keep `Acceptance Criteria` as an ordered list using `AC-*` identifiers.
- Include cited files and code line numbers in `Tech Lead Notes` when available.
- Include `Pre Conditions` plus labeled test steps in `Test Plans`.

## Task Workflow

Use this map for Jira issues of type `Task`.

### Task Statuses

- `TO DO`
- `REQUIREMENTS`
- `DONE`
- `CANCELED`

### Task Primary Flow

`START -> TO DO -> REQUIREMENTS -> DONE`

The workflow also includes direct returns and resolution paths:

- `REQUIREMENTS -> TO DO`
- `Any -> CANCELED`

### Task Explicit Transitions

- `START -> TO DO`
- `TO DO -> REQUIREMENTS`
- `REQUIREMENTS -> TO DO`
- `REQUIREMENTS -> DONE`
- `Any -> CANCELED`

### Task Workflow Notes

- This Task workflow is no longer the earlier two-state draft.
- `REQUIREMENTS` is a real Task status and sits between `TO DO` and `DONE`.
- `REQUIREMENTS` can return to `TO DO` or resolve directly to `DONE`.
- `CANCELED` appears to be globally reachable from any Task status.
- The Task workflow is still simpler than `Story` and `Bug`, but it now includes a planning step before completion.

### How To Use This Map

- When creating a new `Task`, default the initial status to `TO DO` unless live Jira behavior shows a different creation default.
- When summarizing a `Task`, call out whether it is waiting in `TO DO`, being clarified in `REQUIREMENTS`, or already resolved (`DONE` or `CANCELED`).
- When asked to transition a `Task`, prefer the named next step from this workflow instead of assuming the older direct `TO DO -> DONE` shortcut.
- If a requested `Task` transition conflicts with this map, inspect the live Jira transitions before making the change.

### Task Lifecycle Rules

Use these rules in addition to the status map above.

#### Task Type Selection

- Use `Task` for non-development chores, maintenance, cleanup, organization, operational follow-up, or other simple work that does not need the fuller `Story` or `Bug` lifecycle.
- A newly created `Task` starts in `TO DO`.

#### Relationship To Story And Bug Workflows

- `Task` should use the same front-end capture model as `Story` and `Bug` for `TO DO` and `REQUIREMENTS`.
- The main difference is that `Task` does not need `TECH LEAD`, `DEVELOPMENT`, `TEST`, `CODE REVIEW`, or `DEPLOY`.
- Once requirements are captured and the work is performed, the task can move directly to `DONE`.

#### `TO DO`

- `TO DO` is the baseline capture stage for a task.
- In `TO DO`, guide the user toward a brief, high-level summary of the work.
- Keep the summary short and not explicitly detailed.
- The goal in `TO DO` is to create the issue with a baseline summary, not to fully elaborate the task.

#### `REQUIREMENTS`

- `REQUIREMENTS` is the requirements-gathering stage for the task.
- In this stage, ask clarifying questions when needed and compile the answers when they are already available.
- Lock the following sections for the Jira issue description:
- `Overview`
- `Scope`
- `Requirements`
- `Acceptance Criteria`
- `Overview` should be a somewhat brief summary of the full task ticket.
- `Scope` should describe the bounded area of behavior, systems, or actions in scope.
- `Requirements` should be an ordered list.
- Prefix each requirement item with identifiers such as `REQ-1`, `REQ-2`, or `REQ-1A`.
- `Acceptance Criteria` should be an ordered list.
- Prefix each acceptance criterion with identifiers such as `AC-1`, `AC-2`, or `AC-1A`.
- Use sub-items when needed so the team can refer to entries precisely as `1A`, `1B`, `REQ-1A`, or `AC-1A`.
- When requirements gathering is complete, update the Jira description with the locked `Overview`, `Scope`, `Requirements`, and `Acceptance Criteria` sections.
- There are no extra required fields right now, but the Jira agent should be prepared for future required fields.

#### `DONE`

- Once the work is performed, the task can move directly from `REQUIREMENTS` to `DONE`.
- `Task` is intentionally simple: capture the work, perform the work, and mark it done.

#### `CANCELED`

- `CANCELED` is available from any stage.
- Use `CANCELED` when the task should be abandoned rather than completed.

### Task Description Template

When the task reaches `REQUIREMENTS`, structure the Jira description with these sections:

- `Overview`
- `Scope`
- `Requirements`
- `Acceptance Criteria`

Formatting expectations:

- Keep `Overview` concise.
- Keep `Requirements` as an ordered list using `REQ-*` identifiers.
- Keep `Acceptance Criteria` as an ordered list using `AC-*` identifiers.

## Subtask Workflow

Use this map for Jira issues of type `Subtask`.

### Subtask Statuses

- `TO DO`
- `DONE`
- `CANCELED`

### Subtask Primary Flow

`START -> TO DO -> DONE`

### Subtask Explicit Transitions

- `START -> TO DO`
- `TO DO -> DONE`
- `Any -> CANCELED`

### Subtask Hierarchy Notes

- A `Subtask` is not on the same hierarchy level as a `Task`, `Story`, or `Bug`.
- A `Subtask` must belong to a parent issue.
- Valid parent relationships include:
- `Task -> Subtask`
- `Story -> Subtask`
- `Bug -> Subtask`
- Do not treat `Subtask` as a peer alternative to `Task`, `Story`, or `Bug` when classifying new top-level work.
- When creating a `Subtask`, identify and preserve the parent issue key.
- When summarizing or editing a `Subtask`, include parent context when it materially affects the work or status interpretation.
- A `Subtask` may share the same visible statuses as a `Task` without sharing the same planning role or hierarchy.

### Subtask Workflow Notes

- This Subtask workflow is intentionally minimal.
- `TO DO` is the normal entry state for Subtasks.
- `DONE` is reached directly from `TO DO`.
- `CANCELED` appears to be globally reachable from any Subtask status.
- There is no `REQUIREMENTS` stage in the current Subtask workflow.
- The parent-child relationship is still operationally important even though the Subtask status map is simple.
- The parent issue may be a `Task`, `Story`, or `Bug`, each with a richer workflow than the Subtask itself.

### How To Use This Map

- When creating a new `Subtask`, default the initial status to `TO DO` unless live Jira behavior shows a different creation default.
- Before creating a `Subtask`, confirm the intended parent issue key.
- When summarizing a `Subtask`, describe both the Subtask status and its parent issue relationship when useful.
- When asked to transition a `Subtask`, check whether the requested change makes sense relative to the parent issue's current state even though the Subtask has its own simpler status map.
- If a requested `Subtask` transition conflicts with this map, inspect the live Jira transitions before making the change.

### Subtask Lifecycle Rules

Use these rules in addition to the status map above.

#### Subtask Type Selection

- Use `Subtask` only when the work belongs under an existing parent issue.
- Do not use `Subtask` for new top-level work.
- A newly created `Subtask` starts in `TO DO`.

#### Operational Model

- `Subtask` is intentionally minimal.
- Treat it as "did it" or "did not do it."
- If the work is performed, move it to `DONE`.
- If the work should be abandoned, move it to `CANCELED`.
- Unlike `Story`, `Bug`, or `Task`, `Subtask` does not need a separate requirements-expansion stage in the current workflow.
