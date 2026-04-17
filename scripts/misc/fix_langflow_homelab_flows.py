#!/usr/bin/env python3
"""Patch the live Homelab Langflow flows to use current delegation behavior.

This script updates the known Homelab flows stored in Langflow's PostgreSQL
database. It keeps the parent prompt aligned with the repo's current agent
docs, preserves thin delegation for analysis subagents, reduces retained chat
history, and exports JSON snapshots into `langflow/flows/`.

The script talks to Postgres through `kubectl exec` because the current
homelab Langflow deployment keeps live flows in-cluster rather than loading
repo-managed flow files on startup.
"""

from __future__ import annotations

import argparse
import copy
import json
import subprocess
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT_DIR = REPO_ROOT / "langflow" / "flows"

POSTGRES_EXEC = [
    "kubectl",
    "exec",
    "-i",
    "-n",
    "langflow",
    "deploy/langflow-postgres",
    "--",
    "sh",
    "-lc",
    'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -P pager=off -t -A',
]

FLOWS = [
    {
        "flow_id": "9355afe3-0876-49e8-90a1-867182b43e15",
        "folder_id": "3aed29ec-2af2-4930-aee9-11af924af387",
        "snapshot": "homelab-user.json",
    },
    {
        "flow_id": "77744064-b16c-40b1-a99c-3a5474b22ef2",
        "folder_id": "93e4cb02-f91b-4d30-8c34-a47ad5d8d6e5",
        "snapshot": "homelab-admin.json",
    },
]

CANONICAL_SOURCE_FLOW_ID = FLOWS[0]["flow_id"]

PARENT_PROMPT = """You are the Homelab supervisor agent.

Choose between direct tool execution and delegated subagents deliberately.
Use Code Analysis for repo and code analysis.
Use Jira for Jira discovery, project lookup, workflow analysis, and Jira issue
operations such as create, edit, comment, and transition actions.
Use Confluence for Confluence discovery and operations such as page lookup,
creation, editing, comments, and related content management.
Use Kubernetes for manifest, workload, and Argo CD delivery analysis.
Use Terraform for stage, module, variable, and resource analysis.

For delegated analysis, send a thin request envelope. Never forward full chat
history, raw tool output, or large file lists.

Respond to the user in normal markdown prose. Do not return raw JSON or print
internal coordination fields such as `status`, `user_response`, or
`key_findings` unless the caller explicitly asks for structured output.

When you call an analysis subagent, pass only:
- objective
- scope
- context (at most 5 short bullets)
- constraints
- expected_output

If the user explicitly asks for Jira work, route that task through the Jira
subagent so one Jira-specialized capability owns both Jira discovery and Jira
mutations.
If the user explicitly asks for Confluence work, route that task through the
Confluence subagent so one Confluence-specialized capability owns both
Confluence discovery and Confluence mutations.
For bounded live actions outside Jira and Confluence through configured
external tools, prefer the direct tool path when the needed inputs are already
available.
Do not claim that access or permissions are missing unless a real tool call
fails that way or repo docs already prove the limitation.

If you already have large intermediate results, compress them into a few facts
before delegating. Narrow broad requests before delegation instead of asking the
subagent to scan the entire repo.

After the subagent responds, synthesize the final answer for the user. If the
subagent fails with a size or rate-limit error, retry once with a smaller
objective and tighter scope rather than repeating the same request.
"""

PARENT_DESCRIPTION = (
    "Homelab supervisor with repo, Jira, Confluence, Kubernetes, and Terraform "
    "delegated analysis capabilities."
)

