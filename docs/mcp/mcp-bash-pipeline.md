# mcp-bash-pipeline

**FastMCP** server that runs **approved shell pipeline scripts** under this repository’s **`pipelines/`** tree with timeouts and output caps. HTTP transport uses path **`/mcp`** by default (**`BASH_PIPELINE_HTTP_PATH`**).

## URL and path

Expose **`BASH_PIPELINE_PORT`** (default **`8107`**) through your reverse proxy with TLS; clients use **`https://<your-host>/mcp`** unless you remap paths.

## Usage

- Clients may select workspace roots via headers such as **`x-workspace-root`** / **`x-homelab-workspace`** (defaults align with **`BASH_PIPELINE_*`** env in **`terraform/swarm/mcp-bash-pipeline/app/main.tf`**).
- Some pipelines are **blocked** server-side (see **`applications/mcp-bash-pipeline/src/mcp_bash_pipeline/server.py`**, **`BLOCKED_PIPELINES`**).

## Cursor / LangGraph

Add your URL to **`.cursor/mcp.json`** or LangGraph **`mcp.json`** if agents should dispatch pipelines through MCP.

## Swarm

- Stack: **`terraform/swarm/mcp-bash-pipeline/app/`** — mounts code and config volumes per **`variables.tf`**.

## Related

- **`applications/mcp-bash-pipeline/`**
