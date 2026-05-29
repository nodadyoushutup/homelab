"""Registry that manages multiple qBittorrent clients."""

from __future__ import annotations

from dataclasses import dataclass

from torrent_manager.qbittorrent_settings import QBitTorrentClientConfig, client_display_host
from torrent_manager.services.qbittorrent.client import QBitTorrentClient, QBitTorrentError


@dataclass(frozen=True, slots=True)
class QBitTorrentClientStatus:
    """Runtime connectivity status for one configured client."""

    client_id: str
    base_url: str
    display_host: str
    connected: bool
    version: str | None = None
    error: str | None = None


class QBitTorrentRegistry:
    """Holds live client handles for every configured qBittorrent instance."""

    def __init__(self, configs: tuple[QBitTorrentClientConfig, ...]) -> None:
        self._clients: dict[str, QBitTorrentClient] = {
            config.client_id: QBitTorrentClient(config) for config in configs
        }

    @property
    def client_ids(self) -> tuple[str, ...]:
        return tuple(self._clients.keys())

    def get(self, client_id: str) -> QBitTorrentClient:
        """Return a client by id, raising ``KeyError`` when unknown."""
        return self._clients[client_id]

    def connect_all(self) -> tuple[QBitTorrentClientStatus, ...]:
        """Attempt to authenticate every configured client."""
        return tuple(self.status(client_id) for client_id in self.client_ids)

    def status(self, client_id: str) -> QBitTorrentClientStatus:
        """Return connectivity status for one client."""
        client = self.get(client_id)
        try:
            version = client.ping()
            return QBitTorrentClientStatus(
                client_id=client.client_id,
                base_url=client.base_url,
                display_host=client_display_host(client.base_url),
                connected=True,
                version=version,
            )
        except QBitTorrentError as exc:
            return QBitTorrentClientStatus(
                client_id=client.client_id,
                base_url=client.base_url,
                display_host=client_display_host(client.base_url),
                connected=False,
                error=str(exc),
            )

    def all_statuses(self) -> tuple[QBitTorrentClientStatus, ...]:
        """Return connectivity status for every configured client."""
        return tuple(self.status(client_id) for client_id in self.client_ids)
