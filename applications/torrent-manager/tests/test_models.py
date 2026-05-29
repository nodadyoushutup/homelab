"""Model-layer unit tests."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "src"
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from torrent_manager.app import create_app  # noqa: E402
from torrent_manager.config import load_config  # noqa: E402
from torrent_manager.extensions import db  # noqa: E402
from torrent_manager.models.base import BaseRecord  # noqa: E402
from torrent_manager.models.torrent import Torrent, TorrentStatus  # noqa: E402


class _SampleRecord(BaseRecord):
    def __init__(self, *, label: str, record_id: str | None = None) -> None:
        super().__init__(record_id=record_id)
        self.label = label

    def to_dict(self):
        return {"id": self.id, "label": self.label, "created_at": self.created_at.isoformat()}


class TorrentModelTests(unittest.TestCase):
    def setUp(self) -> None:
        self.app = create_app(
            load_config(testing=True)
        )
        self.ctx = self.app.app_context()
        self.ctx.push()
        db.drop_all()
        db.create_all()

    def tearDown(self) -> None:
        db.session.remove()
        self.ctx.pop()

    def test_crud_round_trip(self) -> None:
        created = Torrent.create(
            name="Example",
            magnet_uri="magnet:?xt=urn:btih:abc",
            status=TorrentStatus.QUEUED.value,
        )
        self.assertIsNotNone(created.id)

        loaded = Torrent.get_by_id(created.id)
        assert loaded is not None
        loaded.status = TorrentStatus.DOWNLOADING.value
        loaded.save()

        rows = Torrent.list_all(order_by=Torrent.name.asc())
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].status_enum, TorrentStatus.DOWNLOADING)

    def test_error_status(self) -> None:
        created = Torrent.create(
            name="Broken torrent",
            magnet_uri="magnet:?xt=urn:btih:deadbeef",
            status=TorrentStatus.ERROR.value,
            notes="Tracker unreachable",
        )

        loaded = Torrent.get_by_id(created.id)
        assert loaded is not None
        self.assertEqual(loaded.status_enum, TorrentStatus.ERROR)
        self.assertEqual(loaded.status, "error")

    def test_delete_by_id(self) -> None:
        created = Torrent.create(name="Temporary", info_hash="deadbeef")
        self.assertTrue(Torrent.delete_by_id(created.id))
        self.assertIsNone(Torrent.get_by_id(created.id))

    def test_base_record_is_in_memory_only(self) -> None:
        record = _SampleRecord(label="dto")
        record.update_from_dict({"label": "updated"})
        payload = record.to_dict()
        self.assertEqual(payload["label"], "updated")
        self.assertIn("id", payload)


if __name__ == "__main__":
    unittest.main()
