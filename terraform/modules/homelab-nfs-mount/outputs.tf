locals {
  nfs_o = join(",", compact([
    "addr=${var.nfs_server}",
    var.mount_options,
    var.read_only ? "ro" : "rw",
  ]))
}

output "mount" {
  description = "Mount object for mcp-service var.mounts (type volume + NFS driver_opts)."
  value = {
    type      = "volume"
    source    = var.volume_name
    target    = var.target
    read_only = var.read_only
    volume_options = {
      driver_name = "local"
      driver_options = {
        type   = "nfs"
        o      = local.nfs_o
        device = var.device
      }
      no_copy = false
    }
  }
}
