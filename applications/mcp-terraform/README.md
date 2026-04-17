# MCP Terraform

Thin container wrapper around HashiCorp's official `terraform-mcp-server`
binary.

Why this exists:

- keeps the runtime rooted in the official HashiCorp release
- adds a minimal userland so Swarm can run an HTTP healthcheck against
  `/health`
- preserves the repo's standard remote HTTP MCP deployment pattern without
  introducing a separate proxy layer
