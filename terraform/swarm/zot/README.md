# Zot (Swarm)

Single-service OCI registry using the official **`ghcr.io/project-zot/zot`** full image
(UI, search, mgmt enabled in config).

## Operator config

Live tfvars: **`.config/terraform/swarm/zot/app.tfvars`**

Typical values:

- `published_port` — Swarm ingress (default `35081`; Harbor uses `35080`)
- `enable_auth` + `htpasswd_file_path` — optional push auth (`htpasswd -nB user > file`)
- `placement` — usually `swarm-cp-0` alongside Harbor until cutover

## Deploy

```bash
pipelines/terraform/swarm/zot/app.sh
```

## Usage

After apply (and optional NPM host for HTTPS):

- **UI:** `http://<manager>:35081` (or your public hostname)
- **Push/pull:** `docker push <host>:35081/homelab/myapp:tag`
- **Terraform images:** `image = "zot.example.com/homelab/myapp:1.0.0"` (via NPM hostname)

Harbor remains the current canonical registry until you repoint GHA/Terraform.

## Auth

With `enable_auth = false`, the registry accepts anonymous push/pull (fine on a trusted
network only). For production-style use, set `enable_auth = true` and create an htpasswd
file on the Swarm node at `htpasswd_file_path`.
