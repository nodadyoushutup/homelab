"""Persisted torrent records tracked by the manager."""

from __future__ import annotations

from enum import StrEnum

from sqlalchemy import String, Text
from sqlalchemy.orm import Mapped, mapped_column

from torrent_manager.models.crud import CRUDModel


class TorrentStatus(StrEnum):
    """Lifecycle states for a managed torrent."""

    QUEUED = "queued"
    DOWNLOADING = "downloading"
    SEEDING = "seeding"
    PAUSED = "paused"
    COMPLETED = "completed"
    ERROR = "error"


class Torrent(CRUDModel):
    """A torrent the manager knows about."""

    __tablename__ = "torrents"

    name: Mapped[str] = mapped_column(String(512), nullable=False)
    magnet_uri: Mapped[str | None] = mapped_column(Text, nullable=True)
    info_hash: Mapped[str | None] = mapped_column(String(64), nullable=True, unique=True)
    status: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=TorrentStatus.QUEUED.value,
    )
    size_bytes: Mapped[int | None] = mapped_column(nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    @property
    def status_enum(self) -> TorrentStatus:
        """Return the status as a :class:`TorrentStatus` enum value."""
        return TorrentStatus(self.status)

    def human_size(self) -> str:
        """Return a short human-readable size label."""
        if self.size_bytes is None:
            return "—"
        size = float(self.size_bytes)
        for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
            if size < 1024.0 or unit == "TiB":
                if unit == "B":
                    return f"{int(size)} {unit}"
                return f"{size:.1f} {unit}"
            size /= 1024.0
        return f"{size:.1f} TiB"
