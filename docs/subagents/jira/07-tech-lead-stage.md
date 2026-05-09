# Tech Lead Stage

These instructions describe the `TECH LEAD` flow now that the runtime has a
concrete Tech Lead specialist for technical review and code analysis.

## Handoff Intent

- When a Jira issue enters technical review or the user asks for technical code
  analysis on a Jira issue, return a compact review package so the supervisor can
  route the technical-review request to `tech_lead`.
- The Jira result returned to the supervisor should include the issue context
  the Tech Lead specialist needs first: description, requirements, acceptance
  criteria, subtasks, comments, issue type, and current status.
- The first review question is whether the issue is technically sound: can this
  reasonably be done as described?
- Treat technical soundness as a low bar. Most work is expected to be feasible;
  call out blockers only when the requirements are contradictory, impossible,
  missing essential context, or technically unsafe as written.

## Code And Workflow Analysis

- The Tech Lead review should use available repository context to perform code
  analysis for the proposed change.
- The Tech Lead review should determine the likely impact area of the codebase
  at a useful senior-engineer level, without becoming a line-by-line
  implementation guide.
- The Tech Lead review should inspect `docs/workflows/` for process guidance
  that may be affected by the proposed work.
- The Tech Lead review should identify impact to existing workflows, including
  end-to-end workflows and smaller unit workflows.
- If workflow impact is low or nonexistent, the review should say that clearly.
  Do not invent process impact just to fill the field.

## Workflow Impact Field

- Store workflow impact in `Workflow Impact`, `customfield_10105`.
- Keep the field concise and practical.
- Mention affected workflow docs by path when known.
- If there is low or no workflow impact, use a clear statement such as:

```markdown
Low workflow impact. No changes to documented workflows are expected.
```

## Technical Notes Field

- Store technical notes in `Technical Notes`, `customfield_10106`.
- Write technical notes as senior developer guidance for the eventual
  implementer.
- Include general design direction, implementation cautions, useful files or
  modules to inspect, and good practices to follow.
- Cite specific files or code areas when helpful, but do not turn the field into
  a microscopic implementation checklist.
- Keep the notes aligned with the technical vision and the likely code impact.

## Completion Rule

- Before considering `TECH LEAD` complete, populate both
  `customfield_10105` and `customfield_10106`.
- If the issue is not technically sound, explain the blocker in
  `customfield_10106` and recommend returning to `REQUIREMENTS`.
- If the Tech Lead specialist finds serious issues with the requirements or
  acceptance criteria, the supervisor should route the resulting Jira update
  back to Jira so the main issue can move from `TECH LEAD` back to
  `REQUIREMENTS`.
- When returning an issue to `REQUIREMENTS`, add a Jira comment explaining the
  concerns, the reasons for rejecting or challenging the problematic ideas, and
  concrete suggestions for how requirements gathering should fix them.
- Treat the `TECH LEAD -> REQUIREMENTS` transition as a rejection loop for
  requirements rework, not as implementation feedback.
- If the issue is technically sound, use the fields to prepare the developer for
  implementation.
- When the issue is technically sound and both Tech Lead fields are populated,
  transition the main issue from `TECH LEAD` to `DEVELOPMENT`.
- Treat the `TECH LEAD -> DEVELOPMENT` transition as the point where the
  supervisor can route the locked Jira context and Tech Lead notes to the Code
  specialist.
- If Jira does not expose a direct `DEVELOPMENT` transition, inspect live
  transitions and report the blocker instead of pretending the handoff happened.
