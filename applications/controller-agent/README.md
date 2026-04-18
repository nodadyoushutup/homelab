# Controller Agent Image

This directory contains the repo-owned container build for the standalone
LangGraph Agent Server that serves the homelab multi-graph deployment:

- `controller_agent`
- `code_analysis_agent`
- `jira_agent`

The image is intentionally built on top of the official
`langchain/langgraph-api` runtime image, while the graph code continues to live
under [`langgraph/`](../../langgraph).

Harbor publish target:

- `harbor.nodadyoushutup.com/controller-agent/controller-agent:<tag>`
- `harbor.nodadyoushutup.com/controller-agent/controller-agent:latest`

Build context:

- `langgraph/`

Dockerfile path:

- `applications/controller-agent/Dockerfile`
