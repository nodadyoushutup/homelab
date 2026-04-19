# Jira Workflow

This document describes how to use Jira in this repo for issue discovery,
workflow analysis, and engineering coordination. Use
[`docs/rules/jira.md`](./../rules/jira.md) for the steady-state rules and
[`docs/rules/mcp-servers.md`](./../rules/mcp-servers.md) for the underlying
`mcp-atlassian` service constraints.

## Scope

Use this workflow for:

- finding Jira issues relevant to a task
- summarizing issue status, ownership, dates, and blockers
- tracing status transitions, changelogs, and worklogs
- checking linked pull requests, branches, or commits from Jira development
  panels
- narrowing Jira context before implementation, incident response, or delivery
  analysis
- creating or advancing Jira issues through the team's current issue-type
  workflows

## Standard Flow

When a task needs Jira context:

1. read `docs/rules/jira.md`
2. decide whether you already have a specific issue key or need discovery first
3. if you have an issue key, read the issue directly before doing broader
   searches
4. if you do not have an issue key, run the narrowest Jira search that fits the
   available context
5. inspect extra Jira surfaces only as needed:
   - changelog for status or ownership history
   - dates or SLA data for timing questions
   - development info for linked code review or deployment context
   - worklog or watchers when participation context matters
6. identify the current workflow stage, or the stage being established for
   net-new work, before deciding what Jira action to take
7. treat the Jira action as being in service of completing, unblocking, or
   advancing that stage
8. when issuing a Jira mutation, omit optional tool arguments that are not
   needed and only send valid JSON in fields that Jira documents as JSON
   strings
9. for pure status changes, use `jira_transition_issue` with only the required
   transition arguments unless Jira explicitly requires extra fields, and add
   any note separately with `jira_add_comment`
10. when adding a Jira comment to a normal issue, do not set the optional
    `public` flag; reserve that only for confirmed JSM service-desk requests
11. summarize the findings in plain language and carry only the relevant Jira
   facts into the next technical step
12. when stage-completing work is done, recommend the next workflow step
    instead of asking a generic readiness question
13. update docs if the stable Jira operating pattern changed

## Stage-Aware Guidance

Use this whenever the Jira agent is doing more than a pure read:

1. identify the issue type and current stage first
2. use the issue-type workflow map to decide what the likely next stage is
3. ask follow-up questions only when something is truly missing to complete or
   exit the current stage
4. do not ask "are we ready to move to the next stage?" when Jira state and the
   workflow map already answer that
5. when the current stage is complete, explicitly invite the next transition in
   the response or recommended next actions

## Issue Type Selection Flow

Use this when creating a new Jira issue:

1. if the user does not name a project, use the runtime's configured default
   Jira project unless live Jira metadata or task context makes another project
   necessary
2. decide whether the request is top-level work or child work under an existing issue
3. if it is child work under an existing parent and the user explicitly wants checklist-like child tracking, use `Subtask`
4. otherwise, if something is broken and needs fixing, use `Bug`
5. otherwise, if code work or a new feature is requested, use `Story`
6. otherwise, if it is a simple one-off item, use `Task`
7. if it is code work but the user explicitly wants a lighter "quick task" path to avoid the fuller lifecycle, allow `Task`
8. prefer `Story` or `Bug` over `Task` for normal code work unless the user clearly wants the shortcut
9. treat `Subtask` as rare and avoid using it unless the user explicitly directs it or the work clearly benefits from explicit child-item tracking

## Required Field Gate

Use this whenever an issue is in `REQUIREMENTS` and may be ready to advance:

1. identify whether Jira currently marks any fields as required for this issue
   type, project, or transition
2. check the repo's `jira-required-fields` skill for any additional stable
   repo-specific required field rules
3. verify that every required field is actually populated in Jira
4. do not move the issue out of `REQUIREMENTS` unless that verification passes
5. if verification fails, keep the issue in `REQUIREMENTS`, report the missing
   field or fields, and gather what is needed to fill them

## Bug Lifecycle Flow

Use this when the task is creating or advancing a `Bug` issue:

1. create the bug in `TO DO` with a short baseline summary when the request is
   clearly about something broken that needs fixing
2. move the bug to `REQUIREMENTS` when it is time to gather or lock the fuller
   issue definition
3. in `REQUIREMENTS`, compile and update the Jira description with:
   - `Overview`
   - `Scope`
   - `Requirements`
   - `Acceptance Criteria`
4. format `Requirements` as ordered `REQ-*` items and `Acceptance Criteria` as
   ordered `AC-*` items
5. fill any additional required fields if Jira later introduces them for this
   workflow
6. decide whether `REPLICATE` is needed:
   - if yes, perform replication work and post results as a Jira comment
   - if no, add a Jira comment explicitly saying replication was skipped
7. move back to `REQUIREMENTS` if replication uncovers new questions or missing
   information
8. move to `DONE` directly from `REQUIREMENTS` when the issue is resolved
   without being canceled, such as when the problem turns out to be a training
   issue instead of a true bug
9. move to `TECH LEAD` when the issue is ready for technical validation
10. in `TECH LEAD`, inspect the code at broad strokes, validate the requested
    fix is technically sound, and move back to `REQUIREMENTS` if clarification
    is still needed
11. when `TECH LEAD` is complete, extend the Jira description with:
    - `Tech Lead Notes`
    - `Test Plans`
12. cite specific files and code line numbers in `Tech Lead Notes` when
    possible, and include `Pre Conditions` plus labeled test steps in `Test
    Plans`
