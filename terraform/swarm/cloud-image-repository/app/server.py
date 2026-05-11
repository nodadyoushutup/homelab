#!/usr/bin/env python3

import datetime
import email.utils
import json
import mimetypes
import os
import shutil
import stat
import tempfile
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


DATA_ROOT = os.path.realpath(os.environ.get("CLOUD_IMAGE_REPOSITORY_DATA_ROOT", "/srv/cloud-image-repository/data"))
UI_ROOT = os.path.realpath(os.environ.get("CLOUD_IMAGE_REPOSITORY_UI_ROOT", "/srv/cloud-image-repository/ui"))
LISTEN_PORT = int(os.environ.get("CLOUD_IMAGE_REPOSITORY_PORT", "8080"))
READ_CHUNK_SIZE = 1024 * 1024
WRITE_CHUNK_SIZE = 1024 * 1024
API_PREFIX = "/api/files/"
STATIC_ROUTES = {
    "/": "index.html",
    "/index.html": "index.html",
    "/app.js": "app.js",
    "/favicon.svg": "favicon.svg",
}


def _normalized_relative_path(raw_path: str) -> str:
    decoded = urllib.parse.unquote(raw_path or "")
    segments = []

    for segment in decoded.split("/"):
        cleaned = segment.strip()
        if not cleaned or cleaned == ".":
            continue
        if cleaned == "..":
            raise ValueError("path traversal is not allowed")
        segments.append(cleaned)

    return "/".join(segments)


def _resolve_under_root(root: str, relative_path: str) -> str:
    candidate = os.path.realpath(os.path.join(root, relative_path))
    if os.path.commonpath([root, candidate]) != root:
        raise PermissionError("path escapes the allowed root")
    return candidate


def _iso_utc_timestamp(epoch_seconds: float) -> str:
    stamp = datetime.datetime.fromtimestamp(epoch_seconds, tz=datetime.timezone.utc)
    return stamp.isoformat().replace("+00:00", "Z")


