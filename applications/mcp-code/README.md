# mcp-code

Single **streamable HTTP** MCP endpoint that exposes the union of tools from:

- `@modelcontextprotocol/server-filesystem` (workspace directory argument)
- `mcp-server-git` (`--repository` set to the same workspace root)
- The homelab **ast-grep** server (`ast-grep-bundled/server.py` over stdio)

System dependencies and versions follow `scripts/install/mcp_code_tooling.sh`. The
ast-grep stdio server script and `sgconfig.yml` are vendored under
`ast-grep-bundled/`.

## Build

Use repository root as context (see `.github/workflows/docker_build_push.yml` target `mcp-code`):

```bash
docker build -f applications/mcp-code/Dockerfile -t mcp-code:dev .
```

Arm64 Swarm nodes (from repo root, after `HARBOR_USERNAME` / `HARBOR_PASSWORD` are set, e.g. in `.secrets/.env`):

```bash
./scripts/agents/publish_mcp_code_harbor.sh
```

Then run `pipelines/terraform/swarm/mcp-code/app.sh` (uses `<repo>/.config/terraform/providers/docker_arm64.tfvars` or `docker_amd64.tfvars` for `swarm_docker_provider_config`; see `docs/workflows/docker-build-github-actions.md` for publish discipline).

## Runtime

| Variable | Default | Purpose |
| --- | --- | --- |
| `MCP_CODE_WORKSPACE_ROOT` | `/mnt/eapp/code/homelab` | Filesystem + git root |
| `MCP_CODE_HOST` | `0.0.0.0` | Bind address |
| `MCP_CODE_PORT` | `8100` | Listen port |
| `MCP_HTTP_PATH` | `/mcp` | HTTP path |
| `AST_GREP_CONFIG` | `/opt/ast-grep-config/sgconfig.yml` | ast-grep config |
| `AST_GREP_DEFAULT_PROJECT_ROOT` | same as `MCP_CODE_WORKSPACE_ROOT` | Override ast-grep default scan root |
| `AST_GREP_ALLOWED_ROOTS` | same as `MCP_CODE_WORKSPACE_ROOT` | `:`-separated allow list |

Ast-grep uses the same workspace as filesystem and git unless you set the optional `AST_GREP_*` overrides.

## Concurrent agents and Git worktrees

One mcp-code **process** = one **working tree**. Multiple clients on the same
endpoint share that tree. For **parallel** agents each editing their **own**
branch without collisions, use **Git worktrees** (separate directories) and run
**separate** mcp-code deployments (or endpoints) with `MCP_CODE_WORKSPACE_ROOT`
pointing at each worktree. See **`docs/workflows/mcp-code-worktrees-and-multi-agent.md`**.

Swarm Terraform lives under `terraform/swarm/mcp-code/app/`.

Production HTTPS (Nginx Proxy Manager), same pattern as other MCP hosts:

- `https://mcp.code.nodadyoushutup.com/mcp`

Cloudflare **`A`** record and NPM **`proxy_hosts`** / **`certificates`** live in **`<repo>/.config/terraform/remote/cloudflare/config.tfvars`** and **`<repo>/.config/terraform/swarm/nginx_proxy_manager/config.tfvars`** (forward to Swarm ingress **`192.168.1.120:18212`** by default).
