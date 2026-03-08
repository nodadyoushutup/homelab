# Vault

Vault runs as a single-node Docker Swarm service with integrated Raft storage and a Terraform app/config split.

## Day-1 operating mode

- Single replica on `swarm-cp-0` (current placement default).
- HTTP only (`http://swarm-cp-0.local:8200`), TLS deferred.
- Vault UI enabled.
- Persistent Raft data volume (`vault-data`) mounted at `/vault/file`.
- App pipeline auto-runs bootstrap.
- Config pipeline auto-runs unseal before Terraform.

## Local artifact paths

- `/mnt/eapp/.tfvars/vault/app.tfvars`
- `/mnt/eapp/.tfvars/vault/config.tfvars`
- `/mnt/eapp/.tfvars/vault/init.json` (bootstrap output)
- `/mnt/eapp/.tfvars/vault/.env` (`VAULT_ADDR`, `VAULT_TOKEN`)

> Temporary policy: generated artifacts currently use permissive `775` permissions by design for this homelab phase. Hardening is tracked as follow-up work.

## Commands

Deploy/refresh app stage (includes automatic bootstrap):

```bash
./terraform/swarm/vault/app/pipeline/app.sh
```

If running from a non-manager control host, set manager target for script-based docker actions:

```bash
VAULT_SWARM_MANAGER_HOST="user@swarm-cp-0" ./terraform/swarm/vault/app/pipeline/app.sh
```

Manual unseal (standalone, non-interactive):

```bash
./scripts/vault_unseal.sh
```

Manual seal (standalone, immediate action):

```bash
./scripts/vault_seal.sh
```

Standard secret updates (Terraform-managed):

```bash
# 1) edit /mnt/eapp/.tfvars/vault/config.tfvars
# 2) run config pipeline
./terraform/swarm/vault/config/pipeline/config.sh
```

Config tfvars grouped secret shape (day-1 example):

```hcl
secrets = {
  k8s = {
    thelounge = {
      username = "admin"
      password = "password"
    }
  }
}
```

## Safety and behavior notes

- Do not mount host `/mnt/eapp/.tfvars` into the Vault container.
- Bootstrap writes init material from host-side command execution (`docker exec ... > /mnt/eapp/.tfvars/vault/init.json`).
- If Vault is initialized but `/mnt/eapp/.tfvars/vault/init.json` is missing, bootstrap fails hard and requires file restoration.
- `/mnt/eapp/.tfvars/vault/config.tfvars` is authoritative for managed secrets; removing an entry removes the corresponding Vault secret on apply.
- This pattern stores secret payloads in Terraform state. Accepted for this homelab pattern, not recommended for stricter production security posture.
- If control-host routing to Vault is restricted, use a local SSH tunnel and set `VAULT_ADDR` (for example `http://127.0.0.1:18200`) before running scripts/pipelines.