class FileServerHandler(BaseHTTPRequestHandler):
    server_version = "CloudImageRepository/1.0"

    def do_OPTIONS(self) -> None:
        self._send_status(204)

    def do_GET(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        request_path = parsed.path

        if request_path == "/favicon.ico":
            self._send_redirect("/favicon.svg")
            return

        if request_path.startswith(API_PREFIX):
            self._handle_api_list(request_path)
            return

        static_target = STATIC_ROUTES.get(request_path)
        if static_target:
            self._serve_static_file(static_target, send_body=True)
            return

        self._serve_data_path(request_path, send_body=True)

    def do_HEAD(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        request_path = parsed.path

        if request_path == "/favicon.ico":
            self._send_redirect("/favicon.svg")
            return

        if request_path.startswith(API_PREFIX):
            self._send_status(405, body=b"HEAD not supported for API listing\n", content_type="text/plain; charset=utf-8")
            return

        static_target = STATIC_ROUTES.get(request_path)
        if static_target:
            self._serve_static_file(static_target, send_body=False)
            return

        self._serve_data_path(request_path, send_body=False)

    def do_PUT(self) -> None:
        self._handle_write()

    def do_POST(self) -> None:
        self._handle_write()

    def do_DELETE(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        request_path = parsed.path

        if request_path.startswith(API_PREFIX) or request_path in STATIC_ROUTES or request_path == "/favicon.ico":
            self._send_status(405, body=b"DELETE not allowed for this endpoint\n", content_type="text/plain; charset=utf-8")
            return

        try:
            relative_path = _normalized_relative_path(request_path.lstrip("/"))
            if not relative_path:
                self._send_status(403, body=b"Refusing to delete the data root\n", content_type="text/plain; charset=utf-8")
                return

            target = _resolve_under_root(DATA_ROOT, relative_path)
        except (ValueError, PermissionError):
            self._send_status(400, body=b"Invalid path\n", content_type="text/plain; charset=utf-8")
            return

        if not os.path.exists(target):
            self._send_status(404, body=b"Not found\n", content_type="text/plain; charset=utf-8")
            return

        try:
            if os.path.isdir(target):
                shutil.rmtree(target)
            else:
                os.remove(target)
        except OSError as error:
            message = f"Delete failed: {error}\n".encode("utf-8")
            self._send_status(500, body=message, content_type="text/plain; charset=utf-8")
            return

        self._send_status(204)

    def do_MKCOL(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        request_path = parsed.path

        if request_path.startswith(API_PREFIX) or request_path in STATIC_ROUTES or request_path == "/favicon.ico":
            self._send_status(405, body=b"MKCOL not allowed for this endpoint\n", content_type="text/plain; charset=utf-8")
            return

        try:
            relative_path = _normalized_relative_path(request_path.lstrip("/"))
            if not relative_path:
                self._send_status(405, body=b"Root collection already exists\n", content_type="text/plain; charset=utf-8")
                return

            target = _resolve_under_root(DATA_ROOT, relative_path)
        except (ValueError, PermissionError):
            self._send_status(400, body=b"Invalid path\n", content_type="text/plain; charset=utf-8")
            return

        if os.path.exists(target):
            self._send_status(405, body=b"Target already exists\n", content_type="text/plain; charset=utf-8")
            return

        try:
            os.makedirs(target, exist_ok=False)
        except OSError as error:
            message = f"MKCOL failed: {error}\n".encode("utf-8")
            self._send_status(500, body=message, content_type="text/plain; charset=utf-8")
            return

        self._send_status(201)

    def do_COPY(self) -> None:
        self._handle_copy_or_move(move=False)

    def do_MOVE(self) -> None:
        self._handle_copy_or_move(move=True)

    def _handle_api_list(self, request_path: str) -> None:
        api_relative_path = request_path[len(API_PREFIX) :]

        try:
            relative_path = _normalized_relative_path(api_relative_path)
            directory = _resolve_under_root(DATA_ROOT, relative_path)
        except (ValueError, PermissionError):
            self._send_status(400, body=b"Invalid path\n", content_type="text/plain; charset=utf-8")
            return

        if not os.path.isdir(directory):
            self._send_status(404, body=b"Directory not found\n", content_type="text/plain; charset=utf-8")
            return

        payload = []
        try:
            for name in sorted(os.listdir(directory), key=lambda value: value.lower()):
                full_path = os.path.join(directory, name)
                try:
                    item_stat = os.lstat(full_path)
                except OSError:
                    continue

                is_directory = stat.S_ISDIR(item_stat.st_mode)
                logical_size = None if is_directory else int(item_stat.st_size)
                block_count = getattr(item_stat, "st_blocks", None)
                allocated_size = None
                if not is_directory:
                    if isinstance(block_count, int) and block_count >= 0:
                        allocated_size = block_count * 512
                    else:
                        allocated_size = logical_size

                payload.append(
                    {
                        "name": f"{name}/" if is_directory else name,
                        "type": "directory" if is_directory else "file",
                        "size": logical_size,
                        "allocated_size": allocated_size,
                        "mtime": _iso_utc_timestamp(item_stat.st_mtime),
                    }
                )
        except OSError as error:
            message = f"Failed to read directory: {error}\n".encode("utf-8")
            self._send_status(500, body=message, content_type="text/plain; charset=utf-8")
            return

        body = json.dumps(payload, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
        self._send_status(200, body=body, content_type="application/json")

    def _handle_write(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        request_path = parsed.path

        if request_path.startswith(API_PREFIX) or request_path in STATIC_ROUTES or request_path == "/favicon.ico":
            self._send_status(405, body=b"Write method not allowed for this endpoint\n", content_type="text/plain; charset=utf-8")
            return

        content_length_header = self.headers.get("Content-Length")
        if content_length_header is None:
            self._send_status(411, body=b"Content-Length header is required\n", content_type="text/plain; charset=utf-8")
            return

        try:
            content_length = int(content_length_header)
            if content_length < 0:
                raise ValueError
        except ValueError:
            self._send_status(400, body=b"Invalid Content-Length\n", content_type="text/plain; charset=utf-8")
            return

        try:
            relative_path = _normalized_relative_path(request_path.lstrip("/"))
            if not relative_path:
                self._send_status(400, body=b"A target file path is required\n", content_type="text/plain; charset=utf-8")
                return

            target = _resolve_under_root(DATA_ROOT, relative_path)
            target_directory = os.path.dirname(target)
            os.makedirs(target_directory, exist_ok=True)
        except (ValueError, PermissionError):
            self._send_status(400, body=b"Invalid path\n", content_type="text/plain; charset=utf-8")
            return
        except OSError as error:
            message = f"Failed to prepare directory: {error}\n".encode("utf-8")
            self._send_status(500, body=message, content_type="text/plain; charset=utf-8")
            return

        already_exists = os.path.exists(target)
        temp_fd = None
        temp_path = None

        try:
            temp_fd, temp_path = tempfile.mkstemp(prefix=".upload-", suffix=".tmp", dir=target_directory)
            with os.fdopen(temp_fd, "wb") as handle:
                temp_fd = None
                remaining = content_length

                while remaining > 0:
                    chunk = self.rfile.read(min(WRITE_CHUNK_SIZE, remaining))
                    if not chunk:
                        raise IOError("request body ended unexpectedly")
                    handle.write(chunk)
                    remaining -= len(chunk)

            os.replace(temp_path, target)
            temp_path = None
        except Exception as error:  # noqa: BLE001
            if temp_fd is not None:
                os.close(temp_fd)
            if temp_path and os.path.exists(temp_path):
                os.remove(temp_path)
            message = f"Write failed: {error}\n".encode("utf-8")
            self._send_status(500, body=message, content_type="text/plain; charset=utf-8")
            return

        self._send_status(204 if already_exists else 201)

    def _handle_copy_or_move(self, move: bool) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        source_request_path = parsed.path

        if source_request_path.startswith(API_PREFIX) or source_request_path in STATIC_ROUTES or source_request_path == "/favicon.ico":
            self._send_status(405, body=b"Method not allowed for this endpoint\n", content_type="text/plain; charset=utf-8")
            return

        destination_header = self.headers.get("Destination")
        if not destination_header:
            self._send_status(400, body=b"Destination header is required\n", content_type="text/plain; charset=utf-8")
            return

        destination_path = urllib.parse.urlsplit(destination_header).path
        overwrite_allowed = self.headers.get("Overwrite", "T").strip().upper() != "F"

        try:
            source_rel_path = _normalized_relative_path(source_request_path.lstrip("/"))
            destination_rel_path = _normalized_relative_path(destination_path.lstrip("/"))
            if not source_rel_path or not destination_rel_path:
                self._send_status(400, body=b"Source and destination paths are required\n", content_type="text/plain; charset=utf-8")
                return

            source_target = _resolve_under_root(DATA_ROOT, source_rel_path)
            destination_target = _resolve_under_root(DATA_ROOT, destination_rel_path)
        except (ValueError, PermissionError):
            self._send_status(400, body=b"Invalid source or destination path\n", content_type="text/plain; charset=utf-8")
            return

        if not os.path.exists(source_target):
            self._send_status(404, body=b"Source not found\n", content_type="text/plain; charset=utf-8")
            return

        if source_target == destination_target:
            self._send_status(403, body=b"Source and destination are identical\n", content_type="text/plain; charset=utf-8")
            return

        source_is_dir = os.path.isdir(source_target)
        if source_is_dir and os.path.commonpath([source_target, destination_target]) == source_target:
            self._send_status(409, body=b"Cannot copy or move a directory into itself\n", content_type="text/plain; charset=utf-8")
            return

        destination_exists = os.path.exists(destination_target)
        if destination_exists and not overwrite_allowed:
            self._send_status(412, body=b"Destination exists and overwrite is disabled\n", content_type="text/plain; charset=utf-8")
            return

        try:
            os.makedirs(os.path.dirname(destination_target), exist_ok=True)

            if destination_exists:
                if os.path.isdir(destination_target):
                    shutil.rmtree(destination_target)
                else:
                    os.remove(destination_target)

            if source_is_dir:
                shutil.copytree(source_target, destination_target)
            else:
                shutil.copy2(source_target, destination_target)

            if move:
                if source_is_dir:
                    shutil.rmtree(source_target)
                else:
                    os.remove(source_target)
        except OSError as error:
            message = f"{'MOVE' if move else 'COPY'} failed: {error}\n".encode("utf-8")
            self._send_status(500, body=message, content_type="text/plain; charset=utf-8")
            return

        self._send_status(204 if destination_exists else 201)

    def _serve_static_file(self, filename: str, send_body: bool) -> None:
        try:
            full_path = _resolve_under_root(UI_ROOT, filename)
        except PermissionError:
            self._send_status(500, body=b"Invalid static path\n", content_type="text/plain; charset=utf-8")
            return

        self._serve_file(full_path, send_body=send_body)

    def _serve_data_path(self, request_path: str, send_body: bool) -> None:
        try:
            relative_path = _normalized_relative_path(request_path.lstrip("/"))
            target = _resolve_under_root(DATA_ROOT, relative_path)
        except (ValueError, PermissionError):
            self._send_status(400, body=b"Invalid path\n", content_type="text/plain; charset=utf-8")
            return

        if os.path.isdir(target):
            if relative_path:
                redirect_to = f"/?path={urllib.parse.quote(relative_path)}"
            else:
                redirect_to = "/"
            self._send_redirect(redirect_to)
            return

        self._serve_file(target, send_body=send_body)

    def _serve_file(self, file_path: str, send_body: bool) -> None:
        if not os.path.exists(file_path) or not os.path.isfile(file_path):
            self._send_status(404, body=b"Not found\n", content_type="text/plain; charset=utf-8")
            return

        try:
            file_stat = os.stat(file_path)
            content_type, _ = mimetypes.guess_type(file_path)
            if not content_type:
                content_type = "application/octet-stream"

            self.send_response(200)
            self._write_common_headers()
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(file_stat.st_size))
            self.send_header("Last-Modified", email.utils.formatdate(file_stat.st_mtime, usegmt=True))
            self.end_headers()

            if not send_body:
                return

            with open(file_path, "rb") as handle:
                while True:
                    chunk = handle.read(READ_CHUNK_SIZE)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
        except OSError as error:
            message = f"Failed to read file: {error}\n".encode("utf-8")
            self._send_status(500, body=message, content_type="text/plain; charset=utf-8")

    def _send_redirect(self, location: str) -> None:
        self.send_response(302)
        self._write_common_headers()
        self.send_header("Location", location)
        self.end_headers()

    def _send_status(self, status_code: int, body: bytes = b"", content_type: str = "text/plain; charset=utf-8") -> None:
        self.send_response(status_code)
        self._write_common_headers()
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body and self.command != "HEAD":
            self.wfile.write(body)

    def _write_common_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,HEAD,POST,PUT,DELETE,OPTIONS,MKCOL,COPY,MOVE")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("X-Content-Type-Options", "nosniff")

    def log_message(self, fmt: str, *args) -> None:
        print(f"{self.client_address[0]} - [{self.log_date_time_string()}] {fmt % args}")


def main() -> None:
    os.makedirs(DATA_ROOT, exist_ok=True)
    os.makedirs(UI_ROOT, exist_ok=True)

    server = ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), FileServerHandler)
    print(f"listening on 0.0.0.0:{LISTEN_PORT}, data_root={DATA_ROOT}, ui_root={UI_ROOT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
