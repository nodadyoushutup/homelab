"""qBittorrent registry tests."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1] / "src"
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from torrent_manager.qbittorrent_settings import QBitTorrentClientConfig  # noqa: E402
from torrent_manager.services.qbittorrent.registry import QBitTorrentRegistry  # noqa: E402
from torrent_manager.services.qbittorrent.client import QBitTorrentError  # noqa: E402


class QBitTorrentRegistryTests(unittest.TestCase):
    def test_all_statuses_reports_connected_clients(self) -> None:
        configs = (
            QBitTorrentClientConfig(
                client_id="movie_0",
                base_url="http://movie-0:8080",
                username="admin",
                password="secret",
            ),
            QBitTorrentClientConfig(
                client_id="television_1",
                base_url="http://tv-1:8080",
                username="admin",
                password="secret",
            ),
        )
        registry = QBitTorrentRegistry(configs)

        with mock.patch(
            "torrent_manager.services.qbittorrent.client.QBitTorrentClient.ping",
            side_effect=["v4.6.0", QBitTorrentError("offline")],
        ):
            statuses = registry.all_statuses()

        self.assertEqual(len(statuses), 2)
        self.assertTrue(statuses[0].connected)
        self.assertEqual(statuses[0].version, "v4.6.0")
        self.assertFalse(statuses[1].connected)
        self.assertIn("offline", statuses[1].error or "")


if __name__ == "__main__":
    unittest.main()
