# Controller Agent Image

This directory contains the repo-owned container build for the homelab
multi-graph LangGraph runtime that serves:

- `controller_agent`
- `code_analysis_agent`
- `jira_agent`

The image intentionally runs `langgraph dev` inside the container so the
homelab can self-host the controller stack without the licensed standalone
Agent Server runtime. The graph code continues to live under
[`langgraph/`](../../langgraph).

Harbor publish target:

- `harbor.nodadyoushutup.com/controller-agent/controller-agent:<tag>`
- `harbor.nodadyoushutup.com/controller-agent/controller-agent:latest`

Build context:

- `langgraph/`

Dockerfile path:

- `applications/controller-agent/Dockerfile`

Runtime characteristics:

- container entrypoint: `langgraph dev --host 0.0.0.0 --port 2024 --no-browser --no-reload`
- default API/docs port inside the container: `2024`
- local state directory: `.langgraph_api/`
