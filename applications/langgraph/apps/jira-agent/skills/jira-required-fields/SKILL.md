---
name: jira-required-fields
description: Use this skill for repo-specific Jira required field rules, including which fields are hard requirements, when they must be populated, and how to verify that requirement gates are satisfied before status transitions.
---

# Jira Required Fields

## Overview

This skill is the source of truth for repo-specific Jira required field
handling.

Use it whenever the Jira agent needs to:

- determine whether an issue is missing required fields
- decide whether an issue can leave `REQUIREMENTS`
- explain which Jira fields are hard blockers
- verify that field requirements are satisfied before a status transition
- document future repo-specific required-field rules

Keep required-field gate logic here instead of scattering it across workflow
skills or prompt text.

## Operating Rules

1. Treat required fields as hard gates, not suggestions.
2. Do not move an issue out of `REQUIREMENTS` until all required Jira fields are populated.
3. Before transitioning an issue out of `REQUIREMENTS`, perform a hard check against Jira-backed field data or Jira field metadata to verify the required fields are actually filled.
4. If a required field is missing, stay in `REQUIREMENTS`, report the blocker clearly, and gather what is needed to fill it.
5. If a field is only required for certain issue types, projects, or statuses, document those conditions explicitly here.
6. If a field is required only by team convention rather than Jira enforcement, document that distinction explicitly here.
7. When a field requirement is unclear, inspect Jira field metadata first before guessing.
8. Prefer narrow field updates that satisfy the requirement instead of broad issue rewrites.

## Required Field Template

Use this format when adding a required field definition to this skill:

### `<Field Name>`

- Jira field id: `<customfield_12345>` or standard field name
- Purpose: what this field is for
- Applies to: which issue types, projects, or statuses use it
- Required before: which transition or stage exit it blocks
- Allowed values: list exact values if controlled
- Verification rule: how the Jira agent should confirm the field is satisfied
- Notes: any repo-specific nuance

## Stage Gate Rule

Current repo rule:

- do not allow a ticket to progress out of `REQUIREMENTS` until all required
  fields in Jira are filled in
- perform a hard verification check before leaving `REQUIREMENTS`

## Current Required Field Set

No repo-specific required fields are documented here yet.

Until this section is filled in:

- do not invent required fields
- inspect Jira field metadata before claiming a field is required
- still enforce the stage-gate rule if Jira metadata shows a field is required
- ask a focused follow-up only if the missing required field is truly blocking
  and Jira metadata does not tell you what value is needed
