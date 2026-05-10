## mcp-git

`mcp-git` is a repo-local HTTP wrapper around the official `mcp-server-git`
reference server.

It is designed to be:

- nothing more than the upstream git MCP plus a stable HTTP transport
- rooted at `/mnt/eapp/code/homelab`, which is an actual Git repository the
  upstream server can open directly
- writable as UID/GID `1000:1000` so git operations keep working on the
  NFS-backed workspace
- Swarm tasks mount the code export with a Docker **NFS volume** (see
  `terraform/swarm/modules/homelab-nfs-mount` and `var.nfs_code_device`), not a
  host bind through a node-local `/mnt/eapp/code` mount
- deployed through Docker Swarm from `terraform/swarm/mcp-git/app`

The intended endpoint is:

- `https://mcp.git.nodadyoushutup.com/mcp`
