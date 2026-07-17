# Docker Dev Stack

This directory contains host-local Docker Compose workflows for development.

## RAG local-dev pair

File: [`docker-compose.rag.yml`](docker-compose.rag.yml)

Services:

- `rag-engine-dev` — bind-mounted `applications/rag-engine` source
- `mcp-rag-dev` — bind-mounted `applications/mcp-rag` source; proxies to `rag-engine-dev`

Chroma stays on Swarm. Compose sets `RAG_CHROMA_HOSTNAME` to `192.168.1.120:8000` by default; override with `HOMELAB_DEV_CHROMA_HOSTNAME` in the shell when invoking Compose if your LAN differs.

Local image tags:

- `homelab/rag-engine:latest`
- `homelab/mcp-rag:latest`

### Usage

From the repo root:

```bash
docker compose -f docker/docker-compose.rag.yml up -d --build
```

Default endpoints:

- rag-engine: `http://localhost:9015`
- mcp-rag: `http://localhost:9016`

Secrets live in [`../.config/docker/*.env`](../.config/docker/README.md) (`shared.env`, `rag.env`, `mcp.env`).

Restart the affected service after source or environment changes; rebuild when Dockerfile or dependency layers change.

## Other compose files

- [`docker-compose.yaml`](docker-compose.yaml) — qbittorrent-exporter local stack
- [`docker-compose.minio.yaml`](docker-compose.minio.yaml) — MinIO helper stack
