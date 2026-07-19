"""Flask application factory and web server entrypoint for homelab-config."""

from __future__ import annotations

import atexit
import logging
import os
import signal
import threading
import time
import uuid
from pathlib import Path

from flask import Flask, render_template
from flask_socketio import emit

from homelab_config.cloud_image_repository_store import CloudImageRepositoryStore
from homelab_config.cloudflare_dns_store import CloudflareDnsStore
from homelab_config.docker_providers_store import DockerProvidersStore
from homelab_config.extensions import socketio
from homelab_config.fortigate_store import FortigateConfigStore
from homelab_config.grafana_store import GrafanaConfigStore
from homelab_config.jenkins_store import JenkinsStore
from homelab_config.minio_store import MinioStore
from homelab_config.nfs_store import NfsStore
from homelab_config.npm_store import NpmConfigStore
from homelab_config.packer_store import PackerConfigStore
from homelab_config.paths import (
    APP_DIR,
    CLOUD_IMAGE_REPOSITORY_APP_TFVARS,
    CLOUDFLARE_CONFIG_TFVARS,
    DATA_DIR,
    DEFAULT_HOST,
    DEFAULT_PORT,
    DOCKER_TFVARS,
    EXTRA_HOSTS_YAML,
    FORTIGATE_CONFIG_TFVARS,
    GRAFANA_CONFIG_TFVARS,
    MINIO_BACKEND_HCL,
    MINIO_TFVARS,
    NFS_TFVARS,
    NPM_CONFIG_TFVARS,
    PACKER_BUILD_PKRVARS,
    PID_FILE,
    PROMETHEUS_YAML,
    PROXMOX_APP_TFVARS,
    PROXMOX_TFVARS,
    SWARM_TFVARS,
    TALOS_APP_TFVARS,
    TERRAFORM_STATE_TFVARS,
    VAULT_CONFIG_TFVARS,
    VICTORIAMETRICS_APP_TFVARS,
)
from homelab_config.prometheus_store import PrometheusConfigStore
from homelab_config.provider_specs import PROVIDER_SPECS
from homelab_config.provider_store_generic import GenericProviderStore
from homelab_config.proxmox_cluster_store import ProxmoxClusterStore
from homelab_config.proxmox_store import ProxmoxStore
from homelab_config.reloader import start_reloader
from homelab_config.scaffolds import ensure_config_scaffolds
from homelab_config.store import SwarmStore
from homelab_config.talos_store import TalosStore
from homelab_config.terraform_store import TerraformStore
from homelab_config.vault_store import VaultConfigStore
from homelab_config.victoriametrics_store import VictoriaMetricsConfigStore

logger = logging.getLogger(__name__)

# Unique per process start. A hot reload re-execs the process, so this changes;
# clients compare it across reconnects and refresh when the server restarted.
BOOT_ID = uuid.uuid4().hex

# How long to wait for a previous instance to exit before escalating signals.
_TERM_WAIT_SECONDS = 5.0
_KILL_WAIT_SECONDS = 2.0
_POLL_INTERVAL_SECONDS = 0.1
# How often to poll swarm.tfvars for out-of-band ("external") changes.
_DRIFT_POLL_SECONDS = 1.0


