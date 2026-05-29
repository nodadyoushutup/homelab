"""Health and readiness endpoints."""

from __future__ import annotations

from flask import Blueprint, current_app, jsonify

from torrent_manager.services.qbittorrent import QBitTorrentRegistry

health_bp = Blueprint("health", __name__)


def _registry() -> QBitTorrentRegistry:
    return current_app.extensions["qbittorrent_registry"]


@health_bp.get("/healthz")
def healthz():
    """Liveness probe."""
    return jsonify({"status": "ok"})


@health_bp.get("/healthz/qbittorrent")
def healthz_qbittorrent():
    """Readiness-style probe for configured qBittorrent clients."""
    statuses = _registry().all_statuses()
    if not statuses:
        overall = "ok"
    elif all(item.connected for item in statuses):
        overall = "ok"
    else:
        overall = "degraded"

    payload = {
        "status": overall,
        "clients": [
            {
                "id": item.client_id,
                "base_url": item.base_url,
                "connected": item.connected,
                "version": item.version,
                "error": item.error,
            }
            for item in statuses
        ],
    }
    code = 200 if overall == "ok" else 503
    return jsonify(payload), code
