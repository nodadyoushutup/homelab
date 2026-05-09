# Code Filesystem MCP Rules

Use this guidance for filesystem-backed inspection and edits.

## Scope

- The effective repository root is `{{ repo_root }}`.
- Use `.` or repo-relative paths rooted at `{{ repo_root }}`.
- If an absolute path is required, use `{{ repo_root }}` or a child path.
- Do not treat `/`, `/mnt/eapp/code`, or any parent directory as the workspace
  root for this runtime.

## Searching

- Do not run broad recursive searches from `{{ repo_root }}`.
- First list or inspect the top-level directory, then search inside a narrower
  subtree such as `applications`, `docs`, `kubernetes`, `terraform`, or
  `scripts`.
- Use the ast-grep MCP for syntax-aware searches when the task depends on code
  structure rather than plain text.
- Prefer the context-tight loop: use ast-grep to find candidate symbols, calls,
  classes, functions, or config blocks; then use filesystem tools to inspect
  only the files that matter.
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
- If filesystem access cannot complete the task, report the concrete missing
  path, permission, or tool capability.
