#!/usr/bin/env python3
"""
Inject exported torrent files into qBittorrent television clients with a strict
5000-torrent cap per client.

Source priority is defined by SOURCE_EXPORT_DIRS order. The first source is
fully consumed before the next source is considered.
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

SOURCE_EXPORT_DIRS = [
    EXPORTS_DIR / "192.168.1.100_10097",
    EXPORTS_DIR / "192.168.1.100_41195",
]

TARGET_HOSTS = [
    "qbittorrent.television.0.nodadyoushutup.com",
    "qbittorrent.television.1.nodadyoushutup.com",
    "qbittorrent.television.2.nodadyoushutup.com",
]
INGRESS_BASE_URL = "http://192.168.1.241"

USERNAME = "admin"
PASSWORD = "S#nvhs89vher"
VERIFY_TLS = False
TARGET_PER_CLIENT = 5000
UPLOAD_CHUNK_SIZE = 100
REQUEST_TIMEOUT_SECONDS = 120


@dataclass
class TargetPlan:
    host: str
    base_url: str
    existing_count: int
    pending: list[Path]


class QBClient:
    def __init__(
        self,
        base_url: str,
        timeout: int,
        verify_tls: bool = True,
        host_header: str | None = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.host_header = host_header

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
        if self.host_header:
            req.add_header("Host", self.host_header)
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
        if not files:
            return 0

        try:
            text = self.add_torrents(files)
        except error.HTTPError as exc:
            if exc.code == 413 and len(files) > 1:
                mid = len(files) // 2
                return self.add_torrents_adaptive(files[:mid]) + self.add_torrents_adaptive(files[mid:])
            raise

        if text in ("", "Ok."):
            return len(files)
        if text == "Fails.":
            if len(files) > 1:
                mid = len(files) // 2
                return self.add_torrents_adaptive(files[:mid]) + self.add_torrents_adaptive(files[mid:])
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


def extract_infohash_from_name(path: Path) -> str | None:
    match = re.search(r"([0-9a-fA-F]{40})", path.name)
    if not match:
        return None
    return match.group(1).lower()


def batch_sort_key(path: Path) -> tuple[int, str]:
    match = re.search(r"_([0-9]{4})_[0-9]{4}-[0-9]{4}$", path.name)
    if match:
        return int(match.group(1)), path.name
    return 9999, path.name


def ordered_source_files(source_root: Path) -> list[Path]:
    if not source_root.exists():
        raise FileNotFoundError(f"Source export directory does not exist: {source_root}")
    batch_dirs = sorted(
        [p for p in source_root.iterdir() if p.is_dir() and p.name.startswith("batch_")],
        key=batch_sort_key,
    )

    files: list[Path] = []
    if not batch_dirs:
        files.extend(sorted(source_root.glob("*.torrent"), key=lambda p: (p.stat().st_mtime_ns, p.name)))
        return files

    for batch_dir in batch_dirs:
        batch_files = sorted(
            batch_dir.glob("*.torrent"),
            key=lambda p: (p.stat().st_mtime_ns, p.name),
        )
        files.extend(batch_files)
    return files


def build_target_clients() -> list[QBClient]:
    clients: list[QBClient] = []
    for host in TARGET_HOSTS:
        clients.append(
            QBClient(
                base_url=INGRESS_BASE_URL,
                timeout=REQUEST_TIMEOUT_SECONDS,
                verify_tls=VERIFY_TLS,
                host_header=host,
            )
        )
    return clients


def main() -> int:
    if not PASSWORD:
        print("[ERROR] Missing PASSWORD constant.", file=sys.stderr)
        return 2

    for source_dir in SOURCE_EXPORT_DIRS:
        if not source_dir.exists():
            print(f"[ERROR] Missing source directory: {source_dir}", file=sys.stderr)
            return 2

    clients = build_target_clients()
    plans: list[TargetPlan] = []
    global_seen_hashes: set[str] = set()

    print("[INFO] Loading existing state from target television clients...")
    for host, client in zip(TARGET_HOSTS, clients, strict=True):
        try:
            client.login(USERNAME, PASSWORD)
            existing_hashes = client.torrent_hashes()
            existing_count = len(existing_hashes)
        except (error.HTTPError, error.URLError, RuntimeError, json.JSONDecodeError) as exc:
            print(f"[ERROR] Failed loading target {host}: {exc}", file=sys.stderr)
            return 1

        plans.append(TargetPlan(host=host, base_url=client.base_url, existing_count=existing_count, pending=[]))
        global_seen_hashes.update(existing_hashes)
        print(f"[INFO] {host}: existing={existing_count}")

    slots_total = 0
    for plan in plans:
        slots = max(0, TARGET_PER_CLIENT - plan.existing_count)
        slots_total += slots
        print(f"[INFO] {plan.host}: available_slots={slots}")

    ordered_candidates: list[Path] = []
    for source_dir in SOURCE_EXPORT_DIRS:
        source_files = ordered_source_files(source_dir)
        ordered_candidates.extend(source_files)
        print(f"[INFO] source={source_dir.name} files={len(source_files)}")

    unique_queue: list[Path] = []
    skipped_invalid_hash = 0
    skipped_already_present = 0
    for torrent_file in ordered_candidates:
        infohash = extract_infohash_from_name(torrent_file)
        if not infohash:
            skipped_invalid_hash += 1
            continue
        if infohash in global_seen_hashes:
            skipped_already_present += 1
            continue
        global_seen_hashes.add(infohash)
        unique_queue.append(torrent_file)

    print(
        "[INFO] Candidate summary: "
        f"ordered_total={len(ordered_candidates)} "
        f"unique_new={len(unique_queue)} "
        f"skipped_invalid_hash={skipped_invalid_hash} "
        f"skipped_already_present={skipped_already_present} "
        f"slots_total={slots_total}"
    )

    if not unique_queue:
        print("[DONE] No new torrents to add.")
        return 0

    if len(unique_queue) > slots_total:
        print(
            f"[ERROR] Not enough target capacity. need={len(unique_queue)} available={slots_total}",
            file=sys.stderr,
        )
        return 1

    queue_index = 0
    for plan in plans:
        slots = max(0, TARGET_PER_CLIENT - plan.existing_count)
        if slots == 0:
            continue
        end = min(queue_index + slots, len(unique_queue))
        plan.pending = unique_queue[queue_index:end]
        queue_index = end

    for plan in plans:
        print(
            f"[PLAN] {plan.host} existing={plan.existing_count} "
            f"pending={len(plan.pending)} target_max={TARGET_PER_CLIENT}"
        )

    if queue_index != len(unique_queue):
        print("[ERROR] Queue assignment bug: not all torrents assigned.", file=sys.stderr)
        return 1

    total_uploaded = 0
    for plan, client in zip(plans, clients, strict=True):
        if not plan.pending:
            continue

        print(f"\n[INFO] Uploading to {plan.host} count={len(plan.pending)}")
        sent = 0
        chunk_total = (len(plan.pending) + UPLOAD_CHUNK_SIZE - 1) // UPLOAD_CHUNK_SIZE
        for n, part in enumerate(chunked(plan.pending, UPLOAD_CHUNK_SIZE), start=1):
            try:
                added = client.add_torrents_adaptive(part)
            except error.HTTPError as exc:
                if exc.code != 413:
                    raise
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
                f"[INFO] {plan.host}: chunk {n}/{chunk_total} "
                f"uploaded={added} cumulative={sent}/{len(plan.pending)}"
            )
            if added < len(part):
                print(
                    f"[WARN] {plan.host}: chunk {n} had {len(part) - added} rejected file(s)"
                )

        after = client.torrent_count()
        total_uploaded += sent
        print(
            f"[INFO] {plan.host}: post-count={after} "
            f"delta={after - plan.existing_count} uploaded={sent}"
        )
        if after > TARGET_PER_CLIENT:
            print(
                f"[ERROR] {plan.host} exceeded cap: {after} > {TARGET_PER_CLIENT}",
                file=sys.stderr,
            )
            return 1

    print(f"\n[DONE] Television injection complete. total_uploaded={total_uploaded}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
