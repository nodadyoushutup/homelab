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
                "instead of the transition comment field because some transition comment "
                "inputs expect Atlassian Document Format and reject plain text."
            )

        jira_tools = wrap_blank_optional_args(
            load_mcp_tools(self.app_dir / "mcp.json"),
            json_string_fields_by_tool=JIRA_JSON_STRING_FIELDS_BY_TOOL,
            omit_args_by_tool=JIRA_OMIT_ARGS_BY_TOOL,
            omit_false_bool_args_by_tool=JIRA_OMIT_FALSE_BOOL_ARGS_BY_TOOL,
        )
        return [describe_jira_operating_rules, *jira_tools]
