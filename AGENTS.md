# AGENTS

This repo is docs-driven when live `docs/` exists. Treat archived material under
`.old/` as **out of scope**.

## Ignore `.old/` completely

**Do not read, update, restore, or cite anything under `<repo>/.old/`.**

- Never edit files in `.old/` (including archived docs, AGENTS backups, or old
  workflows).
- Never migrate content out of `.old/` unless the user explicitly asks to restore
  a named path.
- Prefer live `docs/`, code, and `.config/` as sources of truth. If live docs are
  missing, work from code and config — do not fall back to `.old/`.

## Hard cuts only — no legacy support

**When changing code, configs, or APIs in this repo, never keep backward
compatibility with the old shape.**

- Do **not** add fallbacks, dual-read paths, deprecation shims, or silent
  migration helpers.
- **Hard cut every change:** remove the old path, update callers in the same
  change, and state what operators must update if the edit is breaking.

## Do not add `*.tfvars.example` files

**Do not create, restore, or expand checked-in `*.tfvars.example`** unless the
user explicitly asks. Live operator config belongs under
`<repo>/.config/terraform/**`.

## Config

- Tfvars live under `<repo>/.config/terraform/**` (mirroring
  `terraform/components/`).
- Docker/local dotenv lives under `<repo>/.config/docker/`.
- Pipelines use `scripts/terraform/load_root_env.sh`.

## Cursor / MCP

- Use Cursor shell and local file tools for repo filesystem work.
- Homelab MCP servers are configured in project `.cursor/mcp.json`.
- **`mcp_agentmemory`** is user-global in `~/.cursor/mcp.json`.
