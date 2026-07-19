"""A thin ``terraform`` CLI wrapper used by every Python pipeline.

Reproduces the behavior the bash pipelines share, most importantly the
``run_terraform_init`` helper that recovers from a changed S3 backend by
retrying with ``-migrate-state`` and then ``-reconfigure``.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
from typing import Sequence

from .logging_util import PipelineError, warn

_BACKEND_CHANGED_MARKER = "Backend configuration changed"


def require_terraform() -> None:
    """Abort unless the ``terraform`` binary is on ``PATH`` (mirrors bash)."""

    if shutil.which("terraform") is None:
        raise PipelineError("terraform not found on PATH")


class TerraformRunner:
    """Runs ``terraform`` subcommands in a fixed working directory."""

    def __init__(self, terraform_dir: Path | str, exe: str = "terraform"):
        self.terraform_dir = Path(terraform_dir)
        self.exe = exe

    # -- low level ---------------------------------------------------------
    def _popen_args(self, args: Sequence[str], chdir: Path | None) -> list[str]:
        cmd = [self.exe]
        if chdir is not None:
            cmd.append(f"-chdir={chdir}")
        cmd.extend(args)
        return cmd

    def stream(self, args: Sequence[str], *, chdir: Path | None = None, env: dict | None = None) -> int:
        """Run terraform, inheriting stdio; return the exit code."""

        cmd = self._popen_args(args, chdir if chdir is not None else self.terraform_dir)
        proc = subprocess.run(cmd, env=env)
        return proc.returncode

    def capture(
        self, args: Sequence[str], *, chdir: Path | None = None, env: dict | None = None, echo: bool = True
    ) -> tuple[int, str]:
        """Run terraform, teeing combined stdout+stderr; return (code, output)."""

        cmd = self._popen_args(args, chdir if chdir is not None else self.terraform_dir)
        lines: list[str] = []
        proc = subprocess.Popen(
            cmd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        assert proc.stdout is not None
        for line in proc.stdout:
            if echo:
                print(line, end="", flush=True)
            lines.append(line)
        proc.wait()
        return proc.returncode, "".join(lines)

    def output_only(self, args: Sequence[str], *, chdir: Path | None = None, env: dict | None = None) -> str:
        """Run terraform quietly and return stripped stdout ('' on failure)."""

        cmd = self._popen_args(args, chdir if chdir is not None else self.terraform_dir)
        try:
            proc = subprocess.run(
                cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True
            )
        except OSError:
            return ""
        if proc.returncode != 0:
            return ""
        return (proc.stdout or "").strip()

    # -- high level --------------------------------------------------------
    def init(self, backend_config: Path | str, *, extra_args: Sequence[str] = ()) -> None:
        """``terraform init`` with backend-change recovery (raises on failure)."""

        base = ["init", f"-backend-config={backend_config}", *extra_args]
        code, output = self.capture(base)
        if code == 0:
            return

        if _BACKEND_CHANGED_MARKER in output:
            state_file = self.terraform_dir / ".terraform" / "terraform.tfstate"
            if state_file.is_file():
                warn("Backend change detected; attempting state migration")
                if self.stream(
                    ["init", "-force-copy", "-migrate-state", f"-backend-config={backend_config}", *extra_args]
                ) == 0:
                    return
            warn("Backend change detected; re-running terraform init -reconfigure")
            if self.stream(
                ["init", "-reconfigure", f"-backend-config={backend_config}", *extra_args]
            ) == 0:
                return

        raise PipelineError("terraform init failed")

    def init_backend_false(self) -> None:
        """``terraform init -backend=false`` (for console/validation only)."""

        if self.stream(["init", "-backend=false", "-input=false"]) != 0:
            raise PipelineError(f"Unable to initialize {self.terraform_dir} (backend=false)")

    def plan(self, args: Sequence[str]) -> None:
        if self.stream(["plan", *args]) != 0:
            raise PipelineError("terraform plan failed")

    def apply(self, args: Sequence[str]) -> None:
        if self.stream(["apply", *args]) != 0:
            raise PipelineError("terraform apply failed")

    def console(self, expression: str, *, var_files: Sequence[Path | str] = ()) -> str:
        """Evaluate a Terraform ``console`` expression, return stdout ('' on error)."""

        args = ["console"]
        for vf in var_files:
            args += ["-var-file", str(vf)]
        cmd = self._popen_args(args, self.terraform_dir)
        try:
            proc = subprocess.run(
                cmd,
                input=expression + "\n",
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
        except OSError:
            return ""
        if proc.returncode != 0:
            return ""
        return (proc.stdout or "").strip()

    def state_has(self, address: str) -> bool:
        """True if ``terraform state show <address>`` succeeds."""

        cmd = self._popen_args(["state", "show", "-no-color", address], self.terraform_dir)
        proc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return proc.returncode == 0

    def state_show_text(self, address: str) -> str:
        return self.output_only(["state", "show", "-no-color", address])

    def state_rm(self, address: str) -> None:
        self.stream(["state", "rm", address])

    def state_pull(self) -> bool:
        cmd = self._popen_args(["state", "pull"], self.terraform_dir)
        proc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return proc.returncode == 0

    def import_resource(self, address: str, resource_id: str, *, var_files: Sequence[Path | str] = ()) -> bool:
        args = ["import", "-input=false"]
        for vf in var_files:
            args += ["-var-file", str(vf)]
        args += [address, resource_id]
        return self.stream(args) == 0

    def output_raw(self, name: str) -> str:
        return self.output_only(["output", "-raw", name])
