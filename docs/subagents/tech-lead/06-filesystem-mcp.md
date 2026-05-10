# Tech Lead Filesystem MCP Rules

Use this guidance for filesystem-backed review.

## Scope

- The effective repository root is `{{ repo_root }}`.
- Use `.` or repo-relative paths rooted at `{{ repo_root }}`.
- If an absolute path is required, use `{{ repo_root }}` or a child path.
- Do not treat `/`, `/mnt/eapp/code`, or any parent directory as the workspace
  root for this runtime.

## Host vs container paths

- `{{ repo_root }}` is the root **for this runtime** (often `/app` in Docker).
  Operators may see `/mnt/eapp/code/homelab` on the host; MCP introspection may
  show `/app`. Those refer to the same checkout; treat differing absolute
  prefixes as normal, not as missing repo or broken MCP.

## Searching

- Do not run broad recursive searches from `{{ repo_root }}`.
- First list or inspect the top-level directory, then search inside a narrower
  subtree such as `applications`, `docs`, `kubernetes`, `terraform`, or
  `scripts`.
- Use the ast-grep MCP for syntax-aware code impact searches when the review
  depends on code structure rather than plain text.
- Prefer the context-tight loop: use ast-grep to find candidate symbols, calls,
  classes, functions, or config blocks; then use filesystem tools to inspect
  only the files needed to judge impact.
- Keep ast-grep `max_results` small. Narrow `project_folder` when technical
  notes, Jira context, or prior findings identify likely subtrees.
- Use `search_repository_files` only after narrowing the directory. It is for
  multi-pattern lookups within a subtree, not for scanning the whole repo.
- When using recursive search, rely on the default excludes:
  `{{ default_search_excludes }}`.

## Failure Handling

- If filesystem results look empty or inconsistent, call introspection tools such
  as `list_allowed_directories` before claiming the repo is missing.
- If a tool reports a recoverable error, treat it as an observation and retry
  with a narrower path, corrected arguments, or a different tool.
- If filesystem access cannot complete the review, report the concrete missing
  path, permission, or tool capability.
