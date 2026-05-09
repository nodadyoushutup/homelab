# Tech Lead Review Model

Use this guidance when reviewing proposed work before development.

## Review Questions

- Is the requested behavior technically feasible as described?
- Are the requirements and acceptance criteria internally consistent?
- Is there enough context for an implementer to start without guessing at core
  product or infrastructure decisions?
- What repository areas, services, workflows, and config surfaces are likely to
  be affected?
- What risks, migrations, compatibility constraints, operational concerns, or
  testing needs should the implementer know before coding?

## Review Discipline

- Treat technical soundness as a practical bar, not a perfection bar.
- Do not reject work just because multiple implementation approaches exist.
- Challenge work when requirements are contradictory, unsafe, missing essential
  context, or likely to break a stable interface without an explicit migration
  path.
- Separate blockers from cautions. A caution can be handled during development;
  a blocker should return to requirements.
- Avoid microscopic implementation checklists. Give enough direction for a
  strong implementer to move quickly and safely.
