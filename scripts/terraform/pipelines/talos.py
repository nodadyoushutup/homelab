"""Bespoke Talos cluster reconcile logic.

Port of ``cluster/talos/pipeline/app.sh``: before plan/apply it decides which
node ``talos_machine_configuration_apply`` resources (and the bootstrap
resource) to ``-replace`` based on Talos API reachability and Kubernetes node
readiness, and redirects the talosconfig/kubeconfig local-file outputs to
writable managed paths when the configured destinations are not writable.  After
``terraform init`` it repairs the ``talos_machine_secrets`` /
``talos_machine_bootstrap`` state entries when the live API is reachable.

The reconciler is shared between the ``pre_terraform`` and ``post_init`` hooks
so the two phases see the same resolved node map.
"""

from __future__ import annotations

import base64
import os
import re
import socket
import subprocess
import tempfile
from pathlib import Path

from .logging_util import PipelineError, info, warn
from .slice_pipeline import SliceContext

MACHINE_SECRETS_STATE_ADDRESS = "talos_machine_secrets.cluster"
BOOTSTRAP_STATE_ADDRESS = "talos_machine_bootstrap.cluster"
BOOTSTRAP_STATE_ID = "machine_bootstrap"
KUBECONFIG_STATE_ADDRESS = "talos_cluster_kubeconfig.cluster"

# (resource target, tfvar key holding the node IP, role)
NODE_SPECS: list[tuple[str, str, str]] = [
    ("talos_machine_configuration_apply.k8s_cp_0", "k8s_cp_0_node", "control-plane"),
    *[
        (f"talos_machine_configuration_apply.k8s_wk_{i}", f"k8s_wk_{i}_node", "worker")
        for i in range(11)
    ],
]

_UNSET = "__UNSET__"