def create_app() -> Flask:
    """Build and configure the Flask application."""
    app = Flask(__name__)
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    # Create empty scaffolds for any managed .config file that is missing, so a
    # fresh checkout boots with editable configs instead of nothing.
    ensure_config_scaffolds()

    store = SwarmStore(SWARM_TFVARS)
    app.config["SWARM_STORE"] = store

    nfs_store = NfsStore(NFS_TFVARS)
    app.config["NFS_STORE"] = nfs_store

    minio_store = MinioStore(MINIO_TFVARS)
    app.config["MINIO_STORE"] = minio_store

    # Terraform state backend settings. Renders state.tfvars (source of truth)
    # and the DERIVED minio.backend.hcl, resolving the selected MinIO instance
    # from the MinIO catalog.
    terraform_store = TerraformStore(
        TERRAFORM_STATE_TFVARS, MINIO_BACKEND_HCL, MINIO_TFVARS
    )
    app.config["TERRAFORM_STORE"] = terraform_store

    proxmox_store = ProxmoxStore(PROXMOX_TFVARS)
    app.config["PROXMOX_STORE"] = proxmox_store

    proxmox_cluster_store = ProxmoxClusterStore(PROXMOX_APP_TFVARS)
    app.config["PROXMOX_CLUSTER_STORE"] = proxmox_cluster_store

    # Talos cluster machine-config / bootstrap inputs (Kubernetes). Renders the
    # Talos slice app.tfvars.
    talos_store = TalosStore(TALOS_APP_TFVARS)
    app.config["TALOS_STORE"] = talos_store

    # Jenkins deploy inputs (CICD): one working copy per slice (controller +
    # amd64/arm64 agents). Each renders its own Swarm slice app.tfvars. The
    # Jenkins *provider* login stays in the spec-driven provider store.
    jenkins_store = JenkinsStore()
    app.config["JENKINS_STORE"] = jenkins_store

    docker_store = DockerProvidersStore(DOCKER_TFVARS, SWARM_TFVARS, EXTRA_HOSTS_YAML)
    app.config["DOCKER_STORE"] = docker_store

    # Cloud Image Repository Swarm app inputs (docker_machine, DNS, placement,
    # NFS share + sub-path). Renders the cloud-image-repository slice app.tfvars.
    cloud_image_repository_store = CloudImageRepositoryStore(
        CLOUD_IMAGE_REPOSITORY_APP_TFVARS
    )
    app.config["CLOUD_IMAGE_REPOSITORY_STORE"] = cloud_image_repository_store

    # Spec-driven single-object provider credentials (cloudflare, grafana,
    # jenkins, argocd, fortigate, nginx_proxy_manager, vault). One store per
    # spec, keyed by spec.key so the blueprints and drift watcher share them.
    provider_stores = {spec.key: GenericProviderStore(spec) for spec in PROVIDER_SPECS}
    app.config["PROVIDER_STORES"] = provider_stores

    # Desired-state config sections (NOT provider credentials): Cloudflare DNS
    # records (Remote) and FortiGate declarative config (Network). Each renders
    # its own slice config.tfvars.
    cloudflare_dns_store = CloudflareDnsStore(CLOUDFLARE_CONFIG_TFVARS)
    app.config["CLOUDFLARE_DNS_STORE"] = cloudflare_dns_store

    fortigate_config_store = FortigateConfigStore(FORTIGATE_CONFIG_TFVARS)
    app.config["FORTIGATE_CONFIG_STORE"] = fortigate_config_store

    # Nginx Proxy Manager desired state (certificates, proxy hosts, redirections,
    # streams, access lists) under Network. Renders the NPM config slice
    # config.tfvars; provider login stays separate.
    npm_config_store = NpmConfigStore(NPM_CONFIG_TFVARS)
    app.config["NPM_CONFIG_STORE"] = npm_config_store

    # Monitoring desired-state sections: Grafana data sources (config slice),
    # Prometheus scrape config (prometheus.yaml), and VictoriaMetrics Swarm app
    # settings. Each renders its own file; provider logins stay separate.
    grafana_config_store = GrafanaConfigStore(GRAFANA_CONFIG_TFVARS)
    app.config["GRAFANA_CONFIG_STORE"] = grafana_config_store

    prometheus_config_store = PrometheusConfigStore(PROMETHEUS_YAML)
    app.config["PROMETHEUS_CONFIG_STORE"] = prometheus_config_store

    victoriametrics_config_store = VictoriaMetricsConfigStore(
        VICTORIAMETRICS_APP_TFVARS
    )
    app.config["VICTORIAMETRICS_CONFIG_STORE"] = victoriametrics_config_store

    # Vault KV desired state (mount path + secrets) under the Storage section.
    vault_config_store = VaultConfigStore(VAULT_CONFIG_TFVARS)
    app.config["VAULT_CONFIG_STORE"] = vault_config_store

    # Packer build defaults consumed by packer/packer.sh and
    # packer/pipeline/packer.sh (CLI flags still override). Renders the Packer
    # build var-file under .config/packer.
    packer_store = PackerConfigStore(PACKER_BUILD_PKRVARS)
    app.config["PACKER_STORE"] = packer_store

    socketio.init_app(app, cors_allowed_origins="*", async_mode="threading")

    @socketio.on("connect")
    def _hello():  # noqa: ANN202 - Socket.IO handler
        # Tell the freshly connected client which server instance it reached, so
        # it can auto-refresh after a hot reload (new BOOT_ID).
        emit("server:hello", {"boot_id": BOOT_ID})

    from homelab_config.api.swarm import bp as swarm_bp
    from homelab_config.api.ssh import bp as ssh_bp
    from homelab_config.api.nfs import bp as nfs_bp
    from homelab_config.api.minio import bp as minio_bp
    from homelab_config.api.terraform import bp as terraform_bp
    from homelab_config.api.proxmox import bp as proxmox_bp
    from homelab_config.api.proxmox_cluster import bp as proxmox_cluster_bp
    from homelab_config.api.talos import bp as talos_bp
    from homelab_config.api.jenkins import bp as jenkins_deploy_bp
    from homelab_config.api.cloud_image_repository import bp as cloud_image_repository_bp
    from homelab_config.api.docker import bp as docker_bp
    from homelab_config.api.extra_hosts import bp as extra_hosts_bp
    from homelab_config.api.cloudflare_dns import bp as cloudflare_dns_bp
    from homelab_config.api.fortigate_config import bp as fortigate_config_bp
    from homelab_config.api.npm import bp as npm_bp
    from homelab_config.api.grafana_config import bp as grafana_config_bp
    from homelab_config.api.prometheus_config import bp as prometheus_config_bp
    from homelab_config.api.victoriametrics_config import bp as victoriametrics_config_bp
    from homelab_config.api.vault_config import bp as vault_config_bp
    from homelab_config.api.packer import bp as packer_bp
    from homelab_config.api.providers_generic import make_blueprint

    app.register_blueprint(swarm_bp)
    app.register_blueprint(ssh_bp)
    app.register_blueprint(nfs_bp)
    app.register_blueprint(minio_bp)
    app.register_blueprint(terraform_bp)
    app.register_blueprint(proxmox_bp)
    app.register_blueprint(proxmox_cluster_bp)
    app.register_blueprint(talos_bp)
    app.register_blueprint(jenkins_deploy_bp)
    app.register_blueprint(cloud_image_repository_bp)
    app.register_blueprint(docker_bp)
    app.register_blueprint(extra_hosts_bp)
    app.register_blueprint(cloudflare_dns_bp)
    app.register_blueprint(fortigate_config_bp)
    app.register_blueprint(npm_bp)
    app.register_blueprint(grafana_config_bp)
    app.register_blueprint(prometheus_config_bp)
    app.register_blueprint(victoriametrics_config_bp)
    app.register_blueprint(vault_config_bp)
    app.register_blueprint(packer_bp)
    for spec in PROVIDER_SPECS:
        app.register_blueprint(make_blueprint(spec))

    @app.context_processor
    def _inject_provider_nav():  # noqa: ANN202 - Flask context processor
        return {"provider_nav": [spec.public() for spec in PROVIDER_SPECS]}

    @app.route("/")
    def index():  # noqa: ANN202 - Flask view
        return render_template("ssh.html", active="ssh")

    @app.route("/ssh")
    def ssh_page():  # noqa: ANN202 - Flask view
        return render_template("ssh.html", active="ssh")

    @app.route("/swarm")
    def swarm_page():  # noqa: ANN202 - Flask view
        return render_template("swarm.html", active="swarm")

    @app.route("/nfs")
    def nfs_page():  # noqa: ANN202 - Flask view
        return render_template("nfs.html", active="nfs")

    @app.route("/minio")
    def minio_page():  # noqa: ANN202 - Flask view
        return render_template("minio.html", active="minio")

    @app.route("/terraform")
    def terraform_page():  # noqa: ANN202 - Flask view
        return render_template("terraform.html", active="terraform")

    @app.route("/proxmox")
    def proxmox_page():  # noqa: ANN202 - Flask view
        return render_template("proxmox.html", active="proxmox")

    @app.route("/proxmox-vms")
    def proxmox_vms_page():  # noqa: ANN202 - Flask view
        return render_template("proxmox_vms.html", active="proxmox-vms")

    @app.route("/talos")
    def talos_page():  # noqa: ANN202 - Flask view
        return render_template("talos.html", active="talos")

    @app.route("/cicd/jenkins")
    def cicd_jenkins_page():  # noqa: ANN202 - Flask view
        return render_template("jenkins.html", active="cicd-jenkins")

    @app.route("/docker")
    def docker_page():  # noqa: ANN202 - Flask view
        return render_template("docker.html", active="docker")

    @app.route("/cloud-image-repository")
    def cloud_image_repository_page():  # noqa: ANN202 - Flask view
        return render_template(
            "cloud_image_repository.html", active="cloud-image-repository"
        )

    @app.route("/extra-hosts")
    def extra_hosts_page():  # noqa: ANN202 - Flask view
        return render_template("extra_hosts.html", active="extra-hosts")

    @app.route("/network/fortigate")
    def network_fortigate_page():  # noqa: ANN202 - Flask view
        return render_template(
            "network_fortigate.html", active="network-fortigate"
        )

    @app.route("/network/npm")
    def network_npm_page():  # noqa: ANN202 - Flask view
        return render_template("network_npm.html", active="network-npm")

    @app.route("/remote/cloudflare")
    def remote_cloudflare_page():  # noqa: ANN202 - Flask view
        return render_template(
            "remote_cloudflare.html", active="remote-cloudflare"
        )

    @app.route("/monitoring/grafana")
    def monitoring_grafana_page():  # noqa: ANN202 - Flask view
        return render_template("monitoring_grafana.html", active="monitoring-grafana")

    @app.route("/monitoring/prometheus")
    def monitoring_prometheus_page():  # noqa: ANN202 - Flask view
        return render_template(
            "monitoring_prometheus.html", active="monitoring-prometheus"
        )

    @app.route("/monitoring/victoriametrics")
    def monitoring_victoriametrics_page():  # noqa: ANN202 - Flask view
        return render_template(
            "monitoring_victoriametrics.html", active="monitoring-victoriametrics"
        )

    @app.route("/storage/vault")
    def storage_vault_page():  # noqa: ANN202 - Flask view
        return render_template("storage_vault.html", active="storage-vault")

    @app.route("/packer")
    def packer_page():  # noqa: ANN202 - Flask view
        return render_template("packer.html", active="packer")

    def _make_provider_page(spec):  # noqa: ANN202 - view factory
        public = spec.public()

        def _view():  # noqa: ANN202 - Flask view
            return render_template(
                "provider_generic.html", provider=public, active=spec.key
            )

        return _view

    for spec in PROVIDER_SPECS:
        app.add_url_rule(
            f"/{spec.key}",
            endpoint=f"provider_page_{spec.key}",
            view_func=_make_provider_page(spec),
        )

    return app


