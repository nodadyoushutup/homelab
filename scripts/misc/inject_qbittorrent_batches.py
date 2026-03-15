#!/usr/bin/env python3
"""
Inject exported .torrent batch directories into qBittorrent movie-0..movie-8 clients.

Default mapping:
  batch_0000_* -> qbittorrent.movie.0.nodadyoushutup.com
  ...
  batch_0008_* -> qbittorrent.movie.8.nodadyoushutup.com

Usage:
  python3 scripts/misc/inject_qbittorrent_batches.py
"""

from __future__ import annotations

import json
import re
import ssl
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable
from urllib import error, parse, request

REPO_DIR = Path(__file__).resolve().parents[2]
EXPORTS_DIR = REPO_DIR / "exports"

USERNAME = "admin"
PASSWORD = "S#nvhs89vher"
HOST_TEMPLATE = "qbittorrent.movie.{index}.nodadyoushutup.com"
USE_HTTPS = True
VERIFY_TLS = False

BATCH_INDEXES = list(range(9))
TARGET_PER_BATCH = 5000
UPLOAD_CHUNK_SIZE = 100
REQUEST_TIMEOUT_SECONDS = 120


@dataclass
class ClientTarget:
    index: int
    batch_dir: Path
    base_url: str


class QBClient:
    def __init__(self, base_url: str, timeout: int, verify_tls: bool = True) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

        handlers: list[object] = [request.HTTPCookieProcessor()]
        if self.base_url.startswith("https://"):
            if verify_tls:
                context = ssl.create_default_context()
            else:
                context = ssl._create_unverified_context()  # noqa: SLF001
            handlers.append(request.HTTPSHandler(context=context))

        self.opener = request.build_opener(*handlers)

    def _url(self, path: str) -> str:
        return f"{self.base_url}{path}"

    def _request(self, req: request.Request) -> bytes:
        with self.opener.open(req, timeout=self.timeout) as resp:
            return resp.read()

    def post_form(self, path: str, form_data: dict[str, str]) -> bytes:
        data = parse.urlencode(form_data).encode("utf-8")
        req = request.Request(self._url(path), data=data, method="POST")
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
        return self._request(req)

    def post_multipart(self, path: str, fields: dict[str, str], files: list[Path]) -> bytes:
        boundary = f"----qb-{uuid.uuid4().hex}"
        body = bytearray()

        for name, value in fields.items():
            body.extend(f"--{boundary}\r\n".encode())
            body.extend(
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
            )

        for torrent_path in files:
            payload = torrent_path.read_bytes()
            filename = torrent_path.name.replace('"', "")
            body.extend(f"--{boundary}\r\n".encode())
            body.extend(
                (
                    f'Content-Disposition: form-data; name="torrents"; '
                    f'filename="{filename}"\r\n'
                ).encode()
            )
            body.extend(b"Content-Type: application/x-bittorrent\r\n\r\n")
            body.extend(payload)
            body.extend(b"\r\n")

        body.extend(f"--{boundary}--\r\n".encode())

        req = request.Request(self._url(path), data=bytes(body), method="POST")
        req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
        return self._request(req)

    def get_json(self, path: str, query: dict[str, str] | None = None) -> object:
        url = self._url(path)
        if query:
            url = f"{url}?{parse.urlencode(query)}"
        req = request.Request(url, method="GET")
        raw = self._request(req)
        return json.loads(raw.decode("utf-8"))

    def login(self, username: str, password: str) -> None:
        resp = self.post_form("/api/v2/auth/login", {"username": username, "password": password})
        text = resp.decode("utf-8", errors="replace").strip()
        if text != "Ok.":
            raise RuntimeError(f"Login failed: {text}")

    def torrent_count(self) -> int:
        data = self.get_json("/api/v2/torrents/info", {"filter": "all"})
        if not isinstance(data, list):
            raise RuntimeError("Unexpected torrents/info payload")
        return len(data)

    def torrent_hashes(self) -> set[str]:
        data = self.get_json("/api/v2/torrents/info", {"filter": "all"})
        if not isinstance(data, list):
            raise RuntimeError("Unexpected torrents/info payload")
        hashes: set[str] = set()
        for item in data:
            if not isinstance(item, dict):
                continue
            value = item.get("hash")
            if isinstance(value, str) and value:
                hashes.add(value.lower())
        return hashes

    def add_torrents(self, files: list[Path]) -> str:
        fields = {
            "autoTMM": "false",
            "skip_checking": "true",
            "paused": "false",
            "stopCondition": "none",
        }
        resp = self.post_multipart("/api/v2/torrents/add", fields, files)
        return resp.decode("utf-8", errors="replace").strip()

    def add_torrents_adaptive(self, files: list[Path]) -> int:
        """
        Upload with automatic split/retry on 413 payload limits.
        Returns number of files successfully submitted.
        """
        if not files:
            return 0

        try:
            text = self.add_torrents(files)
        except error.HTTPError as exc:
            if exc.code == 413 and len(files) > 1:
                mid = len(files) // 2
                left = files[:mid]
                right = files[mid:]
                return self.add_torrents_adaptive(left) + self.add_torrents_adaptive(right)
            raise
        # qB usually returns empty body or "Ok." depending on version.
        if text in ("", "Ok."):
            return len(files)
        if text == "Fails.":
            if len(files) > 1:
                mid = len(files) // 2
                left = files[:mid]
                right = files[mid:]
                return self.add_torrents_adaptive(left) + self.add_torrents_adaptive(right)
            return 0
        raise RuntimeError(f"Unexpected add response: {text}")

    def add_urls(self, urls: list[str]) -> None:
        if not urls:
            return
        payload = {
            "urls": "\n".join(urls),
            "autoTMM": "false",
            "skip_checking": "true",
            "paused": "false",
            "stopCondition": "none",
        }
        resp = self.post_form("/api/v2/torrents/add", payload)
        text = resp.decode("utf-8", errors="replace").strip()
        if text not in ("", "Ok."):
            raise RuntimeError(f"Unexpected add-urls response: {text}")


