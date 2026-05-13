# mcp-github

Streamable HTTP MCP backed by the **GitHub** MCP server image: PRs, checks, Actions, and repository queries **without** using local **`git`** on the agent host.

## URL and path

Expose the container’s HTTP MCP port through your ingress with TLS. Clients use the resulting **`https://<your-host>/mcp`** (or the path your proxy maps to the upstream **`/mcp`** equivalent).

## Usage

- Prefer **read-before-write**: inspect PRs, checks, and branch state before mutating.
- In this repo, the **GitHub** LangGraph specialist uses **mcp-github** for GitHub-side work and routes file edits and local git to **code** / **mcp-code**. See [docs/subagents/github/01-runtime.md](../subagents/github/01-runtime.md).

## LangGraph

**`applications/langgraph/subagents/github/mcp.json`** registers **mcp-github** with optional override **`HOMELAB_MCP_GITHUB_URL`**.

## Secrets and Swarm

- Swarm stack: **`terraform/swarm/mcp-github/app/`** — tokens and settings via **`env_file_path`** or the **`env`** map (see **`variables.tf`**). Do not commit secrets.

## Related

- [docker-build-github-actions.md](../workflows/docker-build-github-actions.md)
