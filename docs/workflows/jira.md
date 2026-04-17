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
6. summarize the findings in plain language and carry only the relevant Jira
   facts into the next technical step
7. update docs if the stable Jira operating pattern changed

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
