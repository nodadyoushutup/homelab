"""Docker multi-arch build+push pipeline.

Python port of ``scripts/docker/build_push.sh`` (which itself emulates the repo's
Docker GitHub Actions workflow).  Builds per-architecture images with
``docker buildx`` and publishes a combined manifest to GHCR and/or Zot.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

from .logging_util import PipelineError
from .paths import repo_root

GHCR_NAMESPACE_DEFAULT = "ghcr.io/nodadyoushutup"
ZOT_REGISTRY_DEFAULT = "zot.nodadyoushutup.com"
_SUPPORTED_PLATFORMS = ("linux/amd64", "linux/arm64")
_VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")

# build_target -> (image_name, docker_context, dockerfile relative to context/root)
BUILD_TARGETS: dict[str, tuple[str, str, str | None]] = {
    "cloud-image-repository": ("cloud-image-repository", "applications/cloud-image-repository", None),
    "gha-runner": ("gha-runner", ".", "applications/gha-runner/Dockerfile"),
    "jenkins-agent": ("jenkins-agent", ".", "applications/jenkins-agent/Dockerfile"),
    "jenkins-controller": ("jenkins-controller", ".", "applications/jenkins-controller/Dockerfile"),
    "mcp-argocd": ("mcp-argocd", "applications/mcp-argocd", None),
    "mcp-atlassian": ("mcp-atlassian", "applications/mcp-atlassian", None),
    "mcp-cloudflare": ("mcp-cloudflare", "applications/mcp-cloudflare", None),
    "mcp-fortigate": ("mcp-fortigate", "applications/mcp-fortigate", None),
    "mcp-github": ("mcp-github", "applications/mcp-github", None),
    "mcp-google-workspace": ("mcp-google-workspace", "applications/mcp-google-workspace", None),
    "mcp-terraform": ("mcp-terraform", "applications/mcp-terraform", None),
}

USAGE = """Usage: scripts/docker/build_push.py --version <version> --target_registry <github|zot|both> --build_target <target> [options]

Emulates the repo's Docker GitHub Actions workflow as a repo-native Python entrypoint.

Required:
  --version <X.Y.Z>                Version tag to publish
  --target_registry <value>        Registry target: github, zot, or both
  --build_target <value>           Build target from the workflow target list

Options:
  --build_platforms <value>        both, amd64, or arm64 (default: both)
  --phase <value>                  all, build-direct-arch, or publish-direct-manifest (default: all)
  --native_arch <value>            amd64 or arm64; required for build-direct-arch
  --install_binfmt                 Install qemu/binfmt before cross-arch builds
  --github_username <value>        Override GHCR username
  --github_token <value>           Override GHCR token/PAT
  --zot_username <value>           Zot registry username (zot/both publishes)
  --zot_password <value>           Zot registry password (zot/both publishes)
  -h, --help                       Show this help

