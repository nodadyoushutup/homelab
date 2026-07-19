"""The standard Terraform slice pipeline: init -> plan -> apply.

Every homelab ``pipeline/<slice>.sh`` shares the same skeleton:

    * resolve the slice tfvars + S3 backend by config-id (with env / CLI / arg
      overrides),
    * validate ``terraform`` and the required var-files exist,
    * ``terraform init`` (with backend-change recovery),
    * ``terraform plan`` then ``terraform apply -auto-approve`` with an ordered
      list of ``-var-file`` args.

``SlicePipeline`` captures that skeleton.  Bespoke slices (Vault, Talos,
Jenkins agents, Grafana database, NPM config) plug their extra behavior in via
the ``pre_terraform`` / ``post_init`` / ``post_apply`` hooks and by mutating the
``SliceContext`` (extra var-files / plan / apply args).
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Sequence

from . import paths
from .cli import SliceArgs, env_first, parse_slice_args
from .config_resolver import ConfigResolver, config_id_from_terraform_dir
from .logging_util import PipelineError, done, err, step
from .providers import ProviderVarFile, provider
from .terraform import TerraformRunner, require_terraform


class _Slice:
    """Sentinel marking where the slice's own tfvars sits in ``var_files``."""

    def __repr__(self) -> str:  # pragma: no cover - cosmetic
        return "SLICE"


SLICE = _Slice()

Hook = Callable[["SliceContext"], None]


@dataclass
class SliceContext:
    """Mutable state shared with pipeline hooks."""

    pipeline: "SlicePipeline"
    root: Path
    config_dir: Path
    tfvars_home: Path
    resolver: ConfigResolver
    runner: TerraformRunner
    terraform_dir: Path
    slice_tfvars: Path
    backend_config: Path
    var_files: list[Path]
    extra_var_files: list[Path] = field(default_factory=list)
    extra_plan_args: list[str] = field(default_factory=list)
    extra_apply_args: list[str] = field(default_factory=list)

    def all_var_files(self) -> list[Path]:
        return [*self.var_files, *self.extra_var_files]


