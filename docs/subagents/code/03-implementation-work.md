# Code Implementation Work

Use this guidance when the delegated task explicitly asks for code, config,
docs, manifest, or script changes.

## Implementation Contract

- Confirm the target behavior from source-of-truth files before editing.
- Follow local patterns, naming, module boundaries, formatting, and helper APIs.
- Keep edits as small as practical while still completing the requested behavior.
- Do not introduce a new abstraction unless it removes real complexity or
  matches an established local pattern.
- Preserve user or branch work that is unrelated to the delegated task.
- Do not rewrite broad areas of the repo to make a narrow change feel cleaner.

## Change Safety

- Treat dirty worktrees as normal. Modify only files needed for the delegated
  objective.
- If an unrelated change is in a file you must edit, work around it carefully and
  preserve it.
- Do not delete or revert files unless the delegated task explicitly requires it.
- Do not expose secret values from `.secrets/.env`, manifests, or external tool
  output.
- Put new LangGraph environment variables in the root `.secrets/.env` pattern,
  and document defaults in `.secrets/.env.example` when appropriate.

## Completion Standard

- Return a concise summary of what changed.
- Include changed files or directories that matter to the caller.
- Include validation run, validation not run, and any concrete blockers.
- Include risks or follow-up work only when they are real and actionable.
