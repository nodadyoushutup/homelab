# Zot (Swarm)

Single-service OCI registry using the official **`ghcr.io/project-zot/zot`** full image.

## Operator config

**`.config/terraform/components/swarm/zot/`**

| File | Purpose |
|------|---------|
| **`app.tfvars`** | `htpasswd_path`, `placement` |
| **`htpasswd`** | Optional; bcrypt htpasswd line(s). When present at plan time, auth is on |

**`terraform/components/swarm/zot/app/files/zot-config.json.tpl`** — standard Zot config; Terraform adds `http.auth` / `accessControl` only if `fileexists(htpasswd_path)`.

Usernames in **`htpasswd`** must match `registry_auths` for `zot.nodadyoushutup.com` in each consuming slice’s site tfvars (e.g. **`.config/terraform/components/swarm/zot/app.tfvars`** and **`.config/terraform/components/swarm/*/app.tfvars`**). Access control uses **`defaultPolicy`** (any authenticated user).

Create **`htpasswd`** (same host path on planner and `swarm-cp-0`):

```bash
scripts/zot/auth_generate.sh
```

Re-run plan/apply after creating the file so the template picks up auth.

Overlay network **`zot`** and ingress port **`35081`** are hardcoded in `main.tf`.

## Deploy

```bash
terraform/components/swarm/zot/pipeline/app.sh apply
scripts/zot/auth_test.sh
```

## Usage

After apply (and NPM host for HTTPS):

- **UI:** `https://zot.nodadyoushutup.com` (or `http://<manager>:35081`)
- **Login:** `docker login zot.nodadyoushutup.com` (when auth enabled)
- **Push/pull:** `zot.nodadyoushutup.com/<image>:<tag>`

Changing the template or adding/removing **`htpasswd`** rolls the service via config hash (`force_update`).
