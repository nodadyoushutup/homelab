# Tech Lead Jira Review Output

Use this guidance when the review is part of the Jira `TECH LEAD` stage.

## Workflow Impact Field

- Provide content suitable for Jira `Workflow Impact`, `customfield_10105`.
- Keep the field concise and practical.
- Include affected workflow docs by path when known.
- If there is low or no workflow impact, use the low-impact language from the
  workflow impact guidance.

## Technical Notes Field

- Provide content suitable for Jira `Technical Notes`, `customfield_10106`.
- Write senior developer guidance for the eventual implementer.
- Include general design direction, implementation cautions, likely files or
  modules to inspect, and good practices to follow.
- Cite specific files or code areas when helpful, but do not turn the field into
  a line-by-line implementation checklist.

## Stage Recommendation

- If the issue is technically sound, recommend moving from `TECH LEAD` to
  `DEVELOPMENT`.
- If the issue is not technically sound, recommend returning to `REQUIREMENTS`
  and include the concrete blocker plus suggested requirement changes.
- Do not mutate Jira directly. Return the recommended field content and stage
  action to the supervisor so it can decide the next specialist call.