Environment fallbacks:
  GHCR_USERNAME / GITHUB_ACTOR
  GHCR_TOKEN / GITHUB_TOKEN
  ZOT_REGISTRY_USERNAME / ZOT_REGISTRY_PASSWORD"""


def _log(message: str) -> None:
    print(f"[docker-pipeline] {message}", flush=True)


def _die(message: str) -> PipelineError:
    return PipelineError(message)


@dataclass
class DockerBuild:
    version: str = ""
    target_registry: str = ""
    build_target: str = ""
    build_platforms: str = "both"
    phase: str = "all"
    native_arch: str = ""
    install_binfmt: bool = False
    github_username: str = ""
    github_token: str = ""
    zot_username: str = ""
    zot_password: str = ""

    # resolved fields
    root: Path = field(default_factory=repo_root)
    ghcr_namespace: str = ""
    zot_registry: str = ""
    image_name: str = ""
    docker_context: str = ""
    dockerfile: str = ""
    publish_github: bool = False
    publish_zot: bool = False
    ghcr_image_base: str = ""
    zot_image_base: str = ""
    build_amd64: bool = False
    build_arm64: bool = False
    platforms_csv: str = ""

    # -- validation / resolution ------------------------------------------
    def validate(self) -> None:
        if not self.version:
            raise _die("--version is required")
        if not _VERSION_RE.match(self.version):
            raise _die(f"Invalid version '{self.version}'. Expected semantic version like 0.0.1")
        if not self.target_registry:
            raise _die("--target_registry is required")
        if not self.build_target:
            raise _die("--build_target is required")
        if self.phase not in ("all", "build-direct-arch", "publish-direct-manifest"):
            raise _die(f"Unsupported --phase '{self.phase}'")
        if self.native_arch not in ("", "amd64", "arm64"):
            raise _die(f"Unsupported --native_arch '{self.native_arch}'")

        self.ghcr_namespace = os.environ.get("GHCR_NAMESPACE", GHCR_NAMESPACE_DEFAULT)
        self.zot_registry = os.environ.get("ZOT_REGISTRY", ZOT_REGISTRY_DEFAULT)

    def resolve_build_target(self) -> None:
        try:
            image_name, context, dockerfile = BUILD_TARGETS[self.build_target]
        except KeyError as exc:
            raise _die(f"Unsupported build target: {self.build_target}") from exc
        self.image_name = image_name
        self.docker_context = context
        self.dockerfile = dockerfile or f"{context}/Dockerfile"
        if not (self.root / self.dockerfile).is_file():
            raise _die(f"Dockerfile not found: {self.dockerfile}")

    def resolve_registry_target(self) -> None:
        if self.target_registry == "both":
            self.publish_github = self.publish_zot = True
        elif self.target_registry == "github":
            self.publish_github = True
        elif self.target_registry == "zot":
            self.publish_zot = True
        else:
            raise _die(f"Unsupported target_registry: {self.target_registry}")
        if self.publish_github:
            self.ghcr_image_base = f"{self.ghcr_namespace}/{self.image_name}"
        if self.publish_zot:
            self.zot_image_base = f"{self.zot_registry}/{self.image_name}"

    def resolve_platforms(self) -> None:
        requested = {
            "both": ("linux/amd64", "linux/arm64"),
            "amd64": ("linux/amd64",),
            "arm64": ("linux/arm64",),
        }.get(self.build_platforms)
        if requested is None:
            raise _die(f"Unsupported build_platforms selection: {self.build_platforms}")
        filtered = [p for p in _SUPPORTED_PLATFORMS if p in requested]
        if not filtered:
            raise _die(
                f"Build target {self.build_target} does not support "
                f"requested build_platforms={self.build_platforms}"
            )
        self.platforms_csv = ",".join(filtered)
        self.build_amd64 = "linux/amd64" in filtered
        self.build_arm64 = "linux/arm64" in filtered

    # -- docker helpers ----------------------------------------------------
    @staticmethod
    def _require_cmd(cmd: str) -> None:
        if shutil.which(cmd) is None:
            raise _die(f"Missing required command: {cmd}")

    def _run(self, args: list[str], *, cwd: Path | None = None, stdin: str | None = None) -> None:
        proc = subprocess.run(args, cwd=str(cwd) if cwd else None, input=stdin, text=stdin is not None)
        if proc.returncode != 0:
            raise _die(f"command failed: {' '.join(args)}")

    def ensure_buildx(self) -> None:
        self._require_cmd("docker")
        if subprocess.run(["docker", "buildx", "version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
            raise _die("docker buildx is required")
        if subprocess.run(["docker", "buildx", "inspect"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
            self._run(["docker", "buildx", "create", "--name", "homelab-pipelines", "--use"])
        self._run(["docker", "buildx", "inspect", "--bootstrap"])

    def install_binfmt_if_requested(self) -> None:
        if self.install_binfmt:
            _log("Installing qemu/binfmt handlers")
            self._run(["docker", "run", "--privileged", "--rm", "tonistiigi/binfmt", "--install", "all"])

    def registry_login(self) -> None:
        self._require_cmd("docker")
        if self.target_registry in ("both", "github"):
            self._registry_login_github()
        elif self.target_registry == "zot":
            pass
        else:
            raise _die(f"Unsupported target_registry: {self.target_registry}")
        if self.publish_zot:
            self._registry_login_zot()

    def _registry_login_github(self) -> None:
        username = self.github_username or os.environ.get("GHCR_USERNAME") or os.environ.get("GITHUB_ACTOR")
        token = self.github_token or os.environ.get("GHCR_TOKEN") or os.environ.get("GITHUB_TOKEN")
        if not username:
            raise _die("GitHub registry username is required via --github_username, GHCR_USERNAME, or GITHUB_ACTOR")
        if not token:
            raise _die("GitHub registry token is required via --github_token, GHCR_TOKEN, or GITHUB_TOKEN")
        self._run(["docker", "login", "ghcr.io", "--username", username, "--password-stdin"], stdin=token)

    def _registry_login_zot(self) -> None:
        username = self.zot_username or os.environ.get("ZOT_REGISTRY_USERNAME")
        password = self.zot_password or os.environ.get("ZOT_REGISTRY_PASSWORD")
        if not username:
            raise _die("Zot username is required via --zot_username or ZOT_REGISTRY_USERNAME")
        if not password:
            raise _die("Zot password is required via --zot_password or ZOT_REGISTRY_PASSWORD")
        self._run(["docker", "login", self.zot_registry, "--username", username, "--password-stdin"], stdin=password)

    def build_direct_arch(self, arch: str) -> None:
        image_refs: list[str] = []
        tag_args: list[str] = []
        if self.publish_github:
            ref = f"{self.ghcr_image_base}:{self.version}-{arch}"
            image_refs.append(ref)
            tag_args += ["--tag", ref]
        if self.publish_zot:
            ref = f"{self.zot_image_base}:{self.version}-{arch}"
            image_refs.append(ref)
            tag_args += ["--tag", ref]
        if not image_refs:
            raise _die("No registry targets were prepared for publish")

        self.ensure_buildx()
        _log(f"Building {self.image_name}:{self.version}-{arch} from {self.dockerfile} for {self.target_registry}")
        self._run(
            [
                "docker", "buildx", "build",
                "--platform", f"linux/{arch}",
                "--provenance=false",
                "--sbom=false",
                "--file", self.dockerfile,
                "--load",
                *tag_args,
                self.docker_context,
            ],
            cwd=self.root,
        )
        for ref in image_refs:
            _log(f"Pushing {ref}")
            self._run(["docker", "push", ref])

    def publish_direct_manifests(self) -> None:
        os.environ["DOCKER_CLI_EXPERIMENTAL"] = "enabled"

        def publish_for_base(image_base: str) -> None:
            refs: list[str] = []
            if self.build_amd64:
                refs.append(f"{image_base}:{self.version}-amd64")
            if self.build_arm64:
                refs.append(f"{image_base}:{self.version}-arm64")
            if not refs:
                raise _die("No per-architecture image refs were prepared for manifest publish")

            for tag in (self.version, "latest"):
                target = f"{image_base}:{tag}"
                subprocess.run(["docker", "manifest", "rm", target], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self._run(["docker", "manifest", "create", target, *refs])
            for ref in refs:
                arch = ref.rsplit("-", 1)[-1]
                for tag in (self.version, "latest"):
                    self._run(
                        ["docker", "manifest", "annotate", f"{image_base}:{tag}", ref, "--os", "linux", "--arch", arch]
                    )
            _log(f"Publishing manifest tags {image_base}:{self.version} and {image_base}:latest")
            self._run(["docker", "manifest", "push", f"{image_base}:{self.version}"])
            self._run(["docker", "manifest", "push", f"{image_base}:latest"])

        if self.publish_github:
            publish_for_base(self.ghcr_image_base)
        if self.publish_zot:
            publish_for_base(self.zot_image_base)

    # -- orchestration -----------------------------------------------------
    def run(self) -> None:
        self.validate()
        self.resolve_build_target()
        self.resolve_registry_target()
        self.resolve_platforms()

        _log(f"Version: {self.version}")
        _log(f"Target registry: {self.target_registry}")
        _log(f"Build target: {self.build_target}")
        _log("Build strategy: direct")
        _log(f"Platforms: {self.platforms_csv}")
        _log(f"Phase: {self.phase}")

        self.registry_login()
        self.install_binfmt_if_requested()

        if self.phase == "all":
            if self.build_amd64:
                self.build_direct_arch("amd64")
            if self.build_arm64:
                self.build_direct_arch("arm64")
            self.publish_direct_manifests()
        elif self.phase == "build-direct-arch":
            if not self.native_arch:
                raise _die("--native_arch is required for --phase build-direct-arch")
            if self.native_arch == "amd64" and not self.build_amd64:
                raise _die("Requested native arch amd64 is not enabled by --build_platforms")
            if self.native_arch == "arm64" and not self.build_arm64:
                raise _die("Requested native arch arm64 is not enabled by --build_platforms")
            self.build_direct_arch(self.native_arch)
        elif self.phase == "publish-direct-manifest":
            self.publish_direct_manifests()


def parse_args(argv: list[str]) -> DockerBuild | None:
    build = DockerBuild()
    value_opts = {
        "--version": "version",
        "--target_registry": "target_registry",
        "--build_target": "build_target",
        "--build_platforms": "build_platforms",
        "--phase": "phase",
        "--native_arch": "native_arch",
        "--github_username": "github_username",
        "--github_token": "github_token",
        "--zot_username": "zot_username",
        "--zot_password": "zot_password",
    }
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("-h", "--help"):
            print(USAGE)
            return None
        if arg == "--install_binfmt":
            build.install_binfmt = True
            i += 1
            continue
        if arg in value_opts:
            if i + 1 >= len(argv):
                raise _die(f"{arg} requires a value")
            setattr(build, value_opts[arg], argv[i + 1])
            i += 2
            continue
        raise _die(f"Unknown argument: {arg}")
    return build


def main(argv: list[str] | None = None) -> None:
    argv = list(argv if argv is not None else sys.argv[1:])
    try:
        build = parse_args(argv)
        if build is None:
            sys.exit(0)
        build.run()
    except PipelineError as exc:
        print(f"[docker-pipeline] ERROR: {exc}", file=sys.stderr)
        sys.exit(exc.code)
    sys.exit(0)
