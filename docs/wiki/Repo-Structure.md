# Repo Structure

```
/
├── docs/
│   ├── wiki/              # Wiki content (Machines, Secrets, Docker Swarm, service runbooks)
│   └── planning/          # Stage-based plans for new work
├── docker/
│   ├── jenkins/           # Jenkins controller/agent image build contexts
│   ├── purge/             # Service-specific purge scripts (Swarm cleanup)
│   ├── minio/             # Docker Compose stack for MinIO backend
│   └── renovate/          # Docker Compose stack for Renovate
├── pipeline/              # Swarm pipeline entrypoints + Jenkins wrappers per service
├── terraform/
│   ├── module/            # Terraform modules (services, healthcheck helpers, Jenkins jobs)
│   └── swarm/             # Stack entrypoints per service/stage
├── AGENTS.md              # Pointer directory to Machines/Secrets/Docker Swarm docs
├── .github/workflows/     # CI for Jenkins images + wiki sync
└── renovate.json          # Dependency automation configuration
```

## Conventions

- Place documentation alongside the code it explains. If a new service needs a runbook, create `docs/wiki/<Service>.md` and link it from the sidebar.
- Add supporting scripts under a service-specific directory (for example, `docker/<service>/` or `docker/purge/<service>.sh`).
- Keep Terraform/pipeline work reproducible; document tfvars/backend expectations in planning docs and wiki pages.
- Keep this file updated as services and directories evolve.