class _JenkinsSliceWatch:
    """Adapt one Jenkins slice to the drift watcher's ``.status()`` shape."""

    def __init__(self, store: JenkinsStore, key: str) -> None:
        self._store = store
        self._key = key

    def status(self) -> dict:
        return self._store.status(self._key)


def _start_drift_watch(
    store: SwarmStore,
    nfs_store: NfsStore,
    minio_store: MinioStore,
    terraform_store: TerraformStore,
    proxmox_store: ProxmoxStore,
    proxmox_cluster_store: ProxmoxClusterStore,
    talos_store: TalosStore,
    jenkins_store: JenkinsStore,
    docker_store: DockerProvidersStore,
    cloud_image_repository_store: CloudImageRepositoryStore,
    provider_stores: dict,
    cloudflare_dns_store: CloudflareDnsStore,
    fortigate_config_store: FortigateConfigStore,
    npm_config_store: NpmConfigStore,
    grafana_config_store: GrafanaConfigStore,
    prometheus_config_store: PrometheusConfigStore,
    victoriametrics_config_store: VictoriaMetricsConfigStore,
    vault_config_store: VaultConfigStore,
    packer_store: PackerConfigStore,
) -> None:
    """Poll managed files and broadcast status when out-of-band changes appear."""
    from homelab_config.api.swarm import EVENT_STATUS as SWARM_STATUS
    from homelab_config.api.nfs import EVENT_STATUS as NFS_STATUS
    from homelab_config.api.minio import EVENT_STATUS as MINIO_STATUS
    from homelab_config.api.terraform import EVENT_STATUS as TERRAFORM_STATUS
    from homelab_config.api.terraform import broadcast as terraform_broadcast
    from homelab_config.api.proxmox import EVENT_STATUS as PROXMOX_STATUS
    from homelab_config.api.proxmox_cluster import EVENT_STATUS as PROXMOX_VMS_STATUS
    from homelab_config.api.talos import EVENT_STATUS as TALOS_STATUS
    from homelab_config.api.jenkins import status_event as jenkins_status_event
    from homelab_config.jenkins_config import SLICE_KEYS as JENKINS_SLICE_KEYS
    from homelab_config.api.cloud_image_repository import (
        EVENT_STATUS as CLOUD_IMAGE_REPOSITORY_STATUS,
    )
    from homelab_config.api.docker import EVENT_STATUS as DOCKER_STATUS
    from homelab_config.api.docker import broadcast as docker_broadcast
    from homelab_config.api.cloudflare_dns import EVENT_STATUS as CLOUDFLARE_STATUS
    from homelab_config.api.fortigate_config import EVENT_STATUS as FORTIGATE_STATUS
    from homelab_config.api.npm import EVENT_STATUS as NPM_STATUS
    from homelab_config.api.grafana_config import EVENT_STATUS as GRAFANA_STATUS
    from homelab_config.api.prometheus_config import EVENT_STATUS as PROMETHEUS_STATUS
    from homelab_config.api.victoriametrics_config import (
        EVENT_STATUS as VICTORIAMETRICS_STATUS,
    )
    from homelab_config.api.vault_config import EVENT_STATUS as VAULT_STATUS
    from homelab_config.api.packer import EVENT_STATUS as PACKER_STATUS
    from homelab_config.minio_config import canonical as minio_canonical
    from homelab_config.minio_config import read_minio_tfvars
    from homelab_config.swarm_config import canonical as swarm_canonical
    from homelab_config.swarm_config import read_swarm_tfvars

    watched = (
        (store, SWARM_STATUS),
        (nfs_store, NFS_STATUS),
        (minio_store, MINIO_STATUS),
        (terraform_store, TERRAFORM_STATUS),
        (proxmox_store, PROXMOX_STATUS),
        (proxmox_cluster_store, PROXMOX_VMS_STATUS),
        (talos_store, TALOS_STATUS),
        (docker_store, DOCKER_STATUS),
        (cloud_image_repository_store, CLOUD_IMAGE_REPOSITORY_STATUS),
        (cloudflare_dns_store, CLOUDFLARE_STATUS),
        (fortigate_config_store, FORTIGATE_STATUS),
        (npm_config_store, NPM_STATUS),
        (grafana_config_store, GRAFANA_STATUS),
        (prometheus_config_store, PROMETHEUS_STATUS),
        (victoriametrics_config_store, VICTORIAMETRICS_STATUS),
        (vault_config_store, VAULT_STATUS),
        (packer_store, PACKER_STATUS),
    ) + tuple(
        (provider_stores[spec.key], spec.status_event) for spec in PROVIDER_SPECS
    ) + tuple(
        # One watch entry per Jenkins slice; the store needs the slice key, so
        # wrap each in a tiny status() adapter matching the (target, event) shape.
        (_JenkinsSliceWatch(jenkins_store, key), jenkins_status_event(key))
        for key in JENKINS_SLICE_KEYS
    )

    def _swarm_fingerprint() -> object:
        try:
            return swarm_canonical(read_swarm_tfvars(SWARM_TFVARS) or [])
        except Exception:  # noqa: BLE001 - never let the watcher die
            return None

    def _minio_fingerprint() -> object:
        try:
            return minio_canonical(read_minio_tfvars(MINIO_TFVARS) or [])
        except Exception:  # noqa: BLE001 - never let the watcher die
            return None

    def _watch() -> None:
        last: dict[str, object] = {}
        last_swarm = _swarm_fingerprint()
        last_minio = _minio_fingerprint()
        while True:
            time.sleep(_DRIFT_POLL_SECONDS)
            for target, event in watched:
                try:
                    status = target.status()
                except Exception:  # noqa: BLE001 - never let the watcher die
                    continue
                fingerprint = (
                    status["dirty"],
                    status["external_change"],
                    status["disk_present"],
                )
                if fingerprint != last.get(event):
                    last[event] = fingerprint
                    socketio.emit(event, status)

            # Docker providers are partly derived from swarm.tfvars: when the swarm
            # topology changes, re-render the derived portion and re-broadcast.
            current_swarm = _swarm_fingerprint()
            if current_swarm != last_swarm:
                last_swarm = current_swarm
                try:
                    docker_status = docker_store.status()
                    if not docker_status["dirty"] and not docker_status["external_change"]:
                        docker_store.refresh_derived()
                    docker_broadcast(docker_store)
                except Exception:  # noqa: BLE001 - never let the watcher die
                    pass

            # The Terraform S3 backend is derived from the selected MinIO's
            # connection details: when the MinIO catalog changes, re-render the
            # backend (only rewrites when configured) and re-broadcast Terraform.
            current_minio = _minio_fingerprint()
            if current_minio != last_minio:
                last_minio = current_minio
                try:
                    terraform_store.refresh_backend()
                    terraform_broadcast(terraform_store)
                except Exception:  # noqa: BLE001 - never let the watcher die
                    pass

    thread = threading.Thread(target=_watch, name="homelab-config-drift", daemon=True)
    thread.start()


