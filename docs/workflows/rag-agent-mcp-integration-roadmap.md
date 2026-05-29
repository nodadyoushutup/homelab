# RAG, MCP, and LangGraph agent integration

This document is the **contract** for how homelab agents use **`mcp-rag`**, the
**`homelab`** Chroma corpus collection, and **long-term memory** collections.
The primary runtime is **LangGraph** (`applications/langgraph/`). Cursor and
OpenAI Codex use the same HTTPS MCP endpoint and tools. For the supervisor
delegation loop that these gates plug into, see
[`agent-orchestration.md`](./agent-orchestration.md).

## Design stance

- **LangGraph-first:** Supervisor + specialists load **`mcp-rag`** from each
  agent’s `mcp.json`. Prompts under `applications/langgraph/` (supervisor
  `system_prompt.md`, framework `system_prompts/`) and **`docs/subagents/`**
  overlays define routing and tool discipline.
- **Every agent gets RAG:** The supervisor and every specialist (`code`,
  `github`, `jira`, `tech_lead`) include **`mcp-rag`** so any agent can run
  `rag_search` and memory tools without inheriting filesystem MCP access from
  another layer.
- **Thin MCP, fat engine:** `mcp-rag` forwards to **`rag-engine`** so query
  embeddings match ingest. Clients do not open Chroma with ad hoc settings.

## Corpus collection name

- Default Chroma collection for repository chunks: **`homelab`**
  (`RAG_CHROMA_COLLECTION`, default in `applications/rag-engine`).
- **Migrating an existing index:** after backfill completes, either point
  `RAG_CHROMA_COLLECTION` at the new collection and re-ingest into `homelab`, or
  use Chroma’s collection management to rename/copy data, then align env vars
  across `rag-engine` and backfill scripts. Mixed names across
  environments are fine as long as each stack is internally consistent.

## `mcp-rag` tools

| Tool | Role |
| --- | --- |
| `rag_search` | Semantic search over the indexed corpus via `rag-engine`. Optional `path_prefix` scopes to a repo directory; optional `k` overrides hit count up to `RAG_QUERY_K_MAX` (default breadth remains `RAG_TOP_K`). |
| `memory_recall` | Retrieve prior episodic/declarative memories (hints only). |
| `memory_save` | Persist memory through **strict gates** (see below). |
| `memory_forget` | Delete by id when the user asks to forget. |

## Long-term memory (agent responsibility)

All agents that expose **`mcp-rag`** share responsibility for **memory
management**:

- After a **failure is observed and resolved** on the current task, consider
  **`memory_save`** with `kind="episodic"` and `source="failure_resolution"`
  (required fields per tool schema).
- When the user explicitly asks to remember something (**“remember”**, **“save
  this”**, **“note for later”**, or equivalent), use **`memory_save`** with
  `kind="declarative"` and `source="user_assertion"`.
- Do **not** use `memory_save` to cache `rag_search` output, chat summaries, or
  secrets.
- Use **`memory_recall`** before deep diagnosis of recurring failures or when
  starting a clearly topical task; verify hits against the repo.

## Enforced workflow gates (LangGraph)

Runtime middleware under `applications/langgraph/framework/middleware/` enforces:

1. **Docs RAG before every specialist delegation:** On the supervisor, a `task`
   to **`code`**, **`github`**, **`jira`**, or **`tech_lead`** is rejected until
   **`rag_search`** has completed after the user’s latest `HumanMessage`.
   This first query should target the specialist’s docs overlay under
   **`docs/subagents/<specialist>/`** plus relevant **`docs/workflows/`** guidance.
   Pass the doc anchors into the `task` description.
2. **Code-location RAG before code-impact specialists:** A `task` to **`code`**
   or **`tech_lead`** is rejected until a second **`rag_search`** has completed
   after the user’s latest `HumanMessage`. This second query should identify
   likely code, configuration, manifests, scripts, or workflow files. Pass those
   locations into the `task` description.
3. **Read/search before mutating:** On the **Code** specialist, **`write_file`**,
   **`edit_file`**, and **`execute`** are rejected until at least one
   read/analysis-style tool has produced a tool result in that subagent thread
   (e.g. `read_file`, `grep`, `glob`, `find_code`, `list_directory`).
4. **No `general-purpose` subagent:** Delegating to Deep Agents’ default
   **`general-purpose`** subagent is rejected; use **`code`**, **`github`**, **`jira`**, or
   **`tech_lead`**.

**Break-glass:** set **`HOMELAB_DISABLE_WORKFLOW_GATES=1`** on the agent process
(emergency only).

## Indexed metadata keys (Chroma `where` filters)

Chunks carry metadata for filtering in `rag_search(where=...)`. Common keys:

| Key | Meaning |
| --- | --- |
| `path` | Repo-relative path for the chunk’s source file. |
| `chunk_strategy` | Strategy id (`ast_py`, `pdf_hybrid`, `char`, …). |
| `model` | **Embedding model id** used for the vector (not an application domain model). |
| `xml_model` | For Odoo XML, logical model name (e.g. `purchase.order`). |
| `language` | Source language when set by structured chunking. |
| `embedding_provider` | Provider name at embed time. |

Prefer **`xml_model`** (not `model`) when filtering Odoo XML. When changing
embedding provider/model/dimensions, use a **new** collection or full rebuild.

## Related docs

- MCP client wiring: [docs/mcp/mcp-rag.md](../mcp/mcp-rag.md)
- RAG stack overview: [docs/rag/overview.md](../rag/overview.md)
- Embeddings and collections: [docs/rag/embeddings-and-storage.md](../rag/embeddings-and-storage.md)
- LangGraph app: [applications/langgraph/README.md](../../applications/langgraph/README.md)
