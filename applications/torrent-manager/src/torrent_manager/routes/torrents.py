"""Torrent CRUD pages and form handling."""

from __future__ import annotations

from flask import Blueprint, flash, redirect, render_template, request, url_for

from torrent_manager.models.torrent import Torrent, TorrentStatus

torrents_bp = Blueprint("torrents", __name__, url_prefix="/torrents")

_STATUS_CHOICES = [status.value for status in TorrentStatus]


def _form_fields() -> dict[str, str | int | None]:
    size_raw = (request.form.get("size_bytes") or "").strip()
    size_bytes: int | None = None
    if size_raw:
        size_bytes = int(size_raw)

    return {
        "name": (request.form.get("name") or "").strip(),
        "magnet_uri": (request.form.get("magnet_uri") or "").strip() or None,
        "info_hash": (request.form.get("info_hash") or "").strip() or None,
        "status": (request.form.get("status") or TorrentStatus.QUEUED.value).strip(),
        "size_bytes": size_bytes,
        "notes": (request.form.get("notes") or "").strip() or None,
    }


def _validate_fields(fields: dict[str, str | int | None]) -> list[str]:
    errors: list[str] = []
    if not fields["name"]:
        errors.append("Name is required.")
    if fields["status"] not in _STATUS_CHOICES:
        errors.append("Status is invalid.")
    if not fields["magnet_uri"] and not fields["info_hash"]:
        errors.append("Provide a magnet URI or info hash.")
    return errors


@torrents_bp.get("/")
def list_torrents():
    """List all managed torrents."""
    torrents = Torrent.list_all(order_by=Torrent.created_at.desc())
    return render_template("torrents/list.html", torrents=torrents)


@torrents_bp.route("/new", methods=["GET", "POST"])
def create_torrent():
    """Create a torrent record."""
    if request.method == "GET":
        return render_template(
            "torrents/form.html",
            torrent=None,
            status_choices=_STATUS_CHOICES,
            form_action=url_for("torrents.create_torrent"),
            page_title="Add torrent",
        )

    fields = _form_fields()
    errors = _validate_fields(fields)
    if errors:
        for message in errors:
            flash(message, "error")
        return render_template(
            "torrents/form.html",
            torrent=fields,
            status_choices=_STATUS_CHOICES,
            form_action=url_for("torrents.create_torrent"),
            page_title="Add torrent",
        ), 400

    Torrent.create(**fields)
    flash("Torrent created.", "success")
    return redirect(url_for("torrents.list_torrents"))


@torrents_bp.route("/<int:torrent_id>/edit", methods=["GET", "POST"])
def edit_torrent(torrent_id: int):
    """Update an existing torrent record."""
    torrent = Torrent.get_by_id(torrent_id)
    if torrent is None:
        flash("Torrent not found.", "error")
        return redirect(url_for("torrents.list_torrents"))

    if request.method == "GET":
        return render_template(
            "torrents/form.html",
            torrent=torrent,
            status_choices=_STATUS_CHOICES,
            form_action=url_for("torrents.edit_torrent", torrent_id=torrent.id),
            page_title="Edit torrent",
        )

    fields = _form_fields()
    errors = _validate_fields(fields)
    if errors:
        for message in errors:
            flash(message, "error")
        return render_template(
            "torrents/form.html",
            torrent={**torrent.to_dict(), **fields},
            status_choices=_STATUS_CHOICES,
            form_action=url_for("torrents.edit_torrent", torrent_id=torrent.id),
            page_title="Edit torrent",
        ), 400

    torrent.update_from_dict(fields).save()
    flash("Torrent updated.", "success")
    return redirect(url_for("torrents.list_torrents"))


@torrents_bp.post("/<int:torrent_id>/delete")
def delete_torrent(torrent_id: int):
    """Delete a torrent record."""
    deleted = Torrent.delete_by_id(torrent_id)
    if deleted:
        flash("Torrent deleted.", "success")
    else:
        flash("Torrent not found.", "error")
    return redirect(url_for("torrents.list_torrents"))
