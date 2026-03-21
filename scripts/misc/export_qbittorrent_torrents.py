#!/usr/bin/env python3
"""
Export all torrents from a qBittorrent client to .torrent files on disk.

Set BASE_URLS below, then run:
    python3 scripts/misc/export_qbittorrent_torrents.py
"""
from __future__ import annotations

import json
import re
import ssl
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib import error, parse, request


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
REPO_DIR = Path(__file__).resolve().parents[2]
BASE_URLS = ["http://192.168.1.100:10895"]
USERNAME = "admin"
PASSWORD = "S#nvhs89vher"
OUTPUT_DIR = REPO_DIR / "exports"
TIMEOUT_SECONDS = 20
OVERWRITE_EXISTING = False
INSECURE_TLS = False
TAG_FILTER: str | None = None  # Example: "movies"
DATE_FROM: str | None = None  # Inclusive, format YYYY-MM-DD
DATE_TO: str | None = None  # Inclusive, format YYYY-MM-DD
DATE_SORT_ORDER: str | None = "asc"  # "asc"=oldest->newest, "desc"=newest->oldest, None=preserve API order
EXPORT_LIMIT: int | None = None  # Example: 10
BATCH_SIZE: int | None = None  # Example: 100 (creates batch subdirectories)


def safe_filename(name: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._ -]+", "_", name).strip()
    cleaned = re.sub(r"\s+", "_", cleaned)
    return cleaned or "torrent"


def normalize_base_url(value: str) -> str:
    cleaned = value.strip()
    if not cleaned:
        raise RuntimeError("Host value cannot be empty.")
    if "://" not in cleaned:
        cleaned = f"http://{cleaned}"
    return cleaned.rstrip("/")


def parse_host_values(host_values: list[str]) -> list[str]:
    if not host_values:
        raise RuntimeError("BASE_URLS must include at least one host.")

    parsed_hosts: list[str] = []
    seen: set[str] = set()
    for raw in host_values:
        for part in raw.split(","):
            base_url = normalize_base_url(part)
            if base_url in seen:
                continue
            seen.add(base_url)
            parsed_hosts.append(base_url)
    if not parsed_hosts:
        raise RuntimeError("No valid BASE_URLS values were provided.")
    return parsed_hosts


def base_url_slug(base_url: str) -> str:
    normalized = normalize_base_url(base_url)
    return safe_filename(normalized.replace("://", "_").replace(":", "_"))


def host_output_dir(base_output_dir: Path, base_url: str, multi_host: bool) -> Path:
    if not multi_host:
        return base_output_dir
    parsed = parse.urlsplit(base_url)
    host_part = parsed.netloc or parsed.path
    return base_output_dir / safe_filename(host_part.replace(":", "_"))


def batch_folder_name(base_url: str, batch_number: int, batch_start: int, batch_end: int) -> str:
    return (
        f"batch_{base_url_slug(base_url)}_{batch_number:04d}_{batch_start:04d}-{batch_end:04d}"
    )


class QBClient:
    def __init__(self, base_url: str, timeout: int, insecure: bool = False) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        context: ssl.SSLContext | None = None
        if insecure:
            context = ssl.create_default_context()
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
        handlers: list[Any] = [request.HTTPCookieProcessor()]
        if context is not None:
            handlers.append(request.HTTPSHandler(context=context))
        self.opener = request.build_opener(*handlers)

    def _url(self, path: str) -> str:
        return f"{self.base_url}{path}"

    def post_form(self, path: str, form_data: dict[str, str]) -> bytes:
        data = parse.urlencode(form_data).encode("utf-8")
        req = request.Request(self._url(path), data=data, method="POST")
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
        with self.opener.open(req, timeout=self.timeout) as resp:
            return resp.read()

    def get(self, path: str, query: dict[str, str] | None = None) -> bytes:
        url = self._url(path)
        if query:
            url = f"{url}?{parse.urlencode(query)}"
        req = request.Request(url, method="GET")
        with self.opener.open(req, timeout=self.timeout) as resp:
            return resp.read()

    def login(self, username: str, password: str) -> None:
        body = self.post_form("/api/v2/auth/login", {"username": username, "password": password})
        result = body.decode("utf-8", errors="replace").strip()
        if result != "Ok.":
            raise RuntimeError(f"qBittorrent login failed: {result}")

    def list_torrents(self, tag: str | None = None) -> list[dict[str, Any]]:
        query = {"tag": tag} if tag else None
        body = self.get("/api/v2/torrents/info", query=query)
        decoded = json.loads(body.decode("utf-8"))
        if not isinstance(decoded, list):
            raise RuntimeError("Unexpected torrents/info response format.")
        return decoded

    def export_torrent(self, torrent_hash: str) -> bytes:
        return self.get("/api/v2/torrents/export", {"hash": torrent_hash})


