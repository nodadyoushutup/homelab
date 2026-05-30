# mcp-atlassian

Streamable HTTP MCP for **Atlassian Cloud** operations (Jira issues, boards, Confluence where exposed by the server).

## URL and path

Publish the service behind HTTPS; clients call the Streamable MCP URL your proxy forwards to the task (path **`/mcp`** — default **`CMD`** in **`applications/mcp-atlassian/Dockerfile`**; override via Swarm **`args`** if needed).

## Usage

- Use for **Jira discovery**, transitions, comments, and Confluence reads/writes that the tool surface supports.
- Jira agent policy in this repo: [docs/subagents/jira/01-runtime.md](../subagents/jira/01-runtime.md) and framework prompts under **`applications/langgraph/framework/agents/system_prompts/`**.

## Cursor

Project **`.cursor/mcp.json`** registers **`mcp_atlassian`** at **`https://mcp.atlassian.nodadyoushutup.com/mcp`**. No client API key — Jira/Confluence credentials live in Swarm **`env`** on **`.config/terraform/components/swarm/mcp-atlassian/app.tfvars`**. After deploy or config edits, **reload MCP** in Cursor Settings if tools stay disconnected.

## LangGraph

**`applications/langgraph/subagents/jira/mcp.json`** registers the Atlassian server (key **`atlassian`**) with optional override **`HOMELAB_MCP_ATLASSIAN_URL`**.

## Secrets and Swarm

- Swarm stack: **`terraform/components/swarm/mcp-atlassian/app/`** — credentials and site settings in **`env`** on **`.config/terraform/components/swarm/mcp-atlassian/app.tfvars`** (see **`variables.tf`**). Keep tokens out of git.

## Related

- [mcp-rag.md](mcp-rag.md) (supervisor and Jira agent also use **mcp-rag**)
