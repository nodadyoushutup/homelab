# Markdown documentation best practices (homelab)

Apply when editing `docs/**/*.md` and agent contract markdown. This page is
**repository documentation policy**; general response and output shape for the Code
specialist are in the framework **Generic Code Agent** system prompt (**Output
contract**).

- Treat `docs/` as source of truth for repeatable workflows; link to code
  paths with backticks, not vague descriptions.
- Keep headings hierarchical; one H1 per page unless the file is a fragment
  intentionally embedded elsewhere.
- Prefer precise commands and paths over generic instructions when documenting
  operations.
- When changing runtime behavior, update the matching contract under
  `docs/workflows/agents.md` or `docs/subagents/` in the same change when applicable.
