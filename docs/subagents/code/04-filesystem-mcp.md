# Code Filesystem MCP Rules (homelab)

Generic scope, search strategy, and failure handling are in the framework **Generic
Code Agent** system prompt. This file is **homelab path mapping**.

## Host vs container paths

- `{{ repo_root }}` is the root **for this runtime** (often `/app` in Docker).
  Operators may see `/mnt/eapp/code/homelab` on the host; MCP introspection may
  show `/app`. Those refer to the same checkout; treat differing absolute prefixes
  as normal, not as missing repo or broken MCP.
- Do not treat `/`, `/mnt/eapp/code`, or any parent directory as the workspace
  root for this runtime.

## Typical subtrees (this repo)

When narrowing searches, common top-level directories include `applications`,
`docs`, `kubernetes`, `terraform`, `scripts`, `pipelines`, and `docker` (see also
`02-repo-discovery.md`).
