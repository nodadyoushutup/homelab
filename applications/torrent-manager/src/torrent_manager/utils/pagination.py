"""Simple offset pagination for list views."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, TypeVar

from torrent_manager.models.crud import CRUDModel

ModelT = TypeVar("ModelT", bound=CRUDModel)

DEFAULT_PAGE_SIZE = 20


@dataclass(frozen=True, slots=True)
class Page:
    """Pagination metadata and the current page of rows."""

    items: list[Any]
    page: int
    per_page: int
    total: int
    total_pages: int

    @property
    def has_prev(self) -> bool:
        return self.page > 1

    @property
    def has_next(self) -> bool:
        return self.page < self.total_pages

    @property
    def prev_page(self) -> int:
        return max(1, self.page - 1)

    @property
    def next_page(self) -> int:
        return min(self.total_pages, self.page + 1)


def paginate(
    model: type[ModelT],
    *,
    page: int = 1,
    per_page: int = DEFAULT_PAGE_SIZE,
    order_by: Any | None = None,
) -> Page:
    """Return one page of rows plus pagination metadata."""
    page = max(1, page)
    per_page = max(1, per_page)
    total = model.count()
    total_pages = max(1, (total + per_page - 1) // per_page)
    if page > total_pages:
        page = total_pages
    offset = (page - 1) * per_page
    items = model.list_all(order_by=order_by, limit=per_page, offset=offset)
    return Page(
        items=items,
        page=page,
        per_page=per_page,
        total=total,
        total_pages=total_pages,
    )
