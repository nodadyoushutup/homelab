from __future__ import annotations

from pathlib import Path
from typing import Sequence

from deepagents import CompiledSubAgent, create_deep_agent
from langchain.agents import create_agent
from langchain.tools import tool

from .configuration import (
    load_env_file,
    load_system_prompt,
    merged_settings,
    resolve_repo_root,
    resolve_skill_roots,
)
from .mcp_support import DEFAULT_REPO_SEARCH_EXCLUDES, load_mcp_tools, wrap_filesystem_tools
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
                    "jira_delegate_instruction": "Use the `task` tool to delegate Jira discovery and issue-management work to the `jira_agent` specialist.",
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
                "jira_delegate_instruction": "Use `call_jira_agent` for Jira-focused work.",
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

    create_issue_dir = app_dir / "subagents" / "create-issue"
    edit_issue_dir = app_dir / "subagents" / "edit-issue"
    create_issue_settings = load_env_file(create_issue_dir / ".env")
    edit_issue_settings = load_env_file(edit_issue_dir / ".env")

    @tool
    def describe_jira_operating_modes() -> str:
        """Summarize the parent Jira agent and its internal specialists."""
        return (
            "The Jira agent coordinates two internal specialists: "
            "`create_issue` for drafting and validating new issue requests, "
            "and `edit_issue` for updating existing issues. "
            "Use the create specialist when the request is primarily about opening work. "
            "Use the edit specialist when the request is about changing, commenting on, or transitioning existing work."
        )

    @tool
    def draft_issue_creation_request(summary: str, issue_type: str, details: str) -> str:
        """Draft the minimum structured issue-creation payload before a Jira mutation."""
        default_project = create_issue_settings.get("CREATE_ISSUE_DEFAULT_PROJECT", "UNKNOWN")
        return (
            f"Draft create-issue request\n"
            f"- project: {default_project}\n"
            f"- issue_type: {issue_type}\n"
            f"- summary: {summary}\n"
            f"- details: {details}\n"
            "Validate this draft against Jira requirements before submitting."
        )

    @tool
    def draft_issue_edit_request(issue_key: str, requested_change: str) -> str:
        """Draft the minimum structured issue-edit payload before a Jira mutation."""
        allowed_fields = edit_issue_settings.get(
            "EDIT_ISSUE_ALLOWED_FIELDS",
            "summary,description,comment,status,assignee",
        )
        return (
            f"Draft edit-issue request\n"
            f"- issue_key: {issue_key}\n"
            f"- requested_change: {requested_change}\n"
            f"- allowed_fields_hint: {allowed_fields}\n"
            "Confirm that the requested change maps cleanly to one of the allowed field families before submitting."
        )

    create_issue_tools = [
        draft_issue_creation_request,
        *load_mcp_tools(create_issue_dir / "mcp.json"),
    ]
    edit_issue_tools = [
        draft_issue_edit_request,
        *load_mcp_tools(edit_issue_dir / "mcp.json"),
    ]
    parent_tools = [
        describe_jira_operating_modes,
        *load_mcp_tools(app_dir / "mcp.json"),
    ]

    return create_deep_agent(
        model=settings.get("JIRA_MODEL", "openai:gpt-5.4"),
        system_prompt=load_system_prompt(app_dir / "system_prompt.md"),
        tools=parent_tools,
        skills=resolve_skill_roots(app_dir / "skills"),
        subagents=[
            {
                "name": "create_issue",
                "description": "Create and validate new Jira issue requests.",
                "system_prompt": load_system_prompt(
                    create_issue_dir / "system_prompt.md",
                    {
                        "default_project": create_issue_settings.get(
                            "CREATE_ISSUE_DEFAULT_PROJECT", "UNKNOWN"
                        )
                    },
                ),
                "tools": create_issue_tools,
                "skills": resolve_skill_roots(create_issue_dir / "skills"),
                "model": settings.get("JIRA_CREATE_ISSUE_MODEL", settings.get("JIRA_MODEL", "openai:gpt-5.4")),
            },
            {
                "name": "edit_issue",
                "description": "Edit, comment on, or transition existing Jira issues.",
                "system_prompt": load_system_prompt(
                    edit_issue_dir / "system_prompt.md",
                    {
                        "allowed_fields": edit_issue_settings.get(
                            "EDIT_ISSUE_ALLOWED_FIELDS",
                            "summary,description,comment,status,assignee",
                        )
                    },
                ),
                "tools": edit_issue_tools,
                "skills": resolve_skill_roots(edit_issue_dir / "skills"),
                "model": settings.get("JIRA_EDIT_ISSUE_MODEL", settings.get("JIRA_MODEL", "openai:gpt-5.4")),
            },
        ],
    )
