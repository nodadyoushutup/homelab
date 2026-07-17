# MCP servers in this repository

Each page describes **how to use** one Model Context Protocol (MCP) server defined in this repo: URL shape, typical clients (Cursor, LangGraph), secrets, and Terraform layout. **Hostnames are yours to choose**; point DNS and TLS at the Swarm ingress (or localhost) where you publish each service.

| Swarm / stack name | Doc |
| --- | --- |
| **mcp-rag** | [mcp-rag.md](mcp-rag.md) |
| **mcp-agentmemory** | [mcp-agentmemory.md](mcp-agentmemory.md) |
| **mcp-github** | [mcp-github.md](mcp-github.md) |
| **mcp-atlassian** | [mcp-atlassian.md](mcp-atlassian.md) |
| **mcp-playwright** | [mcp-playwright.md](mcp-playwright.md) |
| **mcp-argocd** | [mcp-argocd.md](mcp-argocd.md) |
| **mcp-kubernetes** | [mcp-kubernetes.md](mcp-kubernetes.md) |
| **mcp-terraform** | [mcp-terraform.md](mcp-terraform.md) |
| **mcp-cloudflare** | [mcp-cloudflare.md](mcp-cloudflare.md) |
| **mcp-google-workspace** | [mcp-google-workspace.md](mcp-google-workspace.md) |
| **mcp-fortigate** | [mcp-fortigate.md](mcp-fortigate.md) |

For the pattern used when a service gets a new public name (DNS plus reverse proxy), see [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md).

Cursor MCP servers for this repo live in **`.cursor/mcp.json`** (project scope).
**Exception:** **`mcp_agentmemory`** is user-global in **`~/.cursor/mcp.json`** for
cross-project shared memory (see [mcp-agentmemory.md](mcp-agentmemory.md)).
**`mcp_rag`** uses **`${env:MCP_RAG_API_KEY}`** for **`x-api-key`** (see [mcp-rag.md](mcp-rag.md)).
Per-server guides use **`mcp-*.md`** filenames aligned with Swarm stack names
(**`mcp-rag`**, **`mcp-playwright`**, etc.).
