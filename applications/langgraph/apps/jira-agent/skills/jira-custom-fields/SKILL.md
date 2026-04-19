---
name: jira-custom-fields
description: Use this skill for repo-specific Jira custom field rules, including what each custom field means, when it is required, how it should be populated, and what values are valid.
---

# Jira Custom Fields

## Overview

This skill is the source of truth for repo-specific Jira custom field handling.

Use it whenever the Jira agent needs to:

- read or interpret a custom field on an issue
- decide whether a custom field should be set
- choose a valid custom-field value
- explain what a custom field means in this Jira setup
- update a custom field during issue creation or later issue edits

Keep custom-field semantics here instead of scattering them across workflow
skills or prompt text.

## Operating Rules

1. Treat standard Jira fields and custom Jira fields differently. Do not assume a custom field behaves like a standard field just because the label sounds familiar.
2. If a custom field is documented in this skill, follow that documentation over generic assumptions.
3. If a custom field is not documented here, inspect Jira field metadata first before guessing.
4. Record any stable repo-specific custom field meanings, requiredness, defaults, and allowed values here once they are known.
5. If a field is conditionally required for only some issue types or statuses, document those conditions explicitly here.
6. If a field uses controlled vocabulary, document the exact allowed values and any usage guidance here.
7. If a field should be left blank by default unless the user explicitly asks, document that rule here.
8. When updating custom fields, prefer narrow and deliberate field mutations over broad issue rewrites.

## Field Template

Use this format when adding a custom field definition to this skill:

### `<Field Name>`

- Jira field id: `<customfield_12345>` if known
- Purpose: what this field means in your Jira setup
- Applies to: which issue types use it
- Required when: creation, specific statuses, or conditional cases
- Allowed values: list exact values if controlled
- Default behavior: what to do when the user does not mention it
- Update rules: when the Jira agent should set or change it
- Notes: any repo-specific nuance

## Current Custom Field Set

No custom fields are documented here yet.

Until this section is filled in:

- do not invent custom field meanings
- inspect Jira field metadata before setting unfamiliar custom fields
- ask a focused follow-up only if the field is truly blocking and Jira metadata does not answer it
