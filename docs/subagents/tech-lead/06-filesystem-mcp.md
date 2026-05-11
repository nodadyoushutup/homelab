# Tech Lead Filesystem MCP (homelab)

Generic search and scope rules are in **`tech_lead_system_prompt.md`** (**Tool use
and search**).

## Paths

- `{{ repo_root }}` is the runtime root (often `/app` in Docker); host may show
  `/mnt/eapp/code/homelab` — same checkout, different prefix.
- Do not treat `/` or `/mnt/eapp/code` as the workspace root.

## Typical subtrees

Narrow searches under `applications`, `docs`, `kubernetes`, `terraform`, `scripts`,
or other top-level dirs as appropriate.
