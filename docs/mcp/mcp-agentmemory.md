# mcp-agentmemory

Remote Streamable HTTP MCP in front of a Swarm-hosted **agentmemory** server
(shared Cursor agent memory across chats and projects).

## Endpoint

Publish behind TLS at **`https://mcp.agentmemory.nodadyoushutup.com/mcp`**.

| Service | Role | Port |
| --- | --- | --- |
| **agentmemory** | Memory API + iii engine; stateful `/data` | **3111** (overlay only) |
| **mcp-agentmemory** | `mcp-proxy` + `x-api-key` gateway wrapping `@agentmemory/mcp` | Swarm **18212** → **8087** |

## Auth

- Clients must send header **`x-api-key`** with **`MCP_AGENTMEMORY_API_KEY`**.
- The gateway calls agentmemory with Bearer **`AGENTMEMORY_SECRET`** (overlay-internal).

Set both in **`.config/terraform/swarm/mcp-agentmemory/app.tfvars`** `env`. Export
**`MCP_AGENTMEMORY_API_KEY`** for Cursor from **`.config/docker/mcp.env`**.

## Cursor (global)

Unlike other Homelab MCPs (project `.cursor/mcp.json` only), **`mcp_agentmemory`**
is wired in **user-global** **`~/.cursor/mcp.json`** so memory is shared across
projects:

```json
{
  "mcpServers": {
    "mcp_agentmemory": {
      "url": "https://mcp.agentmemory.nodadyoushutup.com/mcp",
      "headers": {
        "x-api-key": "${env:MCP_AGENTMEMORY_API_KEY}"
      }
    }
  }
}
```

Reload MCP in Cursor Settings after changing the file or env. See **AGENTS.md**
for this intentional exception.

## Swarm

- Stack: **`terraform/components/swarm/mcp-agentmemory/app/`**
- Pipeline: **`terraform/components/swarm/mcp-agentmemory/pipeline/app.sh`**
- Placement: **`swarm-wk-4`**
- Images: **`ghcr.io/nodadyoushutup/agentmemory`**, **`ghcr.io/nodadyoushutup/mcp-agentmemory`**
- Edge: Cloudflare A + NPM certificate/proxy host (forward **18212**)

## Smoke tests

```bash
# Gateway rejects missing key
curl -sS -o /dev/null -w '%{http_code}\n' \
  https://mcp.agentmemory.nodadyoushutup.com/mcp

# With key (expect MCP/protocol response, not 401)
curl -sS -H "x-api-key: ${MCP_AGENTMEMORY_API_KEY}" \
  -H 'Accept: application/json, text/event-stream' \
  https://mcp.agentmemory.nodadyoushutup.com/mcp | head
```

In Cursor: Chat A — remember a unique string; Chat B — recall it.
