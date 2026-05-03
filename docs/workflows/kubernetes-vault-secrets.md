# Kubernetes Vault Secrets Workflow

This document is the source-of-truth workflow for Kubernetes applications that
store secret values in Vault through Terraform tfvars and consume them through
External Secrets.

Use [docs/workflows/kubernetes.md](./kubernetes.md) for the broader Kubernetes
delivery flow and [docs/rules/kubernetes.md](./../rules/kubernetes.md) for
layout and guardrails.

## What This Workflow Does

The standard repo flow is:

1. define the secret payload in `/mnt/eapp/config/vault/config.tfvars`
2. run `pipelines/terraform/swarm/vault/config.sh`
3. let Terraform write the payload into Vault KV v2 under `secret/<group>/<name>`
4. create a namespace-local Vault token secret in Kubernetes
5. point a `SecretStore` at Vault
6. point an `ExternalSecret` at the Vault path and property names
7. consume the generated Kubernetes `Secret` from the workload

In repo terms, the chain is:

`/mnt/eapp/config/vault/config.tfvars` -> `terraform/swarm/vault/config` ->
Vault KV -> `SecretStore` -> `ExternalSecret` -> Kubernetes `Secret` ->
Deployment/StatefulSet/Job

## Source of Truth

The source of truth for secret values is:

- `/mnt/eapp/config/vault/config.tfvars`

The Terraform stage that writes those values into Vault is:

- `terraform/swarm/vault/config`
- `pipelines/terraform/swarm/vault/config.sh`

Do not treat manual `vault kv put` calls or manual UI edits as the steady-state
workflow for Kubernetes app secrets in this repo.

## Vault Path Contract

The current Terraform contract is defined by
[`terraform/swarm/vault/config/main.tf`](/mnt/eapp/code/homelab/terraform/swarm/vault/config/main.tf:1)
and
[`terraform/swarm/vault/config/variables.tf`](/mnt/eapp/code/homelab/terraform/swarm/vault/config/variables.tf:1).

It builds each Vault secret path as:

- `secret/<group>/<name>`

The default mount is `secret`, and the common Kubernetes group is `k8s`, so the
normal app path shape is:

- `secret/k8s/<app>`

Examples:

- `secret/k8s/prowlarr`
- `secret/k8s/argocd`
- `secret/k8s/qbittorrent_movie_10`

Important constraints enforced by Terraform validation:

- `group` must match `^[a-z0-9_-]+$`
- `name` must match `^[a-z0-9_-]+$`
- `/` is not allowed inside `group` or `name`

That means the supported Terraform-driven path shape is exactly
`<group>/<name>`, not arbitrarily deep nested paths.

Some existing older manifests still reference deeper Vault paths such as
`k8s/qbittorrent/movie-0`. Treat those as legacy repo drift, not the pattern to
copy for new work.

## Tfvars Structure

`config.tfvars` supports two grouped inputs:

- `secrets` for inline string fields
- `secret_files` for fields loaded from files on disk

Terraform merges both inputs into one Vault payload per `<group>/<name>`.

Sanitized example:

```hcl
secrets = {
  k8s = {
    prowlarr = {
      db_main_db  = "prowlarr-main"
      db_log_db   = "prowlarr-log"
      db_username = "prowlarr"
      db_password = "replace-me"
    }

    argocd = {
      discord_webhook_url = "https://discord.com/api/webhooks/replace-me"
    }

    qbittorrent_movie_10 = {
      webui_password_pbkdf2 = "replace-me"
    }
  }
}

secret_files = {
  k8s = {
    privatebin = {
      server_salt = "/mnt/eapp/secrets/privatebin/server_salt"
    }
  }
}
```

Resulting Vault objects from that example:

- `secret/k8s/prowlarr`
- `secret/k8s/argocd`
- `secret/k8s/qbittorrent_movie_10`
- `secret/k8s/privatebin`

## Durable Unseal Automation

This repo's Vault deployment uses manual-unseal keys stored in
`/mnt/eapp/config/vault/init.json`, not cloud auto-unseal.

That means Vault can come back `sealed` after a Docker restart even if the host
did not reboot. When that happens, all Kubernetes `SecretStore` objects that
depend on Vault will fail validation and `ExternalSecret` refreshes will start
returning provider errors.

To keep this from recurring after a Swarm manager boot or Docker daemon
restart, install or refresh the host-side auto-unseal unit on the manager that
runs Vault:

```bash
scripts/vault/install_auto_unseal_service.sh
```

The installed `vault-auto-unseal.service` should be enabled for both:

- normal host boot
- `docker.service` starts/restarts

If the Vault host changes, rerun the installer against the new manager.

## Apply Workflow

After updating `/mnt/eapp/config/vault/config.tfvars`, run:

```bash
pipelines/terraform/swarm/vault/config.sh
```

That stage uses fixed input paths and does not accept override args. It also:

- auto-sources `/mnt/eapp/config/vault/.env`
- requires `VAULT_TOKEN` from that env file
- auto-runs `scripts/vault/unseal.sh`
- fails fast if Vault bootstrap artifacts are missing

If this pipeline does not succeed, stop there. Do not debug Kubernetes manifests
until the Vault write path is confirmed.

## Kubernetes Manifests

The normal manifest set for a Vault-backed app is:

- `namespace.yaml`
- `secretstore.yaml`
- `externalsecret.yaml`
- workload manifests that consume the generated `Secret`

Typical sync-wave order in this repo:

- `10` for `SecretStore`
- `15` for `ExternalSecret`
- `30` for the main app deployment

### 1. Bootstrap the namespace-local reader token

