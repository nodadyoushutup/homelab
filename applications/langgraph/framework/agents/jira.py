from __future__ import annotations

from langchain.tools import tool

from framework.mcp_support import JIRA_JSON_STRING_FIELDS_BY_TOOL
from framework.mcp_support import JIRA_OMIT_ARGS_BY_TOOL
from framework.mcp_support import JIRA_OMIT_FALSE_BOOL_ARGS_BY_TOOL
from framework.mcp_support import load_mcp_tools
from framework.mcp_support import wrap_blank_optional_args

from .base import BaseAgent


class JiraAgent(BaseAgent):
    model_setting = "JIRA_MODEL"
    agent_prompt_filename = "jira_system_prompt.md"
    docs_prompt_name = "jira"
    require_docs_prompt = True

    def tools(self) -> list:
        @tool
        def describe_jira_operating_rules() -> str:
            """Summarize how the single-layer Jira agent should handle Jira work."""
            return (
                "The Jira agent is a single-layer specialist for Jira discovery, "
                "net-new issue creation, and existing issue updates. "
                "Identify the current workflow stage from live Jira and deployment docs, "
                "act in service of that stage, ask follow-up questions only for real "
                "blockers, and state when a stage is complete. "
                "Treat create/open/file/log/raise/submit/add/make/write-up language for "
                "an issue without a key as net-new intent; treat an existing key or "
                "explicit change/comment/assignment/transition as update intent. "
                "For new issues, lock summary and issue type before deep requirements "
                "intake (defaults and status names are in the deployment Jira docs). "
                "For pure transitions, pass only required transition fields unless Jira "
                "requires more. "
                "If a note is needed with a transition, prefer `jira_add_comment` after "
                "the transition when transition-comment fields expect ADF, not plain text."
            )

        jira_tools = wrap_blank_optional_args(
            load_mcp_tools(self.app_dir / "mcp.json"),
            json_string_fields_by_tool=JIRA_JSON_STRING_FIELDS_BY_TOOL,
            omit_args_by_tool=JIRA_OMIT_ARGS_BY_TOOL,
            omit_false_bool_args_by_tool=JIRA_OMIT_FALSE_BOOL_ARGS_BY_TOOL,
        )
        return [describe_jira_operating_rules, *jira_tools]
