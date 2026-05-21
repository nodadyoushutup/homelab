# mcp-cloudflare

Streamable HTTP MCP for **Cloudflare** DNS and related API operations using the **`mcp-cloudflare`** image built from this repository.

## URL and path

Publish the service behind TLS at **`https://mcp.cloudflare.nodadyoushutup.com/mcp`** (or your hostname). The container listens on **8084** via **`applications/mcp-cloudflare/entrypoint.sh`** defaults; Swarm publishes **18204** → **8084**.

## Usage

- Use for **DNS record inspection**, zone operations, and other tools the server implements—always confirm zone and account.
- Keep **API tokens** narrowly scoped; DNS is security-sensitive.

## Cursor

Project **`.cursor/mcp.json`** registers **`mcp_cloudflare`** at **`https://mcp.cloudflare.nodadyoushutup.com/mcp`** (Streamable HTTP — **`--transport streamablehttp`** in **`applications/mcp-cloudflare/entrypoint.sh`**). No client API key — **`CLOUDFLARE_*`** credentials live in Swarm **`env`** on **`.config/terraform/swarm/mcp-cloudflare/app.tfvars`**. After deploy or config edits, **reload MCP** in Cursor Settings if tools stay disconnected.

## LangGraph

Add a server block in the relevant **`mcp.json`** when a graph should call Cloudflare through this stack.

## Swarm

- Stack: **`terraform/swarm/mcp-cloudflare/app/`** — all site credentials in the **`env`** map on **`.config/terraform/swarm/mcp-cloudflare/app.tfvars`** (flat keys such as **`CLOUDFLARE_*`**; no Vault **`secrets`** block). The task uses **`CLOUDFLARE_*`** for the MCP server; keep tokens out of git.

## Related

- [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md)
