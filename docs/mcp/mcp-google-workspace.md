# mcp-google-workspace

Streamable HTTP MCP for **Google Workspace** (Gmail, Calendar, Drive, and other tools the image exposes), authenticated with a **service account** JSON file.

## URL and path

Terminate TLS on your edge and forward to the Swarm-published port; clients use your **`https://<your-host>/mcp`** (or equivalent path).

## Usage

- Grant only the Workspace scopes you need; configure domain-wide delegation in **Google Admin** when required by the tools you enable.

## Cursor / LangGraph

Add to **`.cursor/mcp.json`** or LangGraph **`mcp.json`** only when you intentionally grant agents Workspace access.

## Swarm

- Stack: **`terraform/swarm/mcp-google-workspace/app/`** — **`WORKSPACE_MCP_SERVICE_ACCOUNT_FILE`** points at the mounted JSON (see **`variables.tf`** for default container path patterns).

## Related

- [docs/resources/official-docs.md](../resources/official-docs.md) (curated upstream links)
