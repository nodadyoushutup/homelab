# mcp-cloudflare

Streamable HTTP MCP for **Cloudflare** DNS and related API operations using the **`mcp-cloudflare`** image built from this repository.

## URL and path

Publish the Swarm service behind TLS at a hostname you own; clients call your Streamable MCP URL (internal listen defaults include **`MCP_CLOUDFLARE_LISTEN_PORT`** in **`terraform/swarm/mcp-cloudflare/app/main.tf`**).

## Usage

- Use for **DNS record inspection**, zone operations, and other tools the server implements—always confirm zone and account.
- Keep **API tokens** narrowly scoped; DNS is security-sensitive.

## Cursor / LangGraph

Enable explicitly in **`.cursor/mcp.json`** or LangGraph **`mcp.json`** when agents should call Cloudflare through this service.

## Swarm

- Stack: **`terraform/swarm/mcp-cloudflare/app/`** — **`MCP_CLOUDFLARE_*`** and token variables via **`env_file_path`** or **`env`**.

## Related

- [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md)
