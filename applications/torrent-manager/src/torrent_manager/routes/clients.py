"""qBittorrent client status pages."""

from __future__ import annotations

from flask import Blueprint, current_app, render_template

from torrent_manager.services.qbittorrent import QBitTorrentRegistry

clients_bp = Blueprint("clients", __name__, url_prefix="/clients")


def _registry() -> QBitTorrentRegistry:
    return current_app.extensions["qbittorrent_registry"]


@clients_bp.get("/")
def list_clients():
    """Show configured qBittorrent clients and live connectivity."""
    statuses = _registry().all_statuses()
    return render_template("clients/list.html", clients=statuses)
