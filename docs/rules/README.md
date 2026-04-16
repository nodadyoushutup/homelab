# Rules

This directory is the source-of-truth for steady-state repo rules and
guardrails.

Use these files for what must stay true across tasks. Use
[`docs/workflows/README.md`](./../workflows/README.md) for step-by-step
operator flows.

## File map

- `application-networking.md`: app hostname, DNS, reverse proxy, exposure, and
  validation rules
- `applications.md`: placement rules for deciding whether a new app belongs in
  Swarm or Kubernetes
- `mcp-servers.md`: steady-state rules for the Swarm-hosted MCP server set
- `repo.md`: repo-wide rules, safety constraints, host/runtime assumptions, and
  git hygiene
- `kubernetes.md`: Kubernetes layout, ownership, networking, secrets, and
  operational guardrails
- `terraform.md`: Terraform layout, tfvars/backend rules, Swarm policy, and
  edge/infrastructure guardrails
