# Edge DNS (Cloudflare) and Nginx Proxy Manager

When you add a **new externally reachable hostname** for a workload, treat **DNS** and **TLS termination / reverse proxy** as part of the same change as the Swarm service or Kubernetes ingress—not an optional follow-up.

## Public WAN vs LAN `A` record targets

Only these hostnames use the **public WAN** address in Cloudflare `records[].content` (so the name resolves to something reachable from the open internet, subject to firewall/port-forward rules):

- **Picsur**
- **PrivateBin**
- **The Lounge**

Every other name—including apex, `www`, wildcard, MCP, LangGraph, dev compose names, and internal stacks—must use a **private LAN IP** (for example `192.168.1.120` for the Swarm/NPM edge, or the correct K8s LB / service IP). That way global DNS does not advertise a routable target for those apps. Router or FortiGate policies should align so only the three public apps are forwarded from WAN.

## Expectation (checklist)

1. **Name the public hostname** (for example `app.example.com`) and decide **where traffic lands**:
   - **Swarm published port on the edge host** (typical: HTTP(S) via Nginx Proxy Manager on the Swarm manager, with `forward_host` / `forward_port` pointing at the Swarm ingress IP and published port).
   - **Kubernetes**: `Ingress` `host:` in `kubernetes/<app>/` (often `ingress-nginx` + MetalLB). The Cloudflare `A` record `content` may be the **ingress/LB LAN IP**, not the Swarm edge—match whatever actually serves that ingress in your network.
2. **Cloudflare** (`terraform/remote/cloudflare/config`): add or extend a `records` entry with a stable `key`, the full `name`, `content` (target IP), `ttl`, and `proxied`. Live tfvars usually live at **`/mnt/eapp/config/cloudflare/config.tfvars`** (see `pipelines/terraform/remote/cloudflare/config.sh`).
3. **Nginx Proxy Manager** (`terraform/swarm/nginx_proxy_manager/config`): when the app is fronted **through NPM on the Swarm edge** (not through cluster ingress alone), add:
   - a **Let’s Encrypt certificate** spec under `config.certificates` for the hostname (or SAN list), and
   - a **proxy host** under `config.proxy_hosts` with `forward_host`, `forward_port`, and `certificate` (or `certificate_id`) aligned with the Swarm **published port** and certificate name. Live tfvars: **`/mnt/eapp/config/nginx-proxy-manager/config.tfvars`** (`pipelines/terraform/swarm/nginx_proxy_manager/config.sh`).
4. **Apply order**: merge tfvars changes, then run the **Cloudflare** pipeline and the **NPM config** pipeline (order is flexible when only adding records/hosts; keep state backends and credentials as you do today). NPM config uses **`-parallelism=1`** to reduce API races.
5. **Kubernetes-only apps**: you still need **Cloudflare** (or other DNS) consistency with the **ingress host** and the correct **target IP**. You do **not** add NPM proxy hosts unless you intentionally terminate TLS or proxy through NPM for that hostname.

## Repo references

| Piece | Terraform module | Jenkins / shell entry |
| --- | --- | --- |
| Cloudflare `A` records | `terraform/remote/cloudflare/config` | `pipelines/terraform/remote/cloudflare/config.sh`, `config.jenkins` |
| NPM certificates + proxy hosts | `terraform/swarm/nginx_proxy_manager/config` | `pipelines/terraform/swarm/nginx_proxy_manager/config.sh`, `config.jenkins` |
| NPM stack (service + DB) | `terraform/swarm/nginx_proxy_manager/{app,database}` | `app.sh`, `database.sh` |

## In-repo tfvars shapes

Copy from the checked-in examples (replace placeholders; keep secrets out of git):

- `terraform/remote/cloudflare/config/config.tfvars.example`
- `terraform/swarm/nginx_proxy_manager/config/config.tfvars.example`

## Wildcard DNS

A zone wildcard (for example `*.example.com` → edge IP) can make new hostnames resolve without a new Cloudflare row. **Explicit records** are still recommended for anything you document, automate certificates for, or want isolated from wildcard changes—see the RAG note in [operators-and-clients.md](../rag/operators-and-clients.md).

## Docker Compose dev (`docker/docker-compose.yml`)

The **`homelab-dev`** stack publishes **LangGraph**, **LangChain Agent Chat**, **`rag-engine-dev`**, and **`mcp-rag-dev`** on host ports **2124**, **3000**, **9015**, and **9016**. When those services should be reachable under **HTTPS on the LAN** (or VPN), use a **`dev.`** first label on the existing prod-style hostname. Keep **`A` records on a private IP** per the policy above—not the WAN address:

| Service | Public hostname (example zone) | Host port |
| --- | --- | --- |
| LangGraph API | `dev.langgraph.<apex>` (and `dev.langraph.<apex>` if you keep the prod typo alias) | 2124 |
| Agent Chat | `dev.langchain-agent-chat.<apex>` | 3000 |
| RAG engine | `dev.rag-engine.<apex>` | 9015 |
| MCP RAG | `dev.mcp.rag.<apex>` | 9016 |

Terraform: add matching **`A`** records in **`terraform/remote/cloudflare/config`** and **proxy hosts** (plus a Let’s Encrypt certificate) in **`terraform/swarm/nginx_proxy_manager/config`**, with **`forward_host` / `forward_port`** pointing at the **machine where `docker compose` is actually running** (often the same Swarm edge IP if that host runs both; adjust if your dev workstation differs). For the browser chat build arg, set **`LANGCHAIN_AGENT_CHAT_PUBLIC_API_URL`** to the HTTPS Agent Chat URL when you stop using `localhost`.

**Postgres** in that Compose file has no published port and does not need a public name.

## Related

- [docker-build-github-actions.md](docker-build-github-actions.md) (image publish + rollout; add edge DNS/NPM when the app gains a new public URL)
- [operators-and-clients.md](../rag/operators-and-clients.md) (RAG-specific DNS/NPM example)
