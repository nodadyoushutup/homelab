from __future__ import annotations

from pathlib import Path
from typing import Sequence

from deepagents import CompiledSubAgent, create_deep_agent
from langchain.agents import create_agent
from langchain.tools import tool

from .configuration import (
    load_system_prompt,
    merged_settings,
    resolve_repo_root,
    resolve_skill_roots,
)
from .mcp_support import (
    DEFAULT_REPO_SEARCH_EXCLUDES,
    JIRA_JSON_STRING_FIELDS_BY_TOOL,
    JIRA_OMIT_ARGS_BY_TOOL,
    JIRA_OMIT_FALSE_BOOL_ARGS_BY_TOOL,
    load_mcp_tools,
    wrap_blank_optional_args,
    wrap_filesystem_tools,
)
from .remote_a2a import RemoteAgentDefinition, build_remote_delegate_tool


def create_supervisor_agent(
    app_dir: Path,
    *,
    local_subagents: Sequence[CompiledSubAgent] | None = None,
):
    settings = merged_settings(app_dir)

    @tool
    def describe_homelab_topology() -> str:
        """Describe the specialist topology this supervisor expects."""
        if local_subagents:
            available = ", ".join(spec["name"] for spec in local_subagents)
            return (
                "This supervisor is running in a single deployment with local specialist subagents. "
                f"Available specialists: {available}. "
                "Route code, config, repository, path, and filesystem questions to code_agent."
            )
        return (
            "This supervisor is wired to delegate to two remote agents: "
            "a code agent for repository and implementation analysis, "
            "and a jira agent for Jira-backed issue workflows."
        )

    if local_subagents:
        return create_deep_agent(
            model=settings.get("SUPERVISOR_MODEL", "openai:gpt-5.4"),
            tools=[describe_homelab_topology],
            system_prompt=load_system_prompt(
                app_dir / "system_prompt.md",
                {
                    "specialist_topology": "specialist agents that are co-deployed in this same Agent Server",
                    "code_delegate_instruction": "You must use the `task` tool to delegate every repository, source code, configuration, file path, filesystem, MCP workspace, or implementation question to the `code_agent` specialist before answering.",
                    "jira_delegate_instruction": "You must use the `task` tool to delegate every explicit Jira request, including create-issue requests, to the `jira_agent` specialist before asking your own follow-up question or answering directly.",
                },
            ),
            subagents=list(local_subagents),
        )

    remote_tools = [
        build_remote_delegate_tool(
            RemoteAgentDefinition(
                name="call_code_agent",
                description="Delegate any repository, code, config, path, filesystem, or implementation-analysis task to the remote Code agent.",
                base_url=settings.get("CODE_AGENT_URL"),
                assistant_id=settings.get("CODE_AGENT_ASSISTANT_ID"),
                graph_id=settings.get("CODE_AGENT_GRAPH_ID"),
                api_key=settings.get("CODE_AGENT_API_KEY"),
            )
        ),
        build_remote_delegate_tool(
            RemoteAgentDefinition(
                name="call_jira_agent",
                description="Delegate Jira discovery and issue-management tasks to the remote Jira agent.",
                base_url=settings.get("JIRA_AGENT_URL"),
                assistant_id=settings.get("JIRA_AGENT_ASSISTANT_ID"),
                graph_id=settings.get("JIRA_AGENT_GRAPH_ID"),
                api_key=settings.get("JIRA_AGENT_API_KEY"),
            )
        ),
    ]

    return create_agent(
        model=settings.get("SUPERVISOR_MODEL", "openai:gpt-5.4"),
        tools=[describe_homelab_topology, *remote_tools],
        system_prompt=load_system_prompt(
            app_dir / "system_prompt.md",
            {
                "specialist_topology": "remote specialist agents instead of doing domain-specific work yourself",
                "code_delegate_instruction": "You must use `call_code_agent` for any repository, source code, configuration, file path, filesystem, MCP workspace, or implementation question before answering.",
                "jira_delegate_instruction": "You must use `call_jira_agent` for every explicit Jira request, including create-issue requests, before asking your own follow-up question or answering directly.",
            },
        ),
    )


def create_code_agent(app_dir: Path):
    settings = merged_settings(app_dir)
    repo_root = resolve_repo_root(settings.get("CODE_REPOSITORY_ROOT"))

    @tool
    def describe_code_contract() -> str:
        """Describe what the Code agent is responsible for."""
        return (
            "The Code agent owns source-of-truth repository analysis for code, config, files, paths, filesystem visibility, and implementation behavior. "
            f"It should stay scoped to the repository root `{repo_root}`, trace code paths, identify affected files, summarize behavior, and separate facts from assumptions."
        )

    mcp_tools = wrap_filesystem_tools(load_mcp_tools(app_dir / "mcp.json"), repo_root)

    return create_deep_agent(
        model=settings.get("CODE_MODEL", "openai:gpt-5.4"),
        system_prompt=load_system_prompt(
            app_dir / "system_prompt.md",
            {
                "repo_root": str(repo_root),
                "default_search_excludes": ", ".join(DEFAULT_REPO_SEARCH_EXCLUDES),
            },
        ),
        tools=[describe_code_contract, *mcp_tools],
        skills=resolve_skill_roots(app_dir / "skills"),
    )


def create_jira_agent(app_dir: Path):
    settings = merged_settings(app_dir)
    default_project = settings.get("CREATE_ISSUE_DEFAULT_PROJECT", "HLAB")

    @tool
    def describe_jira_operating_rules() -> str:
        """Summarize how the single-layer Jira agent should handle Jira work."""
        return (
            "The Jira agent is a single-layer specialist that handles Jira discovery, "
            "net-new issue creation, and existing issue updates directly. "
            "It should identify the current workflow stage first, treat each Jira "
            "action as being in service of that stage, ask follow-up questions only "
            "for real stage blockers, and invite the next likely stage when the "
            "current one is complete. "
            "Treat requests to create, open, file, log, raise, submit, add, make, or "
            "write up a Jira issue, ticket, task, story, bug, or epic without an "
            "existing issue key as net-new issue creation. "
            "For new issues, start in `TO DO` by locking a short summary and the "
            "issue type (`Story`, `Bug`, or `Task`) before deeper requirements work. "
            "Treat requests with an existing issue key or explicit change, comment, "
            "assignment, or transition intent as updates to existing work. "
            "For pure status changes, use only the required transition arguments unless "
            "Jira explicitly requires extra fields. "
            "If a status change also needs a note, add it with `jira_add_comment` "
            "instead of the transition comment field. "
            f"Default project: {default_project}. Use that project unless the user "
            "names a different project or live Jira metadata shows that another "
            "project is required."
        )

    jira_tools = [
        describe_jira_operating_rules,
        *wrap_blank_optional_args(
            load_mcp_tools(app_dir / "mcp.json"),
            json_string_fields_by_tool=JIRA_JSON_STRING_FIELDS_BY_TOOL,
            omit_args_by_tool=JIRA_OMIT_ARGS_BY_TOOL,
            omit_false_bool_args_by_tool=JIRA_OMIT_FALSE_BOOL_ARGS_BY_TOOL,
        ),
    ]

    return create_deep_agent(
        model=settings.get("JIRA_MODEL", "openai:gpt-5.4"),
        system_prompt=load_system_prompt(
            app_dir / "system_prompt.md",
            {
                "default_project": default_project,
            },
        ),
        tools=jira_tools,
        skills=resolve_skill_roots(app_dir / "skills"),
    )