CODE_ANALYSIS_PROMPT = """You are the Code Analysis subagent for the Homelab flow.

Expect a compact delegation envelope, not full chat history.
The repository root is `/mnt/eapp/code/homelab`. Do not use `/` or `.` as the
search root.

Follow these rules:
- Treat repo_scope as a hard boundary.
- Prefer targeted reads over broad searches.
- Never paste raw tool output or large file lists into your answer.
- Summarize search results into short facts and concrete paths.
- Use search_files only with a narrow path or pattern.
- Start from `/mnt/eapp/code/homelab` and then narrow into the relevant
  subdirectory.
- Prefer read_text_file with head/tail and read_multiple_files on specific
  paths.
- Use at most 6 tool calls unless a failure forces one retry.
- Stop exploring once you have enough evidence.
- Return normal markdown prose or short bullets, not JSON. Tool-call traces may
  be visible to the user, so keep the output readable on its own.

Return concise analysis in this exact shape:
Summary:
- ...

Affected files:
- ...

Assumptions:
- ...

Risks:
- ...

Recommended next actions:
- ...
"""

CODE_ANALYSIS_DESCRIPTION = (
    "Repo-backed code analysis. Input must be a compact delegation envelope "
    "with objective, repo_scope, constraints, and expected_output. Do not pass "
    "full chat history or raw tool dumps."
)

CODE_ANALYSIS_TOOL_DESCRIPTION = (
    "Use for bounded repo analysis. Input should be a compact delegation "
    "envelope, not raw history or tool output."
)

JIRA_PROMPT = """You are the Jira subagent for the Homelab flow.

Handle Jira work end to end: issue discovery, project and workflow lookup, and
live Jira operations such as creating issues, updating fields, adding comments,
and transitioning issues when the request is actionable.

Follow these rules:
- Treat the delegated Jira scope as a hard boundary.
- Prefer direct Jira reads when the issue or project is already known.
- If a Jira mutation is requested and the required inputs are available, perform
  it instead of only describing what you would do.
- If required Jira fields are missing, inspect Jira first for issue metadata,
  project context, transitions, or field options before asking a focused
  follow-up question.
- Separate confirmed facts from assumptions and risks.
- Return normal markdown prose or short bullets, not JSON.

Return concise Jira results in this exact shape:
Summary:
- ...

Affected Jira scope:
- ...

Actions taken:
- ...

Assumptions:
- ...

Risks:
- ...

Recommended next actions:
- ...
"""

JIRA_DESCRIPTION = (
    "Jira discovery and operations. Use for issue lookup plus live Jira "
    "actions such as create, edit, comment, and transition work."
)

JIRA_TOOL_DESCRIPTION = (
    "Use for Jira work end to end. Input should be a compact Jira task "
    "envelope covering analysis or a bounded Jira action."
)

CONFLUENCE_PROMPT = """You are the Confluence subagent for the Homelab flow.

Handle Confluence work end to end: page and space discovery, document lookup,
and live Confluence operations such as creating pages, updating page content,
and adding comments when the request is actionable.

Follow these rules:
- Treat the delegated Confluence scope as a hard boundary.
- Prefer direct Confluence reads when the page, content id, or space is already known.
- If a Confluence mutation is requested and the required inputs are available,
  perform it instead of only describing what you would do.
- If required Confluence inputs are missing, inspect Confluence first for page
  metadata, related pages, space context, or valid targets before asking a
  focused follow-up question.
- Separate confirmed facts from assumptions and risks.
- Return normal markdown prose or short bullets, not JSON.

Return concise Confluence results in this exact shape:
Summary:
- ...

Affected Confluence scope:
- ...

Actions taken:
- ...

Assumptions:
- ...

Risks:
- ...

Recommended next actions:
- ...
"""

CONFLUENCE_DESCRIPTION = (
    "Confluence discovery and operations. Use for page and space lookup plus "
    "live Confluence actions such as create, edit, comment, and content "
    "management work."
)

CONFLUENCE_TOOL_DESCRIPTION = (
    "Use for Confluence work end to end. Input should be a compact Confluence "
    "task envelope covering analysis or a bounded Confluence action."
)

