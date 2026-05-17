# mcp-playwright

Swarm stack and Docker service name: **`mcp-playwright`** (directory **`terraform/swarm/mcp-playwright/`**).

**Streamable HTTP** MCP from the **Playwright MCP** container image: drive a real browser, capture snapshots, and interact with pages. The Swarm stack can bind-mount your repository checkout so tests and fixtures live beside the code.

## URL and path

After DNS and TLS terminate on your edge, point MCP clients at **`https://<your-host>/mcp`** (or whatever path your reverse proxy maps to the task’s HTTP listener). Internal listen port and args are defined in **`terraform/swarm/mcp-playwright/app/main.tf`**.

## Usage

- Wire **Cursor** (or any MCP client) to your public or VPN URL. Example Cursor key in this repo: **`mcp_playwright`** in **`.cursor/mcp.json`**.
- Restrict navigation with **`allowed_hosts`** and related variables in **`terraform/swarm/mcp-playwright/app/`**; configure screenshot/output directories in your **`app.tfvars`**.

## LangGraph

Not part of the checked-in LangGraph **`mcp.json`** files by default; add a server block if a graph should call browser tools directly.

## Deploy

- Swarm: **`terraform/swarm/mcp-playwright/app/`** (explicit **`docker_service`** resource in that root).

## Related

- [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md)
