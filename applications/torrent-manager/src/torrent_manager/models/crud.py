"""Generic CRUD helpers for SQLAlchemy models."""

from __future__ import annotations

from typing import Any, Self

from sqlalchemy import Select, func, select

from torrent_manager.extensions import db
from torrent_manager.models.base import BaseModel


class CRUDModel(BaseModel):
    """Abstract model adding create/read/update/delete helpers on top of :class:`BaseModel`.

    Most persisted domain tables should inherit this class. Models that only need
    custom persistence logic can inherit :class:`BaseModel` directly instead.
    """

    __abstract__ = True

    @classmethod
    def _base_select(cls) -> Select[tuple[Self]]:
        return select(cls)

    @classmethod
    def get_by_id(cls, record_id: int) -> Self | None:
        """Return a row by primary key, or ``None`` when missing."""
        return db.session.get(cls, record_id)

    @classmethod
    def list_all(
        cls,
        *,
        order_by: Any | None = None,
        limit: int | None = None,
        offset: int = 0,
    ) -> list[Self]:
        """Return rows with optional ordering and pagination."""
        stmt = cls._base_select()
        if order_by is not None:
            stmt = stmt.order_by(order_by)
        if offset:
            stmt = stmt.offset(offset)
        if limit is not None:
            stmt = stmt.limit(limit)
        return list(db.session.scalars(stmt))

    @classmethod
    def count(cls) -> int:
        """Return the number of persisted rows for this model."""
        return db.session.scalar(select(func.count()).select_from(cls)) or 0

    @classmethod
    def create(cls, *, commit: bool = True, **fields: Any) -> Self:
        """Construct, persist, and return a new row."""
        instance = cls(**fields)
        db.session.add(instance)
        if commit:
            db.session.commit()
        else:
            db.session.flush()
        return instance

    def save(self, *, commit: bool = True) -> Self:
        """Persist the current row, refreshing ``updated_at`` first."""
        self.touch()
        db.session.add(self)
        if commit:
            db.session.commit()
        else:
            db.session.flush()
        return self

    def delete(self, *, commit: bool = True) -> None:
        """Remove the current row from the database."""
        db.session.delete(self)
        if commit:
            db.session.commit()

    @classmethod
    def delete_by_id(cls, record_id: int, *, commit: bool = True) -> bool:
        """Delete a row by primary key. Returns ``False`` when the row is missing."""
        instance = cls.get_by_id(record_id)
        if instance is None:
            return False
        instance.delete(commit=commit)
        return True
