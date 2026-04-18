# Workflows

This directory is the source-of-truth for repeatable operator workflows.

Use these files for how work gets done. Use
[`docs/rules/README.md`](./../rules/README.md) for the steady-state rules that
govern those workflows.

## File map

- `argocd.md`: normal GitOps workflow for Argo CD-managed Kubernetes changes
- `application-networking.md`: standard hostname, DNS, proxy, and domain
  validation flow for new or changed app endpoints
- `agents.md`: how to choose the owning agent and any subagents before
  execution
- `container-images.md`: container build, Harbor registry, and GitHub Actions
  publish workflow
- `confluence.md`: standard Confluence discovery and documentation-analysis
  workflow
- `git.md`: default staging, commit, and push workflow for normal repo changes
- `jira.md`: standard Jira discovery and issue-analysis workflow
- `langgraph.md`: standard LangGraph monorepo and Deep Agents implementation
  workflow
- `mcp-servers.md`: operator workflow for Swarm-hosted MCP servers
- `new-application.md`: how to classify a new app and then onboard it through
  the correct platform workflow
- `kubernetes.md`: standard Kubernetes delivery and validation flow
- `kubernetes-kustomize-patterns.md`: multi-instance Kustomize workflow using
  qBittorrent as the reference pattern
- `kubernetes-vault-secrets.md`: Vault plus External Secrets workflow for
  Kubernetes workloads
- `terraform.md`: Terraform stage execution and validation flow
