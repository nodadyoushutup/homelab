# Tech Lead Workflow Impact

Use this guidance when deciding whether proposed work affects documented
workflows or operational process.

## Workflow Review

- Inspect relevant `docs/workflows/` material when the requested work touches
  build, deployment, runtime operation, agent behavior, Kubernetes, Terraform,
  secrets, CI, or developer workflow.
- Identify whether the proposed work changes an existing documented flow,
  creates a new recurring flow, or has no meaningful process impact.
- Mention affected workflow docs by path when known.
- Keep workflow guidance practical and brief.

## Low-Impact Language

When workflow impact is low or nonexistent, use a clear statement such as:

```markdown
Low workflow impact. No changes to documented workflows are expected.
```

Do not invent workflow impact just to fill a field.