# --- single-instance / restart-on-launch -----------------------------------


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _read_pidfile() -> int | None:
    try:
        text = PID_FILE.read_text(encoding="utf-8").strip()
    except (FileNotFoundError, OSError):
        return None
    try:
        return int(text)
    except ValueError:
        return None


def _process_is_homelab_config(pid: int) -> bool:
    try:
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes()
    except (FileNotFoundError, OSError):
        return True
    text = cmdline.replace(b"\x00", b" ").decode("utf-8", "replace")
    return "config.py" in text or "homelab_config" in text


def _wait_for_exit(pid: int, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not _pid_alive(pid):
            return True
        time.sleep(_POLL_INTERVAL_SECONDS)
    return not _pid_alive(pid)


def _terminate_existing() -> None:
    """Stop a previously launched server so this launch can take over."""
    pid = _read_pidfile()
    if pid is None or pid == os.getpid():
        return
    if not _pid_alive(pid) or not _process_is_homelab_config(pid):
        return

    logger.warning("homelab-config already running (pid %d); restarting it", pid)
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    if _wait_for_exit(pid, _TERM_WAIT_SECONDS):
        logger.info("Previous homelab-config instance (pid %d) stopped", pid)
        return

    logger.warning("pid %d did not exit after SIGTERM; sending SIGKILL", pid)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    _wait_for_exit(pid, _KILL_WAIT_SECONDS)


def _remove_pidfile() -> None:
    if _read_pidfile() == os.getpid():
        try:
            PID_FILE.unlink()
        except FileNotFoundError:
            pass


def _write_pidfile() -> None:
    PID_FILE.parent.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(os.getpid()), encoding="utf-8")
    atexit.register(_remove_pidfile)


