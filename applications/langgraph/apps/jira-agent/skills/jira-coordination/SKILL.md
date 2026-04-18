---
name: jira-coordination
description: Use this skill for Jira agent routing decisions and Jira-specific guardrails before delegating to a create or edit specialist.
---

# Jira Coordination

## Overview

This skill helps the Jira parent agent choose the right internal specialist and
keep delegation envelopes small.

## Instructions

1. Decide whether the request is about creating new work or changing existing work.
2. Delegate to `create_issue` for new issues.
3. Delegate to `edit_issue` for changes to an existing issue.
4. Pass only the Jira context needed by the internal specialist.
