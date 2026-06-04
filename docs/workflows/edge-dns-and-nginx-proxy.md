# Edge DNS (Cloudflare) and Nginx Proxy Manager

When you add a **new externally reachable hostname** for a workload, treat **DNS** and **TLS termination / reverse proxy** as part of the same change as the Swarm service or Kubernetes ingress—not an optional follow-up.

## Retired MCP hostnames (cleanup)

Remove DNS and NPM objects for services that are no longer deployed. Typical retired names:

1. **Standalone code MCPs** (replaced then removed): **`mcp.filesystem.<apex>`**, **`mcp.git.<apex>`**, **`mcp.ast-grep.<apex>`** (or **`mcp.astgrep.<apex>`**), including **`-homelab`** lane variants.
2. **Aggregate mcp-code**: **`mcp.code.<apex>`** (Swarm published port **`18212`** in prior defaults).

**Cloudflare** — edit **`<repo>/.config/terraform/components/remote/cloudflare/config.tfvars`**. Delete **`records`** items whose **`name`** matches retired hostnames only.

**NPM** — edit **`<repo>/.config/terraform/components/swarm/nginx_proxy_manager/config.tfvars`**. Remove **`certificates`**, **`proxy_hosts`**, **`redirections`**, and **`streams`** keys that only served those hostnames (match **`domain_names`** / **`forward_port`**).

**Keep** records and proxy hosts for live MCPs and apps (**`mcp.rag`**, **`mcp.github`**, **`mcp.atlassian`**, etc.).

**Swarm** — run **`scripts/swarm/mcp_code_swarm_cleanup.sh`** on the manager after Terraform destroy so the **`mcp-code`** service and **`mcp-code-mnt-eapp-code`** volume are gone.

**Apply** — run your usual **Cloudflare** then **NPM config** Terraform pipelines (`plan` → `apply`).

## DNS `A` record targets (NPM edge)

All homelab hostnames that terminate TLS on **Nginx Proxy Manager** use the **Swarm NPM edge LAN IP** in Cloudflare `records[].content` — **`192.168.1.120`** (`swarm-cp-0`). That includes **Picsur**, **PrivateBin**, **The Lounge**, MCPs, Grafana, and the rest: NPM holds the certificate and forwards to the real backend (Swarm published port or Kubernetes ingress, typically **`192.168.1.241:80`** for cluster ingress).

Do **not** point DNS at the ISP **WAN** address. ONT reboots change the public IP and break names; LAN + NPM stays stable.

Reachability from outside the LAN is via VPN or your own port-forward setup—not by publishing a changing WAN IP in Cloudflare.

## Expectation (checklist)

1. **Name the public hostname** (for example `app.example.com`) and decide **where traffic lands**:
   - **Swarm published port on the edge host** (typical: HTTP(S) via Nginx Proxy Manager on the Swarm manager, with `forward_host` / `forward_port` pointing at the Swarm ingress IP and published port).
   - **Kubernetes**: `Ingress` `host:` in `kubernetes/<app>/` (often `ingress-nginx` + MetalLB). The Cloudflare `A` record `content` may be the **ingress/LB LAN IP**, not the Swarm edge—match whatever actually serves that ingress in your network.
2. **Cloudflare** (`terraform/components/remote/cloudflare/config`): add or extend a `records` entry with a stable `key`, the full `name`, `content` = **`192.168.1.120`** (NPM edge) unless the app is intentionally LAN-only on another IP, `ttl`, and `proxied`. Live tfvars: **`<repo>/.config/terraform/remote/cloudflare/config.tfvars`** (see `terraform/components/remote/cloudflare/pipeline/config.sh`).
3. **Nginx Proxy Manager** (`terraform/components/swarm/nginx_proxy_manager/config`): for every HTTPS hostname on the edge, add:
   - a **Let's Encrypt certificate** entry under top-level **`certificates`** (map key = certificate name used by proxy hosts), and
   - a **proxy host** entry under top-level **`proxy_hosts`** (map key = stable Terraform id; body includes `forward_host`, `forward_port`, and `certificate` or `certificate_id` aligned with the Swarm **published port** and certificate map key). Live tfvars: **`<repo>/.config/terraform/components/swarm/nginx_proxy_manager/config.tfvars`** (`terraform/components/swarm/nginx_proxy_manager/pipeline/config.sh`).
