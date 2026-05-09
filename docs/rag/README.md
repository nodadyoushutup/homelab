# RAG in this repository (reference)

Human-facing **system knowledge** for the semantic index: what it is, what gets ingested, how embeddings and storage work, and how services are run. Use this when onboarding, changing `rag-engine`, or reasoning about retrieval behavior.

**Not in this folder:** prompts, routing policy, or tool-usage rules for the Google ADK RAG sub-agent. Those live next to the agent code:

- `applications/google-adk/agent/sub_agents/rag/instructions.md`
- `applications/google-adk/agent/instructions.md` (orchestrator sections that mention RAG / memory)

**Implementation checklists and phased delivery** stay in `docs/workflows/development/` (roadmaps), not here.

## Contents

| Doc | Purpose |
| --- | --- |
| [overview.md](overview.md) | Components, request paths, and how MCP, worker, and Chroma relate |
| [corpus-and-ingest.md](corpus-and-ingest.md) | Corpus layout (`docs/knowledge/`), allowlists, hooks, what is excluded |
| [embeddings-and-storage.md](embeddings-and-storage.md) | Embedding model, batching, Chroma collections, metadata at a glance |
| [operators-and-clients.md](operators-and-clients.md) | Compose services, env vars, Cursor MCP, ADK container wiring |

## Quick links

- MCP usage (ports, headers, troubleshooting): [docs/mcp/rag.md](../mcp/rag.md)
- Worker package summary: [docs/applications/rag-engine.md](../applications/rag-engine.md)
- Structured chunking checklist: [rag-structured-file-ingest-roadmap.md](../workflows/development/rag-structured-file-ingest-roadmap.md)
- Agent + MCP integration phases: [rag-agent-mcp-integration-roadmap.md](../workflows/development/rag-agent-mcp-integration-roadmap.md)
