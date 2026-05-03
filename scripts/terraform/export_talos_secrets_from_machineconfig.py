#!/usr/bin/env python3
"""Export a Talos machine-secrets bundle from a live machine config."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from typing import Any

import yaml


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Export a Talos machine-secrets bundle from a live machine config "
            "using talosctl."
        )
    )
    parser.add_argument("--talosconfig", required=True, help="Path to talosconfig")
    parser.add_argument("--node", required=True, help="Talos node IP or hostname")
    parser.add_argument("--output", required=True, help="Destination secrets.yaml path")
    return parser.parse_args()


def run_machineconfig_query(talosconfig: str, node: str) -> dict[str, Any]:
    cmd = [
        "talosctl",
        "--talosconfig",
        talosconfig,
        "-n",
        node,
        "get",
        "machineconfig",
        "-o",
        "json",
    ]
    proc = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return json.loads(proc.stdout)


def require(mapping: dict[str, Any], path: list[str]) -> Any:
    current: Any = mapping
    walked: list[str] = []
    for key in path:
        walked.append(key)
        if not isinstance(current, dict) or key not in current:
            raise KeyError(f"missing required field: {'.'.join(walked)}")
        current = current[key]
    return current


def build_secrets_bundle(spec_doc: dict[str, Any]) -> dict[str, Any]:
    machine = require(spec_doc, ["machine"])
    cluster = require(spec_doc, ["cluster"])

    bundle = {
        "cluster": {
            "id": require(cluster, ["id"]),
            "secret": require(cluster, ["secret"]),
        },
        "secrets": {
            "bootstraptoken": require(cluster, ["token"]),
            "secretboxencryptionsecret": require(cluster, ["secretboxEncryptionSecret"]),
        },
        "trustdinfo": {
            "token": require(machine, ["token"]),
        },
        "certs": {
            "etcd": {
                "crt": require(cluster, ["etcd", "ca", "crt"]),
                "key": require(cluster, ["etcd", "ca", "key"]),
            },
            "k8s": {
                "crt": require(cluster, ["ca", "crt"]),
                "key": require(cluster, ["ca", "key"]),
            },
            "k8saggregator": {
                "crt": require(cluster, ["aggregatorCA", "crt"]),
                "key": require(cluster, ["aggregatorCA", "key"]),
            },
            "k8sserviceaccount": {
                "key": require(cluster, ["serviceAccount", "key"]),
            },
            "os": {
                "crt": require(machine, ["ca", "crt"]),
                "key": require(machine, ["ca", "key"]),
            },
        },
    }

    aescbc = cluster.get("aescbcEncryptionSecret")
    if aescbc:
        bundle["secrets"]["aescbcencryptionsecret"] = aescbc

    return bundle


def main() -> int:
    args = parse_args()

    machineconfig = run_machineconfig_query(args.talosconfig, args.node)
    spec_text = machineconfig.get("spec")
    if not isinstance(spec_text, str) or not spec_text.strip():
        raise ValueError("machineconfig response did not include a YAML spec payload")

    docs = list(yaml.safe_load_all(spec_text))
    if not docs or not isinstance(docs[0], dict):
        raise ValueError("machineconfig spec payload did not contain a primary YAML document")

    bundle = build_secrets_bundle(docs[0])

    output_path = os.path.abspath(args.output)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as handle:
        yaml.safe_dump(bundle, handle, sort_keys=False)

    os.chmod(output_path, 0o600)
    print(output_path)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as exc:
        sys.stderr.write(exc.stderr or str(exc))
        raise SystemExit(exc.returncode)
    except Exception as exc:  # pragma: no cover
        sys.stderr.write(f"{exc}\n")
        raise SystemExit(1)