ALLOWED_MCP_TOOLS = {
    "mcp_filesystem_homelab": {
        "read_text_file": "Read one text file.",
        "read_multiple_files": "Read several specific files.",
        "list_directory": "List a directory.",
        "directory_tree": "Show a directory tree.",
        "search_files": "Search files in a scoped path.",
        "get_file_info": "Get file metadata.",
    },
    "mcp_ast_grep": {
        "server_info": "Show ast-grep capabilities.",
        "find_code": "Find code by pattern.",
        "find_code_by_rule": "Find code by ast-grep rule.",
    },
}

DISABLED_SERVERS = {
    "mcp_git_homelab",
    "mcp_redis",
    "mcp_agent_protocol",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply-live",
        action="store_true",
        help="Update the live Langflow flow rows in PostgreSQL.",
    )
    parser.add_argument(
        "--write-snapshots",
        action="store_true",
        help="Write patched flow JSON snapshots into langflow/flows/.",
    )
    return parser.parse_args()


def run_psql(sql: str) -> str:
    return subprocess.check_output(POSTGRES_EXEC, input=sql, text=True)


def load_flow(flow_id: str) -> dict[str, Any]:
    sql = f"select data::text from flow where id = '{flow_id}';\n"
    raw = run_psql(sql).strip()
    if not raw:
        raise RuntimeError(f"Flow {flow_id} was not found")
    return json.loads(raw)


def update_flow(flow_id: str, flow_data: dict[str, Any]) -> None:
    payload = json.dumps(flow_data).replace("'", "''")
    sql = (
        "update flow "
        f"set data = '{payload}'::json, updated_at = now() "
        f"where id = '{flow_id}';\n"
    )
    run_psql(sql)


def compact_tools_metadata(
    tools_metadata: list[dict[str, Any]], server_name: str
) -> list[dict[str, Any]]:
    allowed = ALLOWED_MCP_TOOLS[server_name]
    compacted: list[dict[str, Any]] = []
    for item in tools_metadata:
        name = item.get("name")
        if name not in allowed:
            item["status"] = False
            continue
        item["status"] = True
        item["description"] = allowed[name]
        item["display_description"] = allowed[name]
        item["readonly"] = True
        compacted.append(item)
    return compacted


def patch_agent_node(node: dict[str, Any]) -> None:
    template = node["data"]["node"]["template"]
    node_type = node["data"].get("type")
    display_name = node["data"]["node"].get("display_name")

    if display_name in {"Agent", "Homelab Agent"}:
        template["system_prompt"]["value"] = PARENT_PROMPT
        template["agent_description"]["value"] = PARENT_DESCRIPTION
        template["n_messages"]["value"] = 12
        template["max_iterations"]["value"] = 8
        template["max_tokens"]["value"] = 4000
        template["add_current_date_tool"]["value"] = False
        if display_name == "Agent":
            node["data"]["node"]["display_name"] = "Homelab Agent"
        return

    if node_type == "CodeAnalysisAgent":
        template["system_prompt"]["value"] = CODE_ANALYSIS_PROMPT
        template["agent_description"]["value"] = CODE_ANALYSIS_DESCRIPTION
        template["n_messages"]["value"] = 6
        template["max_iterations"]["value"] = 6
        template["max_tokens"]["value"] = 2500
        template["add_current_date_tool"]["value"] = False
        metadata = template.get("tools_metadata", {}).get("value", [])
        if metadata:
            metadata[0]["description"] = CODE_ANALYSIS_TOOL_DESCRIPTION
            metadata[0]["display_description"] = CODE_ANALYSIS_TOOL_DESCRIPTION
        return

    if node_type == "JiraAgent":
        template["system_prompt"]["value"] = JIRA_PROMPT
        template["agent_description"]["value"] = JIRA_DESCRIPTION
        template["n_messages"]["value"] = 6
        template["max_iterations"]["value"] = 6
        template["max_tokens"]["value"] = 2500
        template["add_current_date_tool"]["value"] = False
        metadata = template.get("tools_metadata", {}).get("value", [])
        if metadata:
            metadata[0]["description"] = JIRA_TOOL_DESCRIPTION
            metadata[0]["display_description"] = JIRA_TOOL_DESCRIPTION
        return

    if node_type == "ConfluenceAgent":
        template["system_prompt"]["value"] = CONFLUENCE_PROMPT
        template["agent_description"]["value"] = CONFLUENCE_DESCRIPTION
        template["n_messages"]["value"] = 6
        template["max_iterations"]["value"] = 6
        template["max_tokens"]["value"] = 2500
        template["add_current_date_tool"]["value"] = False
        metadata = template.get("tools_metadata", {}).get("value", [])
        if metadata:
            metadata[0]["description"] = CONFLUENCE_TOOL_DESCRIPTION
            metadata[0]["display_description"] = CONFLUENCE_TOOL_DESCRIPTION


