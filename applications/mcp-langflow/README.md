# mcp-langflow

`mcp-langflow` is the repo-local HTTP wrapper for the published
`langflow-mcp-server` package from `nobrainer-tech/langflow-mcp`.

This service gives host-reachable MCP clients a stable Streamable HTTP endpoint
for Langflow workspace management without relying on Langflow's own project MCP
server behavior.

## Runtime shape

- upstream MCP package: `langflow-mcp-server@3.1.1`
- transport bridge: `mcp-proxy`
- deployed service name: `mcp-langflow`
- public endpoint: `https://mcp.langflow.nodadyoushutup.com/mcp`

## Required runtime environment

- `LANGFLOW_BASE_URL`
- `LANGFLOW_API_KEY`

Recommended defaults for this repo:

- `LANGFLOW_CONSOLIDATED_TOOLS=true`
- `MCP_MODE=stdio`

The matching Swarm runtime lives in `terraform/swarm/mcp-langflow/app`.
