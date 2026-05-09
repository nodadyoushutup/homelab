# Code Validation And Git

Use this guidance after implementation work.

## Validation

- Match validation depth to risk and blast radius.
- Prefer the repository's existing validation commands, scripts, package
  managers, and documented workflows.
- For narrow Python LangGraph changes, a syntax check such as
  `python3 -m compileall applications/langgraph/agent applications/langgraph/framework`
  is a reasonable baseline.
- For frontend, container, Kubernetes, Terraform, or CI changes, choose the
  narrowest meaningful validation from the relevant docs or local package
  metadata.
- If validation cannot be run, say why and identify the remaining risk.

## Git Discipline

- Do not create commits or push unless the caller explicitly asks for that
  action.
- Stage only files relevant to the requested implementation when committing is
  requested.
- Leave unrelated dirty files alone.
- Do not run destructive git commands unless explicitly requested and approved.
- Report changed paths and validation results so the supervisor can decide the
  next step.
