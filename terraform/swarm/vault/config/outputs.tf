output "mount_path" {
  description = "KV v2 mount path"
  value       = vault_mount.kv.path
}

output "secret_paths" {
  description = "Managed secret paths under the KV mount"
  value       = [for k in sort(keys(local.flattened_secrets)) : "${vault_mount.kv.path}/${k}"]
}
