"""Native re-export of mcp-server-git tools (no stdio MCP hop)."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import git
import mcp.types as types
from mcp.types import TextContent, Tool
from mcp_server_git.server import (
    GitAdd,
    GitBranch,
    GitCheckout,
    GitCommit,
    GitCreateBranch,
    GitDiff,
    GitDiffStaged,
    GitDiffUnstaged,
    GitLog,
    GitReset,
    GitShow,
    GitStatus,
    GitTools,
    git_add,
    git_branch,
    git_checkout,
    git_commit,
    git_create_branch,
    git_diff,
    git_diff_staged,
    git_diff_unstaged,
    git_log,
    git_reset,
    git_show,
    git_status,
    validate_repo_path,
)

GIT_TOOLS: list[Tool] = [
    Tool(
        name=GitTools.STATUS,
        description="Shows the working tree status",
        inputSchema=GitStatus.model_json_schema(),
    ),
    Tool(
        name=GitTools.DIFF_UNSTAGED,
        description="Shows changes in the working directory that are not yet staged",
        inputSchema=GitDiffUnstaged.model_json_schema(),
    ),
    Tool(
        name=GitTools.DIFF_STAGED,
        description="Shows changes that are staged for commit",
        inputSchema=GitDiffStaged.model_json_schema(),
    ),
    Tool(
        name=GitTools.DIFF,
        description="Shows differences between branches or commits",
        inputSchema=GitDiff.model_json_schema(),
    ),
    Tool(
        name=GitTools.COMMIT,
        description="Records changes to the repository",
        inputSchema=GitCommit.model_json_schema(),
    ),
    Tool(
        name=GitTools.ADD,
        description="Adds file contents to the staging area",
        inputSchema=GitAdd.model_json_schema(),
    ),
    Tool(
        name=GitTools.RESET,
        description="Unstages all staged changes",
        inputSchema=GitReset.model_json_schema(),
    ),
    Tool(
        name=GitTools.LOG,
        description="Shows the commit logs",
        inputSchema=GitLog.model_json_schema(),
    ),
    Tool(
        name=GitTools.CREATE_BRANCH,
        description="Creates a new branch from an optional base branch",
        inputSchema=GitCreateBranch.model_json_schema(),
    ),
    Tool(
        name=GitTools.CHECKOUT,
        description="Switches branches",
        inputSchema=GitCheckout.model_json_schema(),
    ),
    Tool(
        name=GitTools.SHOW,
        description="Shows the contents of a commit",
        inputSchema=GitShow.model_json_schema(),
    ),
    Tool(
        name=GitTools.BRANCH,
        description="List Git branches",
        inputSchema=GitBranch.model_json_schema(),
    ),
]


def _text_block(text: str) -> types.CallToolResult:
    return types.CallToolResult(content=[TextContent(type="text", text=text)])


async def call_git_tool(
    name: str, arguments: dict[str, Any], *, allowed_repository: Path
) -> types.CallToolResult | None:
    if name not in {t.name for t in GIT_TOOLS}:
        return None
    repo_path = Path(arguments["repo_path"])
    validate_repo_path(repo_path, allowed_repository)
    repo = git.Repo(repo_path)

    # Tool names arrive as str; compare to enum values for reliable matching.
    if name == GitTools.STATUS:
        return _text_block(f"Repository status:\n{git_status(repo)}")
    if name == GitTools.DIFF_UNSTAGED:
        diff = git_diff_unstaged(repo, arguments.get("context_lines", 3))
        return _text_block(f"Unstaged changes:\n{diff}")
    if name == GitTools.DIFF_STAGED:
        diff = git_diff_staged(repo, arguments.get("context_lines", 3))
        return _text_block(f"Staged changes:\n{diff}")
    if name == GitTools.DIFF:
        diff = git_diff(repo, arguments["target"], arguments.get("context_lines", 3))
        return _text_block(f"Diff with {arguments['target']}:\n{diff}")
    if name == GitTools.COMMIT:
        return _text_block(git_commit(repo, arguments["message"]))
    if name == GitTools.ADD:
        return _text_block(git_add(repo, arguments["files"]))
    if name == GitTools.RESET:
        return _text_block(git_reset(repo))
    if name == GitTools.LOG:
        log = git_log(
            repo,
            arguments.get("max_count", 10),
            arguments.get("start_timestamp"),
            arguments.get("end_timestamp"),
        )
        return _text_block("Commit history:\n" + "\n".join(log))
    if name == GitTools.CREATE_BRANCH:
        return _text_block(
            git_create_branch(repo, arguments["branch_name"], arguments.get("base_branch"))
        )
    if name == GitTools.CHECKOUT:
        return _text_block(git_checkout(repo, arguments["branch_name"]))
    if name == GitTools.SHOW:
        return _text_block(git_show(repo, arguments["revision"]))
    if name == GitTools.BRANCH:
        result = git_branch(
            repo,
            arguments.get("branch_type", "local"),
            arguments.get("contains"),
            arguments.get("not_contains"),
        )
        return _text_block(result)
    return None