13. move to `DEVELOPMENT` when the implementation handoff is ready
14. in `DEVELOPMENT`, pass the locked Jira context to the technical execution
    path, currently the `Code` specialist
15. for the current fast-moving workflow, it is acceptable to commit directly
    to `main`, push the change, and then move Jira through the downstream
    statuses as a lightweight workflow formality
16. use `CANCELED` from any stage when the issue should be abandoned rather
    than completed

When one of these bug stages is completed, invite the next likely stage:

- after `TO DO`, invite `REQUIREMENTS`
- after `REQUIREMENTS`, invite `REPLICATE` if reproduction work is needed, otherwise `TECH LEAD`
- after `REPLICATE`, invite `TECH LEAD` unless new gaps require a return to `REQUIREMENTS`
- after `TECH LEAD`, invite `DEVELOPMENT`
- after implementation, invite the downstream workflow progression

## Story Lifecycle Flow

Use this when the task is creating or advancing a `Story` issue:

1. treat the `Story` lifecycle the same as the `Bug` lifecycle for baseline
   capture, requirements expansion, technical validation, implementation
   handoff, and downstream status progression
2. create the story in `TO DO` with a short baseline summary when the request
   is clearly about new functionality, improvements, or general non-bug code
   work
3. move the story to `REQUIREMENTS` when it is time to gather or lock the
   fuller issue definition
4. in `REQUIREMENTS`, compile and update the Jira description with:
   - `Overview`
   - `Scope`
   - `Requirements`
   - `Acceptance Criteria`
5. format `Requirements` as ordered `REQ-*` items and `Acceptance Criteria` as
   ordered `AC-*` items
6. fill any additional required fields if Jira later introduces them for this
   workflow
7. move to `DONE` directly from `REQUIREMENTS` when the issue is resolved
   without being canceled
8. move to `TECH LEAD` when the issue is ready for technical validation
9. in `TECH LEAD`, inspect the code at broad strokes, validate the requested
   work is technically sound, and move back to `REQUIREMENTS` if clarification
   is still needed
10. when `TECH LEAD` is complete, extend the Jira description with:
    - `Tech Lead Notes`
    - `Test Plans`
11. cite specific files and code line numbers in `Tech Lead Notes` when
    possible, and include `Pre Conditions` plus labeled test steps in `Test
    Plans`
12. move to `DEVELOPMENT` when the implementation handoff is ready
13. in `DEVELOPMENT`, pass the locked Jira context to the technical execution
    path, currently the `Code` specialist
14. for the current fast-moving workflow, it is acceptable to commit directly
    to `main`, push the change, and then move Jira through the downstream
    statuses as a lightweight workflow formality
15. the main functional difference from the `Bug` flow is that `Story` does
    not use the `REPLICATE` stage
16. use `CANCELED` from any stage when the issue should be abandoned rather
    than completed

When one of these story stages is completed, invite the next likely stage:

- after `TO DO`, invite `REQUIREMENTS`
- after `REQUIREMENTS`, invite `TECH LEAD`
- after `TECH LEAD`, invite `DEVELOPMENT`
- after implementation, invite the downstream workflow progression

## Task Lifecycle Flow

Use this when the task is creating or advancing a `Task` issue:

1. treat the `Task` lifecycle as using the same front-end capture model as
   `Story` and `Bug` for `TO DO` and `REQUIREMENTS`
2. create the task in `TO DO` with a short baseline summary
3. move the task to `REQUIREMENTS` when it is time to gather or lock the fuller
   issue definition
4. in `REQUIREMENTS`, compile and update the Jira description with:
   - `Overview`
   - `Scope`
   - `Requirements`
   - `Acceptance Criteria`
5. format `Requirements` as ordered `REQ-*` items and `Acceptance Criteria` as
   ordered `AC-*` items
6. fill any additional required fields if Jira later introduces them for this
   workflow
7. once the work is performed, move the task directly from `REQUIREMENTS` to
   `DONE`
8. use `CANCELED` from any stage when the issue should be abandoned rather
   than completed

When one of these task stages is completed, invite the next likely stage:

- after `TO DO`, invite `REQUIREMENTS`
- after `REQUIREMENTS` plus completed work, invite `DONE`

## Subtask Lifecycle Flow

Use this when the task is creating or advancing a `Subtask` issue:

1. confirm the parent issue first
2. create the subtask in `TO DO`
3. keep the subtask workflow intentionally minimal
4. move the subtask to `DONE` when the work is completed
5. move the subtask to `CANCELED` when the work should be abandoned

When a subtask is complete, invite `DONE` rather than asking an open-ended
workflow question.

## Discovery Flow

Use this when the task starts from a feature name, outage description, release
label, or other fuzzy context:

1. identify the likely project key, board, sprint, or issue type if known
2. run a narrow JQL search or board issue query
3. confirm the best candidate issue or issue set
4. switch from search to direct issue reads once you know the issue keys

## Issue Analysis Flow

Use this when the task already points at a specific issue:

1. read the issue details
2. inspect transitions or changelog if the current status alone is not enough
3. inspect linked development info if the task depends on PR, commit, or branch
   context
4. inspect dates, SLA, watchers, or worklog only when those details answer the
   user’s actual question
5. summarize the issue state, risks, and next relevant actions

## Current Constraint

- The current Jira access path in this repo is not read-only through
  `mcp-atlassian`.
- Read operations should still come first for analysis tasks, but transitions,
  edits, comments, and other mutations are live actions and should be taken
  only when the task actually calls for them.