def parse_yyyy_mm_dd(value: str, field_name: str) -> datetime:
    try:
        return datetime.strptime(value, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    except ValueError as exc:
        raise RuntimeError(f"Invalid {field_name} value '{value}'. Expected YYYY-MM-DD.") from exc


def parse_date_window(date_from: str | None, date_to: str | None) -> tuple[int | None, int | None]:
    start_epoch: int | None = None
    end_epoch: int | None = None
    if date_from:
        start_epoch = int(parse_yyyy_mm_dd(date_from, "DATE_FROM").timestamp())
    if date_to:
        # Inclusive end-of-day boundary in UTC.
        end_epoch = int((parse_yyyy_mm_dd(date_to, "DATE_TO") + timedelta(days=1)).timestamp()) - 1
    if start_epoch is not None and end_epoch is not None and start_epoch > end_epoch:
        raise RuntimeError("DATE_FROM must be less than or equal to DATE_TO.")
    return start_epoch, end_epoch


def parse_sort_order(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = value.strip().lower()
    if normalized in ("asc", "desc"):
        return normalized
    raise RuntimeError("Invalid DATE_SORT_ORDER. Use 'asc', 'desc', or None.")


def parse_export_limit(value: int | None) -> int | None:
    if value is None:
        return None
    if value <= 0:
        raise RuntimeError("EXPORT_LIMIT must be greater than 0 when set.")
    return value


def parse_batch_size(value: int | None) -> int | None:
    if value is None:
        return None
    if value <= 0:
        raise RuntimeError("BATCH_SIZE must be greater than 0 when set.")
    return value


def torrent_has_tag(item: dict[str, Any], tag: str) -> bool:
    tags_raw = str(item.get("tags", "")).strip()
    if not tags_raw:
        return False
    tags = {part.strip() for part in tags_raw.split(",") if part.strip()}
    return tag in tags


def torrent_added_on(item: dict[str, Any]) -> int | None:
    value = item.get("added_on")
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str) and value.strip().isdigit():
        return int(value.strip())
    return None


def select_torrents(
    torrents: list[dict[str, Any]],
    tag_filter: str | None,
    start_epoch: int | None,
    end_epoch: int | None,
) -> list[dict[str, Any]]:
    selected: list[dict[str, Any]] = []
    for item in torrents:
        if tag_filter and not torrent_has_tag(item, tag_filter):
            continue
        added_on = torrent_added_on(item)
        if start_epoch is not None and (added_on is None or added_on < start_epoch):
            continue
        if end_epoch is not None and (added_on is None or added_on > end_epoch):
            continue
        selected.append(item)
    return selected


def sort_and_limit_torrents(
    torrents: list[dict[str, Any]],
    sort_order: str | None,
    limit: int | None,
) -> list[dict[str, Any]]:
    ordered = torrents
    if sort_order:
        with_added = [item for item in torrents if torrent_added_on(item) is not None]
        without_added = [item for item in torrents if torrent_added_on(item) is None]
        with_added.sort(key=lambda item: int(torrent_added_on(item) or 0), reverse=(sort_order == "desc"))
        ordered = with_added + without_added
    if limit is not None:
        ordered = ordered[:limit]
    return ordered


def export_selected_torrents(
    client: QBClient,
    selected_torrents: list[dict[str, Any]],
    base_url: str,
    output_dir: Path,
    batch_size: int | None,
) -> tuple[int, int, int, bool]:
    written = 0
    skipped = 0
    failed = 0
    interrupted = False

    total = len(selected_torrents)
    total_batches = ((total + batch_size - 1) // batch_size) if batch_size else 0
    single_batch_dir: Path | None = None
    if batch_size:
        print(f"[INFO] Batching enabled: {total_batches} batch(es) of up to {batch_size} torrent(s)")
    else:
        # Keep non-batched exports under a single batch-like folder so exports always
        # land in a directory and downstream consumers can treat both modes uniformly.
        single_batch_dir = output_dir / batch_folder_name(
            base_url=base_url,
            batch_number=0,
            batch_start=0,
            batch_end=max(total - 1, 0),
        )
        single_batch_dir.mkdir(parents=True, exist_ok=True)
        print(f"[INFO] Batching disabled: writing to {single_batch_dir.name}")

    try:
        for index, item in enumerate(selected_torrents, start=1):
            torrent_hash = str(item.get("hash", "")).strip()
            name = str(item.get("name", "")).strip() or torrent_hash
            batch_dir = single_batch_dir if single_batch_dir else output_dir
            batch_note = ""
            if batch_size:
                # Use zero-based batch indexing so the first batch is 0000.
                batch_number = (index - 1) // batch_size
                batch_start = batch_number * batch_size
                batch_end = min(((batch_number + 1) * batch_size) - 1, total - 1)
                batch_dir = output_dir / batch_folder_name(
                    base_url=base_url,
                    batch_number=batch_number,
                    batch_start=batch_start,
                    batch_end=batch_end,
                )
                batch_dir.mkdir(parents=True, exist_ok=True)
                batch_note = f" [batch {batch_number:04d}/{max(total_batches - 1, 0):04d}]"

            print(f"[ITEM {index}/{total}]{batch_note} {name} ({torrent_hash or 'missing-hash'})")
            if not torrent_hash:
                failed += 1
                print(f"[WARN] Skipping torrent with missing hash: {name}", file=sys.stderr)
                continue

            filename = f"{safe_filename(name)}__{torrent_hash}.torrent"
            destination = batch_dir / filename

            if destination.exists() and not OVERWRITE_EXISTING:
                skipped += 1
                print(f"[SKIP] {destination.name} (already exists)")
                continue

            try:
                torrent_blob = client.export_torrent(torrent_hash)
                if not torrent_blob:
                    raise RuntimeError("empty export payload")
                destination.write_bytes(torrent_blob)
                written += 1
                print(f"[OK] {destination.name}")
            except (error.HTTPError, error.URLError, OSError, RuntimeError) as exc:
                failed += 1
                print(f"[WARN] Failed export for {name} ({torrent_hash}): {exc}", file=sys.stderr)
    except KeyboardInterrupt:
        interrupted = True
        print("\n[WARN] Ctrl+C received. Stopping export gracefully...", file=sys.stderr)

    return written, skipped, failed, interrupted


def main() -> int:
    if not PASSWORD:
        print(
            "[ERROR] Missing qBittorrent password. Set PASSWORD at the top of this script.",
            file=sys.stderr,
        )
        return 2

    base_output_dir = Path(OUTPUT_DIR).expanduser().resolve()
    base_output_dir.mkdir(parents=True, exist_ok=True)

    try:
        hosts = parse_host_values(BASE_URLS)
        start_epoch, end_epoch = parse_date_window(DATE_FROM, DATE_TO)
        sort_order = parse_sort_order(DATE_SORT_ORDER)
        export_limit = parse_export_limit(EXPORT_LIMIT)
        batch_size = parse_batch_size(BATCH_SIZE)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2

    print(
        "[INFO] Export selection:"
        f" hosts={len(hosts)}"
        f" tag={TAG_FILTER if TAG_FILTER else 'any'}"
        f" date_from={DATE_FROM if DATE_FROM else 'none'}"
        f" date_to={DATE_TO if DATE_TO else 'none'}"
        f" date_sort={sort_order if sort_order else 'api'}"
        f" limit={export_limit if export_limit is not None else 'none'}"
        f" batch_size={batch_size if batch_size is not None else 'none'}"
    )

    overall_written = 0
    overall_skipped = 0
    overall_failed = 0
    overall_selected = 0
    host_failures = 0
    interrupted = False

    for host_index, host in enumerate(hosts, start=1):
        host_dir = host_output_dir(base_output_dir, host, multi_host=(len(hosts) > 1))
        host_dir.mkdir(parents=True, exist_ok=True)
        print(f"[HOST {host_index}/{len(hosts)}] {host} -> {host_dir}")

        client = QBClient(host, timeout=TIMEOUT_SECONDS, insecure=INSECURE_TLS)
        try:
            client.login(USERNAME, PASSWORD)
            print(f"[INFO] Connected to qBittorrent at {host} as {USERNAME}")
            torrents = client.list_torrents(tag=TAG_FILTER)
        except (error.HTTPError, error.URLError, RuntimeError, json.JSONDecodeError) as exc:
            host_failures += 1
            overall_failed += 1
            print(f"[ERROR] Failed to connect/list on {host}: {exc}", file=sys.stderr)
            continue

        filtered_torrents = select_torrents(torrents, TAG_FILTER, start_epoch, end_epoch)
        selected_torrents = sort_and_limit_torrents(filtered_torrents, sort_order, export_limit)
        overall_selected += len(selected_torrents)
        print(
            f"[INFO] Beginning export job for {host}: selected={len(selected_torrents)} "
            f"(from {len(filtered_torrents)} filtered, {len(torrents)} fetched)"
        )

        written, skipped, failed, host_interrupted = export_selected_torrents(
            client=client,
            selected_torrents=selected_torrents,
            base_url=host,
            output_dir=host_dir,
            batch_size=batch_size,
        )
        overall_written += written
        overall_skipped += skipped
        overall_failed += failed
        if host_interrupted:
            interrupted = True
            break

    print(
        f"[INFO] Completed export: written={overall_written} skipped={overall_skipped} "
        f"failed={overall_failed} total_selected={overall_selected} host_failures={host_failures}"
    )
    if interrupted:
        return 130
    return 0 if overall_failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
