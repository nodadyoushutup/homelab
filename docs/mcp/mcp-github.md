# mcp-github

Streamable HTTP MCP for **GitHub** API operations (PRs, checks, Actions, repository queries) using the **`mcp-github`** image built from this repository.

## URL and path

Publish the service behind TLS at **`https://mcp.github.nodadyoushutup.com/mcp`** (or your hostname). The container listens on **8082** via **`applications/mcp-github/entrypoint.sh`** defaults; Swarm publishes **18208** → **8082**.

## Usage

- Prefer **read-before-write**: inspect PRs, checks, and branch state before mutating.
- In this repo, the **GitHub** LangGraph specialist uses **mcp-github** for GitHub-side work. File edits and local git run in the IDE or via **code** with worktree-scoped MCP tools (RAG, Atlassian, etc.)—not a dedicated repo filesystem MCP. See [docs/subagents/github/01-runtime.md](../subagents/github/01-runtime.md).

## Cursor

Project **`.cursor/mcp.json`** registers **`mcp_github`** at **`https://mcp.github.nodadyoushutup.com/mcp`** (Streamable HTTP — **`--transport streamablehttp`** in **`applications/mcp-github/entrypoint.sh`**). No client API key — **`GITHUB_PERSONAL_ACCESS_TOKEN`** lives in Swarm **`env`** on **`.config/terraform/components/swarm/mcp-github/app.tfvars`**. After deploy or config edits, **reload MCP** in Cursor Settings if tools stay disconnected.

## LangGraph

**`applications/langgraph/subagents/github/mcp.json`** registers **mcp-github** with optional override **`HOMELAB_MCP_GITHUB_URL`**.

## Swarm

- Stack: **`terraform/components/swarm/mcp-github/app/`** — all site credentials in the **`env`** map on **`.config/terraform/components/swarm/mcp-github/app.tfvars`** (flat keys such as **`GITHUB_PERSONAL_ACCESS_TOKEN`**; no Vault **`secrets`** block or **`env_file_path`**). Keep tokens out of git.

## Related

- [docker-build-github-actions.md](../workflows/docker-build-github-actions.md)
