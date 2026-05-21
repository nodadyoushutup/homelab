# mcp-google-workspace

Streamable HTTP MCP for **Google Workspace** (Gmail, Calendar, Drive, and other tools from upstream [`workspace-mcp`](https://pypi.org/project/workspace-mcp/)), using **native OAuth 2.1** (no service account).

## URL and path

Publish the service behind TLS at **`https://mcp.google-workspace.nodadyoushutup.com/mcp`** (or your hostname). The container listens on **8086**; Swarm publishes **18209** → **8086**.

NPM must forward the **entire hostname** (not only `/mcp`) so OAuth paths reach the container: `/oauth2callback`, `/oauth2/*`, `/.well-known/*`, and `/mcp`. See [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md).

## Usage

- Prefer **`GOOGLE_WORKSPACE_MCP_TOOL_TIER=core`** (default in the image entrypoint) unless you need more tools; smaller scope simplifies consent.
- First authenticated MCP use opens Google sign-in/consent in the browser.
- OAuth tokens live in the container under `WORKSPACE_MCP_CREDENTIALS_DIR`; redeploy clears them and may require re-consent.

## Cursor

Add to project **`.cursor/mcp.json`** when you want Workspace access:

```json
{
  "mcpServers": {
    "mcp_google_workspace": {
      "url": "https://mcp.google-workspace.nodadyoushutup.com/mcp"
    }
  }
}
```

Reload MCP in Cursor Settings after deploy or config changes.

## Swarm

- Stack: **`terraform/swarm/mcp-google-workspace/app/`**
- Credentials: flat **`env`** map on **`.config/terraform/swarm/mcp-google-workspace/app.tfvars`** (no NFS config mount, no service account JSON).

Required keys:

| Key | Description |
| --- | --- |
| `GOOGLE_OAUTH_CLIENT_ID` | Web application OAuth client ID from Google Cloud |
| `GOOGLE_OAUTH_CLIENT_SECRET` | Matching client secret |
| `WORKSPACE_EXTERNAL_URL` | Public HTTPS origin, no trailing slash (e.g. `https://mcp.google-workspace.nodadyoushutup.com`) |

Optional: `GOOGLE_WORKSPACE_MCP_TOOL_TIER` (`core` / `extended` / `complete`), `GOOGLE_WORKSPACE_MCP_READ_ONLY=true`, `GOOGLE_WORKSPACE_MCP_TOOLS` (space-separated list).

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

## Deploy order

1. Build and push **`mcp-google-workspace`** image (new tag; update `image_reference` in tfvars to match).
2. Add Cloudflare `A` record + NPM proxy host (`forward_port` **18209**) per [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md).
3. Set **`app.tfvars`** `env` with OAuth client ID, secret, and `WORKSPACE_EXTERNAL_URL`.
4. Run Terraform app pipeline for **`mcp-google-workspace`**.
5. Register MCP in Cursor and complete browser consent on first use.

## Related

- [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md)
- [docker-build-github-actions.md](../workflows/docker-build-github-actions.md)
- [workspace-mcp docs](https://workspacemcp.com/docs)
