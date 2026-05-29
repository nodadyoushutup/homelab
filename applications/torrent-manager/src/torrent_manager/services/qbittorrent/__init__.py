"""qBittorrent Web API integration."""

from torrent_manager.services.qbittorrent.client import QBitTorrentClient, QBitTorrentError
from torrent_manager.services.qbittorrent.registry import QBitTorrentClientStatus, QBitTorrentRegistry

__all__ = [
    "QBitTorrentClient",
    "QBitTorrentClientStatus",
    "QBitTorrentError",
    "QBitTorrentRegistry",
]
