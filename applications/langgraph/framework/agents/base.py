from __future__ import annotations

from pathlib import Path
from typing import Any

from deepagents import create_deep_agent

from framework.configuration import default_repo_root
from framework.configuration import load_markdown_directory
from framework.configuration import load_system_prompt
from framework.configuration import merged_settings
from framework.configuration import resolve_skill_roots


class BaseAgent:
    """Reusable builder for concrete Deep Agents runtime instances."""

    default_model = "openai:gpt-5.4"
    model_setting: str | None = None
    base_prompt_filename = "base_system_prompt.md"
    agent_prompt_filename: str | None = None
    prompt_filename = "system_prompt.md"
    docs_prompt_name: str | None = None
    require_docs_prompt = False

    def __init__(self, app_dir: Path):
        self.app_dir = Path(app_dir)
        self.settings = merged_settings(self.app_dir)

    @property
    def model(self) -> str:
        if self.model_setting:
            return self.settings.get(self.model_setting, self.default_model)
        return self.default_model

    @property
    def prompt_path(self) -> Path:
        return self.app_dir / self.prompt_filename

    @property
    def base_prompt_path(self) -> Path:
        return Path(__file__).resolve().parent / "system_prompts" / self.base_prompt_filename

    @property
    def agent_prompt_path(self) -> Path | None:
        if not self.agent_prompt_filename:
            return None
        return Path(__file__).resolve().parent / "system_prompts" / self.agent_prompt_filename

    @property
    def docs_prompt_dir(self) -> Path:
        prompt_name = self.docs_prompt_name or self.app_dir.name
        return default_repo_root() / "docs" / "subagents" / prompt_name

    def prompt_variables(self) -> dict[str, str]:
        return {}

    def base_system_prompt(self) -> str:
        return load_system_prompt(self.base_prompt_path, self.prompt_variables())

    def agent_system_prompt(self) -> str | None:
        agent_prompt_path = self.agent_prompt_path
        if not agent_prompt_path:
            return None
        return load_system_prompt(agent_prompt_path, self.prompt_variables())

    def object_system_prompts(self) -> list[str]:
        docs_prompts = load_markdown_directory(self.docs_prompt_dir, self.prompt_variables())
        if docs_prompts:
            return docs_prompts

        if self.require_docs_prompt:
            raise FileNotFoundError(
                "Object-level prompt docs are required for "
                f"{self.__class__.__name__}: {self.docs_prompt_dir}/*.md"
            )

        return [load_system_prompt(self.prompt_path, self.prompt_variables())]

    def prompt_parts(self) -> list[str]:
        parts = [self.base_system_prompt()]
        agent_prompt = self.agent_system_prompt()
        if agent_prompt:
            parts.append(agent_prompt)
        parts.extend(self.object_system_prompts())
        return parts

    def system_prompt(self) -> str:
        return "\n\n---\n\n".join(self.prompt_parts())

    def tools(self) -> list[Any]:
        return []

    def skills(self) -> list[str]:
        return resolve_skill_roots(self.app_dir / "skills")

    def subagents(self) -> list[Any]:
        return []

    def build_kwargs(self) -> dict[str, Any]:
        kwargs: dict[str, Any] = {
            "model": self.model,
            "tools": self.tools(),
            "system_prompt": self.system_prompt(),
        }

        skills = self.skills()
        if skills:
            kwargs["skills"] = skills

        subagents = self.subagents()
        if subagents:
            kwargs["subagents"] = subagents

        return kwargs

    def build(self):
        return create_deep_agent(**self.build_kwargs())