def chunked(items: list[Path], size: int) -> Iterable[list[Path]]:
    for i in range(0, len(items), size):
        yield items[i : i + size]


def find_batch_dir(batch_index: int) -> Path:
    pattern = f"batch_{batch_index:04d}_*"
    matches = sorted(EXPORTS_DIR.glob(pattern))
    if not matches:
        raise FileNotFoundError(f"No batch directory found for index {batch_index} ({pattern})")
    if len(matches) > 1:
        names = ", ".join(m.name for m in matches)
        raise RuntimeError(f"Multiple batch dirs found for {batch_index}: {names}")
    if not matches[0].is_dir():
        raise RuntimeError(f"Resolved batch path is not a directory: {matches[0]}")
    return matches[0]


def extract_infohash_from_name(path: Path) -> str | None:
    match = re.search(r"([0-9a-fA-F]{40})", path.name)
    if not match:
        return None
    return match.group(1).lower()


def build_targets() -> list[ClientTarget]:
    scheme = "https" if USE_HTTPS else "http"
    targets: list[ClientTarget] = []
    for i in BATCH_INDEXES:
        batch_dir = find_batch_dir(i)
        host = HOST_TEMPLATE.format(index=i)
        targets.append(ClientTarget(index=i, batch_dir=batch_dir, base_url=f"{scheme}://{host}"))
    return targets


def main() -> int:
    if not EXPORTS_DIR.exists():
        print(f"[ERROR] Missing exports dir: {EXPORTS_DIR}", file=sys.stderr)
        return 2

    try:
        targets = build_targets()
    except Exception as exc:
        print(f"[ERROR] Target discovery failed: {exc}", file=sys.stderr)
        return 2

    print(f"[INFO] Targets: {len(targets)} | exports_dir={EXPORTS_DIR}")
    total_sent = 0

    for target in targets:
        torrent_files = sorted(target.batch_dir.glob("*.torrent"))
        available = len(torrent_files)
        requested = min(TARGET_PER_BATCH, available)
        selected = torrent_files[:requested]

        print(
            f"\n[INFO] movie-{target.index} <- {target.batch_dir.name} "
            f"available={available} selected={requested}"
        )

        if requested == 0:
            print(f"[WARN] Skipping movie-{target.index}: no torrents in {target.batch_dir}")
            continue
        if available < TARGET_PER_BATCH:
            print(
                f"[WARN] movie-{target.index}: requested {TARGET_PER_BATCH} but only {available} available"
            )

        client = QBClient(
            target.base_url,
            timeout=REQUEST_TIMEOUT_SECONDS,
            verify_tls=VERIFY_TLS,
        )

        try:
            client.login(USERNAME, PASSWORD)
            before = client.torrent_count()
            existing_hashes = client.torrent_hashes()
            print(f"[INFO] movie-{target.index}: pre-count={before}")

            pending: list[Path] = []
            skipped_existing = 0
            for torrent in selected:
                infohash = extract_infohash_from_name(torrent)
                if infohash and infohash in existing_hashes:
                    skipped_existing += 1
                    continue
                pending.append(torrent)

            if skipped_existing:
                print(
                    f"[INFO] movie-{target.index}: skipped_existing={skipped_existing} "
                    f"pending={len(pending)}"
                )

            if not pending:
                after = client.torrent_count()
                print(
                    f"[INFO] movie-{target.index}: nothing to add "
                    f"post-count={after} delta={after - before}"
                )
                continue

            chunk_total = (len(pending) + UPLOAD_CHUNK_SIZE - 1) // UPLOAD_CHUNK_SIZE
            sent = 0
            for n, part in enumerate(chunked(pending, UPLOAD_CHUNK_SIZE), start=1):
                try:
                    added = client.add_torrents_adaptive(part)
                except error.HTTPError as exc:
                    if exc.code != 413:
                        raise
                    # If a chunk still fails with 413, retry file-by-file and fallback
                    # oversized single-file uploads to magnet links.
                    added = 0
                    for torrent in part:
                        try:
                            added += client.add_torrents_adaptive([torrent])
                        except error.HTTPError as single_exc:
                            if single_exc.code != 413:
                                raise
                            infohash = extract_infohash_from_name(torrent)
                            if not infohash:
                                raise RuntimeError(
                                    f"Cannot fallback to magnet for oversized file: {torrent.name}"
                                ) from single_exc
                            magnet = f"magnet:?xt=urn:btih:{infohash}"
                            client.add_urls([magnet])
                            added += 1
                sent += added
                print(
                    f"[INFO] movie-{target.index}: chunk {n}/{chunk_total} "
                    f"uploaded={added} cumulative={sent}/{len(pending)}"
                )
                if added < len(part):
                    print(
                        f"[WARN] movie-{target.index}: chunk {n} had "
                        f"{len(part) - added} file(s) rejected by qBittorrent"
                    )

            after = client.torrent_count()
            print(
                f"[INFO] movie-{target.index}: post-count={after} "
                f"delta={after - before} uploaded={sent}"
            )
            total_sent += sent
        except (error.HTTPError, error.URLError, RuntimeError, OSError, json.JSONDecodeError) as exc:
            print(f"[ERROR] movie-{target.index} failed: {exc}", file=sys.stderr)
            return 1

    print(f"\n[DONE] Injection complete. total_uploaded={total_sent}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