Each namespace needs a Kubernetes secret containing `VAULT_TOKEN` for the
`SecretStore` auth reference.

Standard command:

```bash
source /mnt/eapp/config/vault/.env && \
kubectl -n <namespace> create secret generic <app>-vault-reader \
  --from-literal=VAULT_TOKEN="$VAULT_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
```

Example:

```bash
source /mnt/eapp/config/vault/.env && \
kubectl -n prowlarr create secret generic prowlarr-vault-reader \
  --from-literal=VAULT_TOKEN="$VAULT_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
```

The secret must exist in the same namespace as the `SecretStore`.

### 2. Create the `SecretStore`

Reference pattern from
[`kubernetes/prowlarr/secretstore.yaml`](/mnt/eapp/code/homelab/kubernetes/prowlarr/secretstore.yaml:1):

```yaml
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: prowlarr-vault
  namespace: prowlarr
spec:
  provider:
    vault:
      server: http://192.168.1.120:8200
      path: secret
      version: v2
      auth:
        tokenSecretRef:
          name: prowlarr-vault-reader
          key: VAULT_TOKEN
```

Repo expectations:

- `path` should be `secret`
- `version` should be `v2`
- `tokenSecretRef.name` usually follows `<app>-vault-reader`

### 3. Create the `ExternalSecret`

Reference pattern from
[`kubernetes/prowlarr/externalsecret.yaml`](/mnt/eapp/code/homelab/kubernetes/prowlarr/externalsecret.yaml:1):

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: prowlarr-secrets
  namespace: prowlarr
spec:
  secretStoreRef:
    kind: SecretStore
    name: prowlarr-vault
  target:
    name: prowlarr-secrets
  data:
    - secretKey: POSTGRES_USER
      remoteRef:
        key: k8s/prowlarr
        property: db_username
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: k8s/prowlarr
        property: db_password
```

Mapping rules:

- `remoteRef.key` must be `<group>/<name>` from the tfvars-driven Vault path
- `remoteRef.property` must match the payload field name in Vault exactly
- `secretKey` is the field name that will exist in the generated Kubernetes
  `Secret`

Example translations:

- tfvars `secrets.k8s.prowlarr.db_username` -> Vault `secret/k8s/prowlarr`
  property `db_username` -> Kubernetes Secret key `POSTGRES_USER`
- tfvars `secrets.k8s.argocd.discord_webhook_url` -> Vault `secret/k8s/argocd`
  property `discord_webhook_url` -> Kubernetes Secret key
  `discord-webhook-url`

### 4. Consume the generated Kubernetes `Secret`

The workload should consume the generated secret, not Vault directly.

Reference pattern from
[`kubernetes/prowlarr/deployment.yaml`](/mnt/eapp/code/homelab/kubernetes/prowlarr/deployment.yaml:1):

```yaml
env:
  - name: PROWLARR__POSTGRES__USER
    valueFrom:
      secretKeyRef:
        name: prowlarr-secrets
        key: POSTGRES_USER
  - name: PROWLARR__POSTGRES__PASSWORD
    valueFrom:
      secretKeyRef:
        name: prowlarr-secrets
        key: POSTGRES_PASSWORD
```

## Standard End-to-End Sequence

For a new app or a secret rotation, use this order:

1. update `/mnt/eapp/config/vault/config.tfvars`
2. run `pipelines/terraform/swarm/vault/config.sh`
3. create or refresh the namespace-local `<app>-vault-reader` secret if needed
4. apply `secretstore.yaml`
5. apply `externalsecret.yaml`
6. confirm the generated Kubernetes `Secret` exists
7. apply or restart the workload that consumes the secret

Direct apply examples:

```bash
kubectl apply -f kubernetes/prowlarr/secretstore.yaml
kubectl apply -f kubernetes/prowlarr/externalsecret.yaml
kubectl get secret -n prowlarr prowlarr-secrets
```

## Validation

Validate in this order:

1. Vault write succeeded
2. `SecretStore` is ready
3. `ExternalSecret` is ready
4. generated Kubernetes `Secret` contains expected keys
5. workload consumes the generated secret successfully

Common checks:

```bash
kubectl get secretstore,externalsecret -n <namespace>
kubectl describe externalsecret -n <namespace> <name>
kubectl get secret -n <namespace> <target-secret>
kubectl get secret -n <namespace> <target-secret> -o yaml
```

If you need to verify the Vault-side path directly, the intended path is
`secret/<group>/<name>`.

## Troubleshooting

### `config.sh` fails before Terraform

Check:

- `/mnt/eapp/config/vault/init.json` exists
- `/mnt/eapp/config/vault/.env` exists
- `VAULT_TOKEN` is present in `.env`
- Vault is reachable and unsealed

If Vault is sealed, run:

```bash
scripts/vault/unseal.sh
```

Then rerun:

```bash
pipelines/terraform/swarm/vault/config.sh
```

### `ExternalSecret` is not syncing

Usually one of these is wrong:

- `SecretStore` token secret name or namespace
- `remoteRef.key`
- `remoteRef.property`
- Vault path was never written because tfvars or pipeline apply was wrong

Debug with:

```bash
kubectl describe secretstore -n <namespace> <name>
kubectl describe externalsecret -n <namespace> <name>
```

### Secret path naming is unclear

Use the Terraform contract, not the manifest guess:

- choose a `group`, usually `k8s`
- choose a single `name`
- reference it in Kubernetes as `<group>/<name>`

For multi-instance apps, flatten the instance identity into `name` rather than
adding more path segments.

Recommended pattern:

- `k8s/qbittorrent_movie_10`

Not recommended for new work:

- `k8s/qbittorrent/movie-10`