def patch_model_node(node: dict[str, Any]) -> None:
    template = node["data"]["node"]["template"]
    if "max_tokens" in template:
        template["max_tokens"]["value"] = 4000


def patch_mcp_node(node: dict[str, Any]) -> bool:
    template = node["data"]["node"]["template"]
    server_info = template["mcp_server"]["value"]
    server_name = server_info["name"]
    if server_name in DISABLED_SERVERS:
        return False
    if server_name not in ALLOWED_MCP_TOOLS:
        return True
    template["use_cache"]["value"] = True
    template["tools_metadata"]["value"] = compact_tools_metadata(
        template["tools_metadata"]["value"],
        server_name,
    )
    return True


def patch_flow(
    flow_data: dict[str, Any],
    *,
    flow_id: str,
    folder_id: str,
) -> dict[str, Any]:
    kept_nodes: list[dict[str, Any]] = []
    removed_node_ids: set[str] = set()

    for node in flow_data["nodes"]:
        node_type = node["data"].get("type")
        display_name = node["data"]["node"].get("display_name")
        if node_type == "LanguageModelComponent":
            patch_model_node(node)
        elif node_type in {"Agent", "CodeAnalysisAgent", "JiraAgent", "ConfluenceAgent"}:
            patch_agent_node(node)
        elif node_type == "MCP":
            keep = patch_mcp_node(node)
            if not keep:
                removed_node_ids.add(node["id"])
                continue

        template = node["data"]["node"].get("template", {})
        if "_frontend_node_flow_id" in template:
            template["_frontend_node_flow_id"]["value"] = flow_id
        if "_frontend_node_folder_id" in template:
            template["_frontend_node_folder_id"]["value"] = folder_id
        kept_nodes.append(node)

    flow_data["nodes"] = kept_nodes
    flow_data["edges"] = [
        edge
        for edge in flow_data["edges"]
        if edge["source"] not in removed_node_ids and edge["target"] not in removed_node_ids
    ]
    return flow_data


def main() -> int:
    args = parse_args()
    SNAPS = []
    canonical = patch_flow(
        load_flow(CANONICAL_SOURCE_FLOW_ID),
        flow_id=CANONICAL_SOURCE_FLOW_ID,
        folder_id=FLOWS[0]["folder_id"],
    )
    for flow in FLOWS:
        patched = patch_flow(
            copy.deepcopy(canonical),
            flow_id=flow["flow_id"],
            folder_id=flow["folder_id"],
        )
        if args.apply_live:
            update_flow(flow["flow_id"], patched)
        if args.write_snapshots:
            snapshot_path = SNAPSHOT_DIR / flow["snapshot"]
            snapshot_path.parent.mkdir(parents=True, exist_ok=True)
            snapshot_path.write_text(json.dumps(patched, indent=2) + "\n", encoding="utf-8")
            SNAPS.append(snapshot_path)

    mode = []
    if args.apply_live:
        mode.append("applied live updates")
    if args.write_snapshots:
        mode.append("wrote snapshots")
    print(", ".join(mode) or "no changes requested")
    for path in SNAPS:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
