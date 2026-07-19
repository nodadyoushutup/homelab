"""Packer image build pipeline.

Python port of ``packer/pipeline/packer.sh``: validate inputs, then run the
existing ``packer/packer.sh`` build (and optionally ``packer/upload.sh``) with
the composed per-distro arguments.  The heavy lifting stays in those scripts;
this entrypoint mirrors the pipeline wrapper's argument handling.
"""

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from .logging_util import PipelineError
from .paths import repo_root

_VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")

USAGE = """Usage: packer/pipeline/packer.py --version <version> [options]

Emulates the repo's Packer GitHub Actions workflow by running the existing
packer build and upload scripts in order.

Required:
  --version <X.Y.Z>                Image version to build

Options:
  --distro <ubuntu|arch|centos|kali> Distro to build (default: ubuntu)
  --gui <headless|gnome|kde|xfce>  Desktop environment to install (default: headless)
  --install_node_exporter          Install host-level node_exporter systemd service (default: off)
  --ubuntu_release <24.04|26.04>   Ubuntu LTS release (ubuntu only; default: 24.04)
  --centos_stream <10>             CentOS Stream major release (centos only; default: 10)
  --arch_snapshot <snapshot>       Arch cloud image snapshot (arch only; default: template pin)
  --kali_release <2026.2>          Kali rolling release checkpoint (kali only; default: 2026.2)
  --target <cloud-image-repository> Publish target (default: cloud-image-repository)
  --amd64_accelerator <value>      kvm, tcg, or none (default: kvm)
  --arm64_accelerator <value>      kvm, tcg, or none (default: kvm)
  --build_arch <value>             amd64, arm64, or both (default: amd64)
  --publish                        Also upload artifacts over REST (default: off)
  -h, --help                       Show this help"""


def _log(message: str) -> None:
    print(f"[packer-pipeline] {message}", flush=True)


def _die(message: str) -> PipelineError:
    return PipelineError(message)


@dataclass
class PackerBuild:
    version: str = ""
    distro: str = "ubuntu"
    gui: str = "headless"
    install_node_exporter: bool = False
    ubuntu_release: str = "24.04"
    centos_stream: str = "10"
    arch_snapshot: str = ""
    kali_release: str = "2026.2"
    target: str = "cloud-image-repository"
    amd64_accelerator: str = "kvm"
    arm64_accelerator: str = "kvm"
    build_arch: str = "amd64"
    publish: bool = False

    def validate(self) -> None:
        if not self.version:
            raise _die("--version is required")
        if not _VERSION_RE.match(self.version):
            raise _die(f"Invalid version '{self.version}'. Expected semantic version like 0.0.1")
        if self.distro not in ("ubuntu", "arch", "centos", "kali"):
            raise _die(f"Invalid distro '{self.distro}'. Expected: ubuntu|arch|centos|kali")
        if self.gui not in ("headless", "gnome", "kde", "xfce"):
            raise _die(f"Invalid gui '{self.gui}'. Expected: headless|gnome|kde|xfce")
        if self.target != "cloud-image-repository":
            raise _die(f"Unsupported target '{self.target}'")
        if self.amd64_accelerator not in ("kvm", "tcg", "none"):
            raise _die(f"Invalid amd64 accelerator '{self.amd64_accelerator}'")
        if self.arm64_accelerator not in ("kvm", "tcg", "none"):
            raise _die(f"Invalid arm64 accelerator '{self.arm64_accelerator}'")
        if self.build_arch not in ("amd64", "arm64", "both"):
            raise _die(f"Invalid build_arch '{self.build_arch}'")
        if self.distro == "arch" and self.build_arch != "amd64":
            raise _die(
                "Arch Linux publishes no official arm64 cloud image; arm64 Arch builds are not "
                "supported. Use --build_arch amd64."
            )

    def _release_args(self) -> list[str]:
        if self.distro == "ubuntu":
            return ["--ubuntu_release", self.ubuntu_release]
        if self.distro == "centos":
            return ["--centos_stream", self.centos_stream]
        if self.distro == "arch":
            return ["--arch_snapshot", self.arch_snapshot] if self.arch_snapshot else []
        if self.distro == "kali":
            return ["--kali_release", self.kali_release]
        return []

    def run(self) -> None:
        self.validate()
        root = repo_root()
        release_args = self._release_args()
        node_exporter_args = ["--install_node_exporter"] if self.install_node_exporter else []

        _log(f"Version: {self.version}")
        _log(f"Distro: {self.distro}")
        _log(f"GUI: {self.gui}")
        _log(
            "Host node_exporter: "
            + ("enabled" if self.install_node_exporter else "disabled (swarm/k8s container exporter)")
        )
        _log(f"Target: {self.target}")
        _log(f"AMD64 accelerator: {self.amd64_accelerator}")
        _log(f"ARM64 accelerator: {self.arm64_accelerator}")
        _log(f"Build arch: {self.build_arch}")
        _log("REST publish: " + ("enabled" if self.publish else "disabled (served from NFS)"))

        build_cmd = [
            str(root / "packer" / "packer.sh"),
            "--version", self.version,
            "--distro", self.distro,
            "--gui", self.gui,
            "--target", self.target,
            "--build_arch", self.build_arch,
            "--amd64_accelerator", self.amd64_accelerator,
            "--arm64_accelerator", self.arm64_accelerator,
            *node_exporter_args,
            *release_args,
        ]
        if subprocess.run(build_cmd, cwd=str(root)).returncode != 0:
            raise _die("packer build failed")

        if self.publish:
            upload_cmd = [
                str(root / "packer" / "upload.sh"),
                self.version,
                "--distro", self.distro,
                "--target", self.target,
                "--build_arch", self.build_arch,
                *release_args,
            ]
            if subprocess.run(upload_cmd, cwd=str(root)).returncode != 0:
                raise _die("packer upload failed")
        else:
            _log("Skipping REST upload (--publish to enable); artifacts served from NFS data/packer.")


def parse_args(argv: list[str]) -> PackerBuild | None:
    build = PackerBuild()
    value_opts = {
        "--version": "version",
        "--distro": "distro",
        "--gui": "gui",
        "--ubuntu_release": "ubuntu_release",
        "--centos_stream": "centos_stream",
        "--arch_snapshot": "arch_snapshot",
        "--kali_release": "kali_release",
        "--target": "target",
        "--amd64_accelerator": "amd64_accelerator",
        "--arm64_accelerator": "arm64_accelerator",
        "--build_arch": "build_arch",
    }
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("-h", "--help"):
            print(USAGE)
            return None
        if arg == "--install_node_exporter":
            build.install_node_exporter = True
            i += 1
            continue
        if arg in ("--publish", "--upload"):
            build.publish = True
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
        print(f"[packer-pipeline] ERROR: {exc}", file=sys.stderr)
        sys.exit(exc.code)
    sys.exit(0)
