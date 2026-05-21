# mcp-cloudflare

Streamable HTTP MCP for **Cloudflare** DNS and related API operations using the **`mcp-cloudflare`** image built from this repository.

## URL and path

Publish the service behind TLS at **`https://mcp.cloudflare.nodadyoushutup.com/mcp`** (or your hostname). The container listens on **8084** via **`applications/mcp-cloudflare/entrypoint.sh`** defaults; Swarm publishes **18204** → **8084**.

## Usage

- Use for **DNS record inspection**, zone operations, and other tools the server implements—always confirm zone and account.
- Keep **API tokens** narrowly scoped; DNS is security-sensitive.

## Cursor

Project **`.cursor/mcp.json`** can register **`mcp_cloudflare`** at your public MCP URL. No client API key — **`CLOUDFLARE_API_TOKEN`**, **`CLOUDFLARE_ZONE_ID`**, and related settings live in Swarm **`env`** on **`.config/terraform/swarm/mcp-cloudflare/app.tfvars`**. For all workspaces, add the same block to **User** MCP settings or **`~/.cursor/mcp.json`**.

## LangGraph

Add a server block in the relevant **`mcp.json`** when a graph should call Cloudflare through this stack.

## Swarm

- Stack: **`terraform/swarm/mcp-cloudflare/app/`** — credentials and settings in **`env`** on **`.config/terraform/swarm/mcp-cloudflare/app.tfvars`** (see **`variables.tf`**). Keep tokens out of git.

## Related

- [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md)