4. **Apply order**: merge tfvars changes, then run the **Cloudflare** pipeline and the **NPM config** pipeline (order is flexible when only adding records/hosts; keep state backends and credentials as you do today). NPM config uses **`-parallelism=1`** to reduce API races.
5. **Kubernetes apps** (The Lounge, Picsur, PrivateBin, qBittorrent, …): keep **`Ingress`** `host:` in `kubernetes/<app>/`; add **Cloudflare** `A` → **`192.168.1.120`** and an **NPM proxy host** with `forward_host` / `forward_port` pointing at ingress (**`192.168.1.241:80`** in this cluster).

## Recovery after WAN / power outages

NPM runs on Swarm **`swarm-cp-0`** (`192.168.1.120`). After internet or router
reboots, overlay tasks can fail with **stale VXLAN interfaces** and NPM never
comes back until Docker is fixed. Automated recovery is installed by
**`scripts/install/swarm_pi_clock_bootstrap.sh`** on every Swarm Pi:
**`docker-swarm-overlay-recovery.timer`** (every 2 minutes) and boot-time
**`docker-swarm-boot-recovery.service`**. See
[swarm-rpi-network.md](swarm-rpi-network.md) (NPM / edge URLs section).

## Repo references

| Piece | Terraform module | Jenkins / shell entry |
| --- | --- | --- |
| Cloudflare `A` records | `terraform/components/remote/cloudflare/config` | `terraform/components/remote/cloudflare/pipeline/config.sh`, `config.jenkins` |
| NPM certificates + proxy hosts | `terraform/components/swarm/nginx_proxy_manager/config` | `terraform/components/swarm/nginx_proxy_manager/pipeline/config.sh`, `config.jenkins` |
| NPM stack (service + DB) | `terraform/components/swarm/nginx_proxy_manager/{app,database}` | `app.sh`, `database.sh` |

## NPM advanced nginx and default 404

Checked-in under **`terraform/components/swarm/nginx_proxy_manager/config/files/`**: **`advanced.conf`** (3600s proxy timeouts + unlimited upload for all proxy/redirection hosts) and **`404.html`** (NPM default site).

## Wildcard DNS

A zone wildcard (for example `*.example.com` → edge IP) can make new hostnames resolve without a new Cloudflare row. **Explicit records** are still recommended for anything you document, automate certificates for, or want isolated from wildcard changes—see the RAG note in [operators-and-clients.md](../rag/operators-and-clients.md).

## Docker Compose dev (`docker/docker-compose.yml`)

The **`homelab-dev`** stack publishes **LangGraph**, **LangChain Agent Chat**, **`rag-engine-dev`**, and **`mcp-rag-dev`** on host ports **2124**, **3000**, **9015**, and **9016**. When those services should be reachable under **HTTPS on the LAN** (or VPN), use a **`dev.`** first label on the existing prod-style hostname. Keep **`A` records on `192.168.1.120`** (NPM edge):

| Service | Public hostname (example zone) | Host port |
| --- | --- | --- |
| LangGraph API | `dev.langgraph.<apex>` (and `dev.langraph.<apex>` if you keep the prod typo alias) | 2124 |
| Agent Chat | `dev.langchain-agent-chat.<apex>` | 3000 |
| RAG engine | `dev.rag-engine.<apex>` | 9015 |
| MCP RAG | `dev.mcp.rag.<apex>` | 9016 |

Terraform: add matching **`A`** records in **`terraform/components/remote/cloudflare/config`** and **proxy hosts** (plus a Let's Encrypt certificate) in **`terraform/components/swarm/nginx_proxy_manager/config`**, with **`forward_host` / `forward_port`** pointing at the **machine where `docker compose` is actually running** (often the same Swarm edge IP if that host runs both; adjust if your dev workstation differs). For the browser chat build arg, set **`LANGCHAIN_AGENT_CHAT_PUBLIC_API_URL`** to the HTTPS Agent Chat URL when you stop using `localhost`.

**Postgres** in that Compose file has no published port and does not need a public name.

## Related

- [docker-build-github-actions.md](docker-build-github-actions.md) (image publish + rollout; add edge DNS/NPM when the app gains a new public URL)
- [operators-and-clients.md](../rag/operators-and-clients.md) (RAG-specific DNS/NPM example)
