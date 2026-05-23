# mcp-playwright

Streamable HTTP MCP from the upstream **Playwright MCP** image: drive a headless Chromium browser, capture snapshots, and interact with pages.

## URL and path

Publish the service behind TLS at **`https://mcp.playwright.nodadyoushutup.com/mcp`** (or your hostname). The container listens on **8931**; Swarm publishes **18211** → **8931**.

## Usage

- Wire **Cursor** (or any MCP client) to your public or VPN URL. Example Cursor key in this repo: **`mcp_playwright`** in **`.cursor/mcp.json`**.
- Playwright MCP is **not** a security boundary; restrict edge access and treat browser automation as privileged.

## LangGraph

Not part of the checked-in LangGraph **`mcp.json`** files by default; add a server block if a graph should call browser tools directly.

## Swarm

- Stack: **`terraform/swarm/mcp-playwright/app/`** — optional container settings in the **`env`** map on **`.config/terraform/swarm/mcp-playwright/app.tfvars`** (no Vault **`secrets`** block or **`env_file_path`**).
- Image and ingress port **18211** are pinned in **`terraform/swarm/mcp-playwright/app/main.tf`**. The stack runs the upstream **`mcr.microsoft.com/playwright/mcp:latest`** image with headless Chromium and ephemeral output under **`/tmp/playwright`** (no NFS mounts in the current layout).

## Related

- [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md)
