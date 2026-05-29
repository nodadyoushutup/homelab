"""Abstract foundations for persisted and in-memory domain objects."""

from __future__ import annotations

from abc import ABC, abstractmethod
from datetime import datetime, timezone
from typing import Any, Self
from uuid import uuid4

from sqlalchemy import DateTime, func
from sqlalchemy.orm import Mapped, mapped_column

from torrent_manager.extensions import db


def utcnow() -> datetime:
    """Return the current UTC time as a timezone-aware datetime."""
    return datetime.now(timezone.utc)


class BaseRecord(ABC):
    """In-memory object with the same identity and audit fields as :class:`BaseModel`.

    Subclass this when you need shared serialization and timestamp behavior without
    SQLAlchemy persistence — for example API DTOs built from external torrent clients.
    """

    def __init__(self, *, record_id: str | None = None) -> None:
        self.id: str = record_id or str(uuid4())
        now = utcnow()
        self.created_at = now
        self.updated_at = now

    def touch(self) -> None:
        """Mark the object as recently updated."""
        self.updated_at = utcnow()

    @abstractmethod
    def to_dict(self) -> dict[str, Any]:
        """Serialize the object to a JSON-friendly mapping."""

    def update_from_dict(
        self,
        data: dict[str, Any],
        *,
        exclude: frozenset[str] | set[str] = frozenset({"id", "created_at", "updated_at"}),
    ) -> Self:
        """Apply mapping values onto attributes, skipping protected keys."""
        for key, value in data.items():
            if key in exclude:
                continue
            if hasattr(self, key):
                setattr(self, key, value)
        self.touch()
        return self

    def __repr__(self) -> str:
        return f"<{self.__class__.__name__} id={self.id!r}>"


class BaseModel(db.Model):
    """Abstract SQLAlchemy model providing primary key and audit timestamps.

    Every concrete table model should inherit either :class:`CRUDModel` (when it needs
    database CRUD helpers) or this class directly (when it only needs columns and
    serialization without the generic query helpers).
    """

    __abstract__ = True

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utcnow,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utcnow,
        onupdate=utcnow,
        server_default=func.now(),
    )

    def touch(self) -> None:
        """Refresh ``updated_at`` before persistence."""
        self.updated_at = utcnow()

    def to_dict(self) -> dict[str, Any]:
        """Serialize mapped columns to a JSON-friendly mapping."""
        return {
            column.key: getattr(self, column.key)
            for column in self.__table__.columns  # type: ignore[attr-defined]
        }

    def update_from_dict(
        self,
        data: dict[str, Any],
        *,
        exclude: frozenset[str] | set[str] = frozenset({"id", "created_at", "updated_at"}),
    ) -> Self:
        """Apply mapping values onto mapped columns, skipping protected keys."""
        for key, value in data.items():
            if key in exclude:
                continue
            if hasattr(self, key):
                setattr(self, key, value)
        return self

    def __repr__(self) -> str:
        return f"<{self.__class__.__name__} id={self.id!r}>"
