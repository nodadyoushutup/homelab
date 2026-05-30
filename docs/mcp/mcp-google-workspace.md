# mcp-google-workspace

Streamable HTTP MCP for **Google Workspace** (Gmail, Calendar, Drive, and other tools from upstream [`workspace-mcp`](https://pypi.org/project/workspace-mcp/)), wrapped by **`applications/mcp-google-workspace/`**. Uses **single-user legacy OAuth** on the server (no MCP OAuth 2.1, no service account). Same client model as **mcp-github**: Cursor connects to `/mcp` with no Bearer token; Google sign-in and tokens live in the container.

## URL and path

Publish the service behind TLS at **`https://mcp.google-workspace.nodadyoushutup.com/mcp`** (or your hostname). The container listens on **8086** via **`applications/mcp-google-workspace/entrypoint.sh`** defaults (`MCP_GOOGLE_WORKSPACE_LISTEN_PORT`); Swarm publishes **18209** → **8086**.

NPM must forward the **entire hostname** (not only `/mcp`) so OAuth paths reach the container: `/oauth2callback`, `/oauth2/*`, `/.well-known/*`, and `/mcp`. See [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md).

## Usage

- Prefer **`GOOGLE_WORKSPACE_MCP_TOOL_TIER=core`** (default in **`applications/mcp-google-workspace/entrypoint.sh`**) unless you need more tools; smaller scope simplifies consent.
- Restrict exposed services with **`GOOGLE_WORKSPACE_MCP_TOOLS`** in Swarm **`env`** (space-separated upstream service keys). Omit it to load all services.
- First tool use that needs Google APIs opens sign-in/consent in the browser (server `/oauth2callback` flow).
- OAuth tokens live in the container under **`WORKSPACE_MCP_CREDENTIALS_DIR`**; redeploy clears them and may require re-consent.
- **`/mcp` is not protected by MCP OAuth 2.1** — treat the hostname like other homelab MCPs (TLS + network trust). Do not expose it on the public internet without accepting that risk.

## Cursor

Project **`.cursor/mcp.json`** registers **`mcp_google_workspace`** at **`https://mcp.google-workspace.nodadyoushutup.com/mcp`** (Streamable HTTP — **`--transport streamable-http`** in **`applications/mcp-google-workspace/entrypoint.sh`**). No client API key — **`GOOGLE_OAUTH_*`** and **`WORKSPACE_EXTERNAL_URL`** live in Swarm **`env`** on **`.config/terraform/components/swarm/mcp-google-workspace/app.tfvars`**. After deploy or config edits, **reload MCP** in Cursor Settings if tools stay disconnected.

## LangGraph

Add a server block in the relevant **`mcp.json`** when a graph should call Google Workspace through this stack.

## Swarm

- Stack: **`terraform/components/swarm/mcp-google-workspace/app/`** — all site config in the **`env`** map on **`.config/terraform/components/swarm/mcp-google-workspace/app.tfvars`** (flat keys such as **`GOOGLE_OAUTH_CLIENT_ID`**, **`GOOGLE_OAUTH_CLIENT_SECRET`**, **`WORKSPACE_EXTERNAL_URL`**, **`GOOGLE_WORKSPACE_MCP_TOOLS`**; no Vault **`secrets`** block or **`env_file_path`**). Keep tokens out of git.

Required keys:

| Key | Description |
| --- | --- |
| `GOOGLE_OAUTH_CLIENT_ID` | Web application OAuth client ID from Google Cloud |
| `GOOGLE_OAUTH_CLIENT_SECRET` | Matching client secret |
| `WORKSPACE_EXTERNAL_URL` | Public HTTPS origin, no trailing slash (e.g. `https://mcp.google-workspace.nodadyoushutup.com`) |

Optional `env` keys:

| Key | Description |
| --- | --- |
| `GOOGLE_WORKSPACE_MCP_TOOLS` | Space-separated upstream service keys to expose (e.g. `gmail drive calendar docs sheets`). Omit to load all services. |
| `USER_GOOGLE_EMAIL` | Default Workspace account for tool calls |
| `MCP_GOOGLE_WORKSPACE_LISTEN_PORT` | Container listen port (default `8086`) |
| `MCP_GOOGLE_WORKSPACE_HOST` | Bind address (default `0.0.0.0`) |
| `GOOGLE_WORKSPACE_MCP_TOOL_TIER` | `core` / `extended` / `complete` (default `core`) |
| `GOOGLE_WORKSPACE_MCP_READ_ONLY` | `true` for read-only OAuth scopes and write-tool filtering |

Valid **`GOOGLE_WORKSPACE_MCP_TOOLS`** service keys: `gmail`, `drive`, `calendar`, `docs`, `sheets`, `slides`, `forms`, `tasks`, `contacts`, `chat`, `search`, `appscript`.

Example restriction (exclude Apps Script, Custom Search, Chat, Contacts, Tasks, Forms, Slides):

```hcl
env = {
  GOOGLE_OAUTH_CLIENT_ID     = "..."
  GOOGLE_OAUTH_CLIENT_SECRET = "..."
  WORKSPACE_EXTERNAL_URL     = "https://mcp.google-workspace.nodadyoushutup.com"
  GOOGLE_WORKSPACE_MCP_TOOLS = "gmail drive calendar docs sheets"
}
```

## Google Cloud OAuth setup

Use a **Google Cloud project** you control (personal or Workspace org).

1. **Open Google Cloud Console** — [https://console.cloud.google.com/](https://console.cloud.google.com/)
2. **Create or select a project** — [Manage resources](https://console.cloud.google.com/cloud-resource-manager)
3. **Configure OAuth consent** — [Google Auth platform → Branding](https://console.developers.google.com/auth/branding) (and Audience / Data Access as prompted). For a single-org homelab, **Internal** user type avoids external verification when all users are in your Workspace domain. Guide: [Configure OAuth consent](https://developers.google.com/workspace/guides/configure-oauth-consent)
4. **Enable APIs** you need (at minimum those for your tool tier), e.g.:
   - [Gmail API](https://console.cloud.google.com/flows/enableapi?apiid=gmail.googleapis.com)
   - [Google Calendar API](https://console.cloud.google.com/flows/enableapi?apiid=calendar-json.googleapis.com)
   - [Google Drive API](https://console.cloud.google.com/flows/enableapi?apiid=drive.googleapis.com)
5. **Create OAuth client** — [APIs & Services → Credentials → Create credentials → OAuth client ID](https://console.cloud.google.com/apis/credentials)
   - Application type: **Web application**
   - **Authorized JavaScript origins:** `https://mcp.google-workspace.nodadyoushutup.com` (your `WORKSPACE_EXTERNAL_URL` origin)
   - **Authorized redirect URIs:** `https://mcp.google-workspace.nodadyoushutup.com/oauth2callback`
   - Copy **Client ID** and **Client secret** into Swarm `env` (never commit secrets).
6. **Workspace auth overview** (background): [Authentication and authorization](https://developers.google.com/workspace/guides/auth-overview)
7. **Upstream FAQ** (redirect URI troubleshooting): [workspacemcp.com FAQ — OAuth](https://workspacemcp.com/welcome/faq#oauth-google-cloud-setup)

## Related

- [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md)
- [docker-build-github-actions.md](../workflows/docker-build-github-actions.md)
- [workspace-mcp docs](https://workspacemcp.com/docs)
