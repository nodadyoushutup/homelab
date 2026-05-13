# MCP servers in this repository

Each page describes **how to use** one Model Context Protocol (MCP) server defined in this repo: URL shape, typical clients (Cursor, LangGraph), secrets, and Terraform layout. **Hostnames are yours to choose**; point DNS and TLS at the Swarm ingress (or localhost) where you publish each service.

| Swarm / stack name | Doc |
| --- | --- |
| **mcp-rag** | [mcp-rag.md](mcp-rag.md) |
| **mcp-code** | [mcp-code.md](mcp-code.md) |
| **mcp-github** | [mcp-github.md](mcp-github.md) |
| **mcp-atlassian** | [mcp-atlassian.md](mcp-atlassian.md) |
| **playwright-mcp** | [mcp-playwright.md](mcp-playwright.md) |
| **mcp-argocd** | [mcp-argocd.md](mcp-argocd.md) |
| **mcp-kubernetes** | [mcp-kubernetes.md](mcp-kubernetes.md) |
| **mcp-terraform** | [mcp-terraform.md](mcp-terraform.md) |
| **mcp-cloudflare** | [mcp-cloudflare.md](mcp-cloudflare.md) |
| **mcp-google-workspace** | [mcp-google-workspace.md](mcp-google-workspace.md) |
| **mcp-fortigate** | [mcp-fortigate.md](mcp-fortigate.md) |
| **mcp-bash-pipeline** | [mcp-bash-pipeline.md](mcp-bash-pipeline.md) |

For the pattern used when a service gets a new public name (DNS plus reverse proxy), see [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md).

Example Cursor wiring for a subset of servers lives in **`.cursor/mcp.json`** (URLs are environment-specific). Per-server guides use **`mcp-*.md`** filenames; Playwright’s Swarm service is **`playwright-mcp`**, documented in **`mcp-playwright.md`**.
