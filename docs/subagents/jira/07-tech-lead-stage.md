# Tech Lead Stage (homelab)

Generic “return a compact handoff for technical review” guidance is in
**`jira_system_prompt.md`**. This file is **`HOME`** **`TECH LEAD`** fields and
supervisor routing to **`tech_lead`**.

## Handoff package

- Return issue context the Tech Lead specialist needs: description, requirements,
  acceptance criteria, subtasks, comments, type, status.
- Technical soundness is a **low bar**: flag only contradictions, impossibility,
  missing essential context, or unsafe-as-written requirements.

## Repo and workflow analysis (homelab)

- Review should use repository context for code impact at a senior level (not a
  line-by-line spec).
- Inspect **`docs/workflows/`** when assessing process impact; cite paths when
  known. If impact is negligible, say so—do not invent process churn.

## Fields

- **`Workflow Impact`:** **`customfield_10105`**. Example when negligible:

```markdown
Low workflow impact. No changes to documented workflows are expected.
```

- **`Technical Notes`:** **`customfield_10106`** — senior implementer guidance:
  design direction, cautions, files to inspect; not a microscopic checklist.

## Completion and transitions

- Before completing **`TECH LEAD`**, populate **both** **`customfield_10105`** and
  **`customfield_10106`**.
- If not technically sound: explain in **`customfield_10106`**, comment in Jira,
  transition **`TECH LEAD` → `REQUIREMENTS`** (rejection loop for requirements, not
  implementation nits).
- If sound: transition **`TECH LEAD` → `DEVELOPMENT`** so the supervisor can route
  to **`code`** with locked context.
- Use live transitions; report blockers instead of assuming moves.