def _handle_sigterm(signum, frame) -> None:  # noqa: ANN001 - signal handler
    """Raise SystemExit on SIGTERM so atexit cleanup (pidfile) runs."""
    raise SystemExit(0)


def run_server() -> int:
    """Run the homelab-config web server.

    Honors ``HOMELAB_CONFIG_HOST`` and ``HOMELAB_CONFIG_PORT`` overrides.

    Returns:
        Process exit code.
    """
    # On a hot reload the process re-execs in place (same PID), so the pidfile
    # already points at us; only stop a distinct prior instance on a fresh launch.
    _terminate_existing()
    _write_pidfile()
    signal.signal(signal.SIGTERM, _handle_sigterm)

    if os.environ.get("HOMELAB_CONFIG_RELOAD", "1") != "0":
        start_reloader([APP_DIR])

    app = create_app()
    _start_drift_watch(
        app.config["SWARM_STORE"],
        app.config["NFS_STORE"],
        app.config["MINIO_STORE"],
        app.config["TERRAFORM_STORE"],
        app.config["PROXMOX_STORE"],
        app.config["PROXMOX_CLUSTER_STORE"],
        app.config["TALOS_STORE"],
        app.config["JENKINS_STORE"],
        app.config["DOCKER_STORE"],
        app.config["CLOUD_IMAGE_REPOSITORY_STORE"],
        app.config["PROVIDER_STORES"],
        app.config["CLOUDFLARE_DNS_STORE"],
        app.config["FORTIGATE_CONFIG_STORE"],
        app.config["NPM_CONFIG_STORE"],
        app.config["GRAFANA_CONFIG_STORE"],
        app.config["PROMETHEUS_CONFIG_STORE"],
        app.config["VICTORIAMETRICS_CONFIG_STORE"],
        app.config["VAULT_CONFIG_STORE"],
        app.config["PACKER_STORE"],
    )

    host = os.environ.get("HOMELAB_CONFIG_HOST", DEFAULT_HOST)
    port = int(os.environ.get("HOMELAB_CONFIG_PORT", str(DEFAULT_PORT)))
    logger.info("homelab-config listening on http://%s:%d", host, port)
    # allow_unsafe_werkzeug lets the bundled dev server run outside debug mode.
    socketio.run(app, host=host, port=port, allow_unsafe_werkzeug=True)
    return 0


__all__ = ["create_app", "run_server"]
