"""qBittorrent Web API v2 client."""

from __future__ import annotations

import json
import ssl
from typing import Any
from urllib import error, parse, request

from torrent_manager.qbittorrent_settings import QBitTorrentClientConfig


class QBitTorrentError(RuntimeError):
    """Raised when a qBittorrent API call fails."""


class QBitTorrentClient:
    """Authenticated client for one qBittorrent Web UI instance."""

    def __init__(self, config: QBitTorrentClientConfig) -> None:
        self.config = config
        self._logged_in = False
        context: ssl.SSLContext | None = None
        if config.insecure_tls:
            context = ssl.create_default_context()
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE

        handlers: list[Any] = [request.HTTPCookieProcessor()]
        if context is not None:
            handlers.append(request.HTTPSHandler(context=context))
        self._opener = request.build_opener(*handlers)

    @property
    def client_id(self) -> str:
        return self.config.client_id

    @property
    def base_url(self) -> str:
        return self.config.base_url

    def _url(self, path: str) -> str:
        return f"{self.base_url}{path}"

    def _prepare_request(self, req: request.Request) -> request.Request:
        if self.config.host_header:
            req.add_header("Host", self.config.host_header)
        return req

    def _post_form(self, path: str, form_data: dict[str, str]) -> bytes:
        data = parse.urlencode(form_data).encode("utf-8")
        req = request.Request(self._url(path), data=data, method="POST")
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
        req = self._prepare_request(req)
        try:
            with self._opener.open(req, timeout=self.config.timeout_sec) as resp:
                return resp.read()
        except error.URLError as exc:
            raise QBitTorrentError(str(exc)) from exc

    def _get(self, path: str, query: dict[str, str] | None = None) -> bytes:
        url = self._url(path)
        if query:
            url = f"{url}?{parse.urlencode(query)}"
        req = request.Request(url, method="GET")
        req = self._prepare_request(req)
        try:
            with self._opener.open(req, timeout=self.config.timeout_sec) as resp:
                return resp.read()
        except error.URLError as exc:
            raise QBitTorrentError(str(exc)) from exc

    def login(self) -> None:
        """Authenticate against ``/api/v2/auth/login``."""
        body = self._post_form(
            "/api/v2/auth/login",
            {
                "username": self.config.username,
                "password": self.config.password,
            },
        )
        result = body.decode("utf-8", errors="replace").strip()
        if result != "Ok.":
            raise QBitTorrentError(f"login failed: {result or 'empty response'}")
        self._logged_in = True

    def ensure_login(self) -> None:
        """Log in when the session has not been established yet."""
        if not self._logged_in:
            self.login()

    def app_version(self) -> str:
        """Return the qBittorrent application version string."""
        self.ensure_login()
        body = self._get("/api/v2/app/version")
        return body.decode("utf-8", errors="replace").strip().strip('"')

    def list_torrents(self, *, tag: str | None = None) -> list[dict[str, Any]]:
        """Return torrent rows from ``/api/v2/torrents/info``."""
        self.ensure_login()
        query = {"tag": tag} if tag else None
        body = self._get("/api/v2/torrents/info", query=query)
        decoded = json.loads(body.decode("utf-8"))
        if not isinstance(decoded, list):
            raise QBitTorrentError("unexpected torrents/info response format")
        return decoded

    def ping(self) -> str:
        """Verify connectivity and authentication, returning the app version."""
        return self.app_version()