class TalosReconciler:
    def __init__(self) -> None:
        self.override_talosconfig = _UNSET
        self.override_kubeconfig = _UNSET
        self.node_target_ip: dict[str, str] = {}
        self.all_node_targets: list[str] = []
        self.control_plane_target = ""
        self.control_plane_ip = ""
        self._replace_seen: set[str] = set()
        self._ctx: SliceContext | None = None

    # -- tfvars helpers ----------------------------------------------------
    def _tfvars(self) -> Path:
        assert self._ctx is not None
        return self._ctx.slice_tfvars

    def _extract(self, key: str) -> str:
        pattern = re.compile(r"^\s*" + re.escape(key) + r"\s*=")
        quoted = re.compile(r'"([^"]+)"')
        try:
            text = self._tfvars().read_text(encoding="utf-8")
        except OSError:
            return ""
        for line in text.splitlines():
            if pattern.search(line):
                m = quoted.search(line)
                if m:
                    return m.group(1)
        return ""

    def _managed_talosconfig(self) -> Path:
        override = os.environ.get("MANAGED_TALOSCONFIG_OUTPUT_PATH")
        if override:
            return Path(override)
        assert self._ctx is not None
        return self._ctx.tfvars_home / "terraform/components/cluster/talos/app/talosconfig"

    def _managed_kubeconfig(self) -> Path:
        override = os.environ.get("MANAGED_KUBECONFIG_OUTPUT_PATH")
        if override:
            return Path(override)
        assert self._ctx is not None
        return self._ctx.tfvars_home / "terraform/components/cluster/talos/app/kubeconfig"

    def _configured_talosconfig(self) -> str:
        from_tfvars = self._extract("talosconfig_output_path")
        if from_tfvars:
            return from_tfvars
        return str(Path.home() / ".talos" / "config")

    def _talosconfig_output_path(self) -> str:
        if self.override_talosconfig != _UNSET:
            return self.override_talosconfig
        return self._configured_talosconfig()

    def _kubeconfig_output_path(self) -> str:
        if self.override_kubeconfig != _UNSET:
            return self.override_kubeconfig
        from_tfvars = self._extract("kubeconfig_output_path")
        if from_tfvars:
            return from_tfvars
        cluster = self._extract("cluster_name")
        if cluster:
            return str(Path.home() / ".kube" / f"{cluster}.config")
        return str(Path.home() / ".kube" / "config")

    # -- replace/var override tracking -------------------------------------
    def _append_replace(self, target: str) -> None:
        if not target or target in self._replace_seen:
            return
        self._replace_seen.add(target)
        assert self._ctx is not None
        self._ctx.extra_plan_args.append(f"-replace={target}")
        self._ctx.extra_apply_args.append(f"-replace={target}")

    def _append_var(self, expression: str) -> None:
        assert self._ctx is not None
        self._ctx.extra_plan_args += ["-var", expression]
        self._ctx.extra_apply_args += ["-var", expression]

    # -- reachability ------------------------------------------------------
    @staticmethod
    def _api_reachable(endpoint: str) -> bool:
        if not endpoint:
            return False
        try:
            with socket.create_connection((endpoint, 6443), timeout=1):
                return True
        except OSError:
            return False

    def _state_ca_matches_endpoint(self, endpoint: str) -> bool:
        ctx = self._ctx
        assert ctx is not None
        if not ctx.runner.state_has(MACHINE_SECRETS_STATE_ADDRESS):
            return False
        text = ctx.runner.state_show_text(MACHINE_SECRETS_STATE_ADDRESS)
        ca_b64 = ""
        for line in text.splitlines():
            if "ca_certificate" in line and "=" in line:
                m = re.search(r'"([^"]+)"', line)
                if m:
                    ca_b64 = m.group(1)
                    break
        if not ca_b64:
            return False
        try:
            ca_bytes = base64.b64decode(ca_b64)
        except (ValueError, base64.binascii.Error):
            return False
        with tempfile.TemporaryDirectory() as tmp:
            ca_file = Path(tmp) / "talos-ca.pem"
            ca_file.write_bytes(ca_bytes)
            proc = subprocess.run(
                [
                    "openssl", "s_client", "-verify_return_error",
                    "-connect", f"{endpoint}:50000",
                    "-servername", endpoint,
                    "-CAfile", str(ca_file),
                ],
                input="",
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=10,
            )
            return proc.returncode == 0

    # -- output redirect ---------------------------------------------------
    @staticmethod
    def _parent_writable(target: str) -> bool:
        if not target:
            return False
        parent = Path(target).parent
        while not parent.exists() and parent != parent.parent:
            parent = parent.parent
        return parent.is_dir() and os.access(parent, os.W_OK)

    def _redirect_local_outputs_if_unwritable(self) -> None:
        talos_path = self._talosconfig_output_path()
        kube_path = self._kubeconfig_output_path()
        managed_talos = self._managed_talosconfig()
        managed_kube = self._managed_kubeconfig()

        def try_redirect() -> None:
            if self._parent_writable(str(managed_talos)) and self._parent_writable(str(managed_kube)):
                self.override_talosconfig = str(managed_talos)
                self.override_kubeconfig = str(managed_kube)
            else:
                self.override_talosconfig = ""
                self.override_kubeconfig = ""

        if talos_path and not self._parent_writable(talos_path):
            try_redirect()
        if kube_path and not self._parent_writable(kube_path):
            try_redirect()

        if self.override_talosconfig == str(managed_talos) and self.override_kubeconfig == str(managed_kube):
            assert self._ctx is not None
            info(
                "Redirecting Talos local file outputs to shared managed paths under "
                f"{self._ctx.tfvars_home}/terraform/components/cluster/talos/app"
            )
            self._append_var(f"talosconfig_output_path={self.override_talosconfig}")
            self._append_var(f"kubeconfig_output_path={self.override_kubeconfig}")
        elif self.override_talosconfig == "" and self.override_kubeconfig == "":
            info("Disabling Talos local file outputs on this runner (configured paths are not writable)")
            self._append_var("talosconfig_output_path=")
            self._append_var("kubeconfig_output_path=")

    # -- node targets ------------------------------------------------------
    def _init_node_targets(self) -> None:
        self.all_node_targets = []
        self.control_plane_target = ""
        self.control_plane_ip = ""
        self.node_target_ip = {}
        for target, tfvar_key, role in NODE_SPECS:
            ip = self._extract(tfvar_key)
            if not ip:
                continue
            self.all_node_targets.append(target)
            self.node_target_ip[target] = ip
            if role == "control-plane":
                self.control_plane_target = target
                self.control_plane_ip = ip

    def _collect_ready_ips(self, kubeconfig_path: str) -> set[str] | None:
        jsonpath = (
            '{range .items[*]}'
            '{.status.addresses[?(@.type=="InternalIP")].address}{"|"}'
            '{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{"\\n"}{end}'
        )
        try:
            proc = subprocess.run(
                ["kubectl", "--kubeconfig", kubeconfig_path, "get", "nodes", "-o", f"jsonpath={jsonpath}"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=7,
            )
        except (OSError, subprocess.TimeoutExpired):
            return None
        if proc.returncode != 0 or not proc.stdout.strip():
            return None
        ready: set[str] = set()
        for line in proc.stdout.splitlines():
            if not line:
                continue
            ip, _, status = line.partition("|")
            if ip and status == "True":
                ready.add(ip)
        return ready

    # -- hooks -------------------------------------------------------------
    def pre_terraform(self, ctx: SliceContext) -> None:
        self._ctx = ctx
        mode = os.environ.get("FORCE_TALOS_BOOTSTRAP_REPLACE", "auto")

        self._init_node_targets()
        self._redirect_local_outputs_if_unwritable()
        endpoint = self._extract("endpoint")
        kubeconfig_path = self._kubeconfig_output_path()

        api_reachable = self._api_reachable(endpoint)
        ready_ips: set[str] | None = None
        if _has_cmd("kubectl") and kubeconfig_path and Path(kubeconfig_path).is_file():
            ready_ips = self._collect_ready_ips(kubeconfig_path)

        kubectl_signal = ready_ips is not None
        if kubectl_signal:
            to_replace = [t for t in self.all_node_targets if self.node_target_ip[t] not in ready_ips]
            if not to_replace:
                info("Cluster health check: all configured nodes are Ready")
            else:
                info(f"Cluster health check: reconciling {len(to_replace)} unready/missing node(s)")
                for target in to_replace:
                    self._append_replace(target)
                self._append_replace(KUBECONFIG_STATE_ADDRESS)
        else:
            if api_reachable:
                warn("Kubernetes health check unavailable; reconciling all Talos nodes")
            else:
                warn(f"Talos API {endpoint or '<unknown>'}:6443 unreachable; reconciling all Talos nodes")
            for target in self.all_node_targets:
                self._append_replace(target)
            self._append_replace(KUBECONFIG_STATE_ADDRESS)

        replace_bootstrap = self._decide_bootstrap_replace(mode, kubectl_signal, ready_ips, endpoint, api_reachable)
        if replace_bootstrap:
            info(f"Forcing replace: {BOOTSTRAP_STATE_ADDRESS}")
            self._append_replace(BOOTSTRAP_STATE_ADDRESS)
        else:
            info("Skipping forced bootstrap replace (API reachable)")

    def _decide_bootstrap_replace(
        self, mode: str, kubectl_signal: bool, ready_ips: set[str] | None, endpoint: str, api_reachable: bool
    ) -> bool:
        if mode in ("always", "true", "1", "yes"):
            return True
        if mode in ("never", "false", "0", "no"):
            return False
        if mode != "auto":
            warn(f"Unknown FORCE_TALOS_BOOTSTRAP_REPLACE='{mode}', defaulting to auto")
        # auto (and unknown fallthrough share the same logic)
        if kubectl_signal:
            assert ready_ips is not None
            return not (self.control_plane_ip and self.control_plane_ip in ready_ips)
        if not endpoint:
            warn("Talos endpoint not found in tfvars; forcing bootstrap replace")
            return True
        return not api_reachable

    def post_init(self, ctx: SliceContext) -> None:
        self._ctx = ctx
        endpoint = self._extract("endpoint")
        if not endpoint:
            warn("Talos endpoint not found in tfvars; skipping bootstrap state repair")
            return
        if not self._api_reachable(endpoint):
            info(f"Talos API {endpoint}:6443 is unreachable; skipping bootstrap import repair")
            return

        self._repair_machine_secrets_state(endpoint)

        if ctx.runner.state_has(BOOTSTRAP_STATE_ADDRESS):
            return

        warn(f"{BOOTSTRAP_STATE_ADDRESS} missing from state while API is reachable; importing it")
        if ctx.runner.import_resource(BOOTSTRAP_STATE_ADDRESS, BOOTSTRAP_STATE_ID, var_files=[ctx.slice_tfvars]):
            info(f"Imported {BOOTSTRAP_STATE_ADDRESS} into state")
            return
        raise PipelineError(f"Failed to import {BOOTSTRAP_STATE_ADDRESS}; manual recovery required")

    def _repair_machine_secrets_state(self, endpoint: str) -> None:
        ctx = self._ctx
        assert ctx is not None
        if self._state_ca_matches_endpoint(endpoint):
            return

        if ctx.runner.state_has(MACHINE_SECRETS_STATE_ADDRESS):
            warn(f"{MACHINE_SECRETS_STATE_ADDRESS} CA does not match the live Talos API; repairing it")
        else:
            warn(f"{MACHINE_SECRETS_STATE_ADDRESS} missing from state while Talos API is reachable; importing it")

        import_path = self._ensure_secrets_import_file()
        if import_path is None:
            raise PipelineError(
                f"Unable to repair {MACHINE_SECRETS_STATE_ADDRESS}; "
                "expected a readable Talos config for live export"
            )

        if ctx.runner.state_has(MACHINE_SECRETS_STATE_ADDRESS):
            ctx.runner.state_rm(MACHINE_SECRETS_STATE_ADDRESS)

        ok = ctx.runner.import_resource(
            MACHINE_SECRETS_STATE_ADDRESS, str(import_path), var_files=[ctx.slice_tfvars]
        )
        if not ok:
            _cleanup(import_path)
            raise PipelineError(f"Failed to import {MACHINE_SECRETS_STATE_ADDRESS} from {import_path}")

        if not self._state_ca_matches_endpoint(endpoint):
            _cleanup(import_path)
            raise PipelineError(
                f"Imported {MACHINE_SECRETS_STATE_ADDRESS}, but its CA still does not match the live Talos API"
            )

        _cleanup(import_path)
        info(f"Repaired {MACHINE_SECRETS_STATE_ADDRESS} from {import_path}")

    def _ensure_secrets_import_file(self) -> Path | None:
        ctx = self._ctx
        assert ctx is not None
        preset = os.environ.get("TALOS_SECRETS_IMPORT_PATH")
        if preset and Path(preset).is_file():
            return Path(preset)

        export_script = ctx.root / "scripts" / "terraform" / "export_talos_secrets_from_machineconfig.py"
        bootstrap_node = self._extract("bootstrap_node")
        candidates = [
            self._talosconfig_output_path(),
            self._configured_talosconfig(),
            str(self._managed_talosconfig()),
            str(Path.home() / ".talos" / "config"),
        ]
        talosconfig_path = next((c for c in candidates if c and Path(c).is_file()), "")

        if not export_script.is_file() or not bootstrap_node or not talosconfig_path:
            return None

        handle = tempfile.NamedTemporaryFile(prefix="talos-machine-secrets-", suffix=".yaml", delete=False)
        handle.close()
        import_path = Path(handle.name)

        proc = subprocess.run(
            [
                "python3", str(export_script),
                "--talosconfig", talosconfig_path,
                "--node", bootstrap_node,
                "--output", str(import_path),
            ],
            stdout=subprocess.DEVNULL,
        )
        if proc.returncode == 0:
            info(f"Exporting live Talos machine secrets to {import_path}")
            return import_path
        _cleanup(import_path)
        return None


def _has_cmd(name: str) -> bool:
    import shutil

    return shutil.which(name) is not None


def _cleanup(path: Path) -> None:
    try:
        path.unlink(missing_ok=True)
    except OSError:
        pass
