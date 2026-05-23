# RAG in this repository (reference)

Human-facing **system knowledge** for the semantic index: what it is, what gets ingested, how embeddings and storage work, and how services are run. Use this when onboarding, changing `rag-engine`, or reasoning about retrieval behavior.

**Prompts, routing, memory gates, and tool-usage rules** for homelab agents live with the LangGraph runtime and agent contracts:

- `applications/langgraph/agent/system_prompt.md` (supervisor / `agent` graph) and `applications/langgraph/framework/agents/system_prompts/`
- `docs/subagents/*/*.md` (per-specialist deployment overlays)
- [rag-agent-mcp-integration-roadmap.md](../workflows/rag-agent-mcp-integration-roadmap.md)

**Implementation checklists** for structured ingest (when present) live alongside other workflows under `docs/workflows/`.

## Contents

| Doc | Purpose |
| --- | --- |
| [overview.md](overview.md) | Components, request paths, and how MCP, engine, and Chroma relate |
| [corpus-and-ingest.md](corpus-and-ingest.md) | Corpus layout (`docs/knowledge/`), allowlists, what is excluded |
| [embeddings-and-storage.md](embeddings-and-storage.md) | Embedding model, batching, Chroma collections, metadata at a glance |
| [operators-and-clients.md](operators-and-clients.md) | Swarm (Terraform), Docker dev `rag-engine-dev`/`mcp-rag-dev` + LangGraph `HOMELAB_MCP_RAG_URL`, env vars, Cursor MCP |

## Quick links

- MCP usage (ports, headers, troubleshooting): [docs/mcp/mcp-rag.md](../mcp/mcp-rag.md)
- Engine package summary: [docs/applications/rag-engine.md](../applications/rag-engine.md)
- Structured chunking checklist: [rag-structured-file-ingest-roadmap.md](../workflows/rag-structured-file-ingest-roadmap.md) (add under `docs/workflows/` when authored)
- Agent + MCP integration: [rag-agent-mcp-integration-roadmap.md](../workflows/rag-agent-mcp-integration-roadmap.md)
