# Confluence Workflow

This document describes how to use Confluence in this repo for page discovery,
documentation analysis, and engineering coordination. Use
[`docs/rules/confluence.md`](./../rules/confluence.md) for the steady-state
rules and [`docs/rules/mcp-servers.md`](./../rules/mcp-servers.md) for the
underlying `mcp-atlassian` service constraints.

## Scope

Use this workflow for:

- finding Confluence pages relevant to a task
- summarizing page content, hierarchy, labels, comments, and attachments
- checking page update history, diffs, or views when recency matters
- narrowing documentation context before implementation, incident response, or
  operational analysis

## Standard Flow

When a task needs Confluence context:

1. read `docs/rules/confluence.md`
2. decide whether you already have a specific page id, exact title plus space
   key, or need discovery first
3. if you have a page id or exact page reference, read the page directly before
   doing broader searches
4. if you do not have a precise page reference, run the narrowest Confluence
   search that fits the available context
5. inspect extra Confluence surfaces only as needed:
   - child pages for hierarchy or navigation questions
   - comments for discussion or review context
   - labels for topic classification
   - attachments for source documents or diagrams
   - history, diff, or views when recency and document drift matter
6. summarize the findings in plain language and carry only the relevant
   Confluence facts into the next technical step
7. update docs if the stable Confluence operating pattern changed

## Discovery Flow

Use this when the task starts from a service name, runbook title, outage
description, or other fuzzy context:

1. identify the likely space key, exact page title fragment, label, or keyword
   if known
2. run a narrow Confluence search
3. confirm the best candidate page or page set
4. switch from search to direct page reads once you know the page ids

## Page Analysis Flow

Use this when the task already points at a specific page:

1. read the page details
2. inspect child pages if page hierarchy matters
3. inspect attachments if the task depends on diagrams, exports, or source
   files
4. inspect comments, labels, history, or diff only when those details answer
   the user's actual question
5. summarize the page state, relevant risks, and next useful actions

## Current Constraint

- The current Confluence access path in this repo is not read-only through
  `mcp-atlassian`.
- Read operations should still come first for analysis tasks, but page edits,
  comments, labels, and other mutations are live actions and should be taken
  only when the task actually calls for them.