@dataclass
class SlicePipeline:
    """Declarative spec for a standard Terraform slice deploy."""

    name: str
    terraform_dir: str
    tfvars_env: str
    backend_env: str
    var_files: Sequence[object] = (SLICE,)
    slice_label: str = "slice tfvars"
    apply_extra: Sequence[str] = ()
    parallelism: int | None = None
    pre_terraform: Hook | None = None
    post_init: Hook | None = None
    post_apply: Hook | None = None
    summary: str = ""

    # -- usage/help --------------------------------------------------------
    def usage(self, default_tfvars: str, default_backend: str) -> str:
        rel = self.terraform_dir
        pipeline_rel = _pipeline_rel(rel)
        summary = self.summary or f"Deploy {self.name} (terraform init, plan, apply)."
        return (
            f"Usage: {pipeline_rel} [options] [slice_tfvars] [backend_config]\n\n"
            f"{summary}\n\n"
            "Options:\n"
            f"  --tfvars <path>           Slice tfvars (default: {default_tfvars})\n"
            f"  --backend <path>          S3 backend config (default: {default_backend})\n"
            "  -h, --help                Show this help\n\n"
            f"Environment overrides: {self.tfvars_env}, {self.backend_env}, "
            "CONFIG_DIR (default: <repo>/.config)"
        )

    # -- execution ---------------------------------------------------------
    def build_context(self, argv: list[str]) -> SliceContext | None:
        root = paths.repo_root()
        config_dir = paths.config_dir(root)
        os.environ.setdefault("CONFIG_DIR", str(config_dir))
        tfvars_home = paths.tfvars_home_dir(root)

        resolver = ConfigResolver(config_dir)
        provider_resolver = resolver if tfvars_home == config_dir else ConfigResolver(tfvars_home)

        terraform_dir = (root / self.terraform_dir).resolve()
        slice_config_id = config_id_from_terraform_dir(root, terraform_dir)
        default_slice = str(resolver.resolve(slice_config_id))
        default_backend = str(resolver.resolve("terraform/minio.backend"))

        usage = self.usage(default_slice, default_backend)
        args = parse_slice_args(argv, usage=usage)
        if args.help:
            return None

        slice_tfvars = _resolve_path(default_slice, self.tfvars_env, args, "tfvars")
        backend_config = _resolve_path(default_backend, self.backend_env, args, "backend")

        runner = TerraformRunner(terraform_dir)
        require_terraform()

        resolved_var_files: list[Path] = []
        provider_files: list[tuple[ProviderVarFile, Path]] = []
        for entry in self.var_files:
            if isinstance(entry, _Slice):
                resolved_var_files.append(Path(slice_tfvars))
            else:
                pv = provider(str(entry))
                pv_path = pv.resolve(provider_resolver)
                provider_files.append((pv, pv_path))
                resolved_var_files.append(pv_path)

        _require_file(self.slice_label, slice_tfvars)
        _require_file("backend config", backend_config)
        for pv, pv_path in provider_files:
            _require_file(pv.label, pv_path)

        print(_kv("Terraform dir", terraform_dir))
        print(_kv(self.slice_label.capitalize(), slice_tfvars))
        print(_kv("Backend config", backend_config))

        return SliceContext(
            pipeline=self,
            root=root,
            config_dir=config_dir,
            tfvars_home=tfvars_home,
            resolver=resolver,
            runner=runner,
            terraform_dir=terraform_dir,
            slice_tfvars=Path(slice_tfvars),
            backend_config=Path(backend_config),
            var_files=resolved_var_files,
        )

    def run(self, argv: list[str] | None = None) -> int:
        argv = list(argv if argv is not None else sys.argv[1:])
        ctx = self.build_context(argv)
        if ctx is None:
            return 0

        if self.pre_terraform is not None:
            self.pre_terraform(ctx)

        step(f"terraform init ({self.name})")
        ctx.runner.init(ctx.backend_config)

        if self.post_init is not None:
            self.post_init(ctx)

        var_flags: list[str] = []
        for vf in ctx.all_var_files():
            var_flags += ["-var-file", str(vf)]

        plan_args = ["-input=false", *var_flags, *ctx.extra_plan_args]
        step(f"terraform plan ({self.name})")
        ctx.runner.plan(plan_args)

        apply_args = ["-input=false", "-auto-approve"]
        if self.parallelism is not None:
            apply_args.append(f"-parallelism={self.parallelism}")
        apply_args += [*self.apply_extra, *var_flags, *ctx.extra_apply_args]
        step(f"terraform apply ({self.name})")
        ctx.runner.apply(apply_args)

        if self.post_apply is not None:
            self.post_apply(ctx)

        done(f"{self.name} apply complete.")
        return 0

    def main(self, argv: list[str] | None = None) -> None:
        run_pipeline_main(lambda: self.run(argv))


def run_pipeline_main(runner: Callable[[], int]) -> None:
    """Execute ``runner``, translating :class:`PipelineError` into exit codes.

    The first line of the error is printed as ``[ERR] ...``; any remaining lines
    (e.g. an appended usage block) are written to stderr verbatim, matching how
    the bash pipelines emit an error line followed by usage.
    """

    import sys

    try:
        code = runner()
    except PipelineError as exc:
        lines = str(exc).splitlines() or [""]
        err(lines[0])
        for extra in lines[1:]:
            print(extra, file=sys.stderr)
        sys.exit(exc.code)
    except KeyboardInterrupt:  # pragma: no cover
        sys.exit(130)
    sys.exit(code)


def _resolve_path(default: str, env_var: str, args: SliceArgs, kind: str) -> str:
    """Apply bash precedence: TFVARS_FILE/BACKEND_FILE > positional > --opt > env > default."""

    value = env_first(env_var) or default
    if kind == "tfvars":
        if args.opt_tfvars:
            value = args.opt_tfvars
        if args.pos_tfvars:
            value = args.pos_tfvars
        override = env_first("TFVARS_FILE")
    else:
        if args.opt_backend:
            value = args.opt_backend
        if args.pos_backend:
            value = args.pos_backend
        override = env_first("BACKEND_FILE")
    if override:
        value = override
    return value


def _require_file(label: str, path: str | Path) -> None:
    p = Path(path)
    if not str(path) or not p.is_file():
        raise PipelineError(f"Missing {label}: {path}")


def _kv(label: str, value: object) -> str:
    return f"{label + ':':<18} {value}"


def _pipeline_rel(terraform_dir_rel: str) -> str:
    # terraform/components/<domain>/<component>/<slice> -> .../pipeline/<slice>.py
    parts = terraform_dir_rel.split("/")
    slice_name = parts[-1]
    component_dir = "/".join(parts[:-1])
    return f"{component_dir}/pipeline/{slice_name}.py"
