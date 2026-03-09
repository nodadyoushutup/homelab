"""Service-account auth patch for workspace-mcp.

This monkeypatch is intentionally narrow: when WORKSPACE_MCP_USE_SERVICE_ACCOUNT=true,
workspace-mcp retrieves delegated user credentials from a mounted service account
JSON file instead of interactive OAuth client flows.
"""

from __future__ import annotations

import logging
import os
from functools import lru_cache
from typing import Iterable, Optional, Tuple

logger = logging.getLogger("workspace_mcp.service_account_patch")

_ENABLED_ENV = "WORKSPACE_MCP_USE_SERVICE_ACCOUNT"
_FILE_ENV = "WORKSPACE_MCP_SERVICE_ACCOUNT_FILE"
_USER_ENV = "WORKSPACE_MCP_DELEGATED_USER"


def _is_true(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _service_account_mode_enabled() -> bool:
    return _is_true(os.getenv(_ENABLED_ENV, "false"))


def _get_service_account_config() -> tuple[Optional[str], Optional[str]]:
    service_account_file = os.getenv(_FILE_ENV)
    delegated_user = os.getenv(_USER_ENV)

    if not service_account_file:
        logger.error("%s is required when %s=true", _FILE_ENV, _ENABLED_ENV)
        return None, None

    if not delegated_user:
        logger.error("%s is required when %s=true", _USER_ENV, _ENABLED_ENV)
        return None, None

    if "@" not in delegated_user:
        logger.error("%s must be a valid email address", _USER_ENV)
        return None, None

    if not os.path.isfile(service_account_file):
        logger.error("Service account file not found: %s", service_account_file)
        return None, None

    return service_account_file, delegated_user


def _normalize_scopes(scopes: Iterable[str]) -> Tuple[str, ...]:
    deduped: list[str] = []
    for scope in scopes:
        if scope and scope not in deduped:
            deduped.append(scope)
    return tuple(deduped)


def _refresh_credentials(credentials) -> bool:
    try:
        from google.auth.transport.requests import Request

        credentials.refresh(Request())
        return True
    except Exception:
        logger.exception("Failed refreshing delegated service-account credentials")
        return False


@lru_cache(maxsize=128)
def _build_service_account_credentials(
    service_account_file: str,
    delegated_user: str,
    scopes: Tuple[str, ...],
):
    from google.oauth2 import service_account

    credentials = service_account.Credentials.from_service_account_file(
        service_account_file,
        scopes=list(scopes),
    ).with_subject(delegated_user)
    return credentials


def _load_service_account_credentials(required_scopes: Iterable[str]):
    service_account_file, delegated_user = _get_service_account_config()
    if not service_account_file or not delegated_user:
        return None

    scopes = _normalize_scopes(required_scopes)

    try:
        credentials = _build_service_account_credentials(
            service_account_file,
            delegated_user,
            scopes,
        )
    except Exception:
        logger.exception("Failed creating delegated service-account credentials")
        return None

    if _refresh_credentials(credentials):
        return credentials

    return None


def _apply_patch() -> None:
    if not _service_account_mode_enabled():
        return

    try:
        from core import log_formatter as log_formatter_module
    except Exception:
        logger.exception("Service-account patch could not import core.log_formatter")
    else:
        def _skip_file_logging(logger_name=None) -> bool:
            logger.info("Skipping workspace-mcp file logging in service-account mode")
            return False

        log_formatter_module.configure_file_logging = _skip_file_logging

    try:
        from auth import google_auth as google_auth_module
    except Exception:
        logger.exception("Service-account patch could not import auth.google_auth")
        return

    original_get_credentials = google_auth_module.get_credentials
    original_get_authenticated_google_service = (
        google_auth_module.get_authenticated_google_service
    )

    def patched_get_credentials(
        user_google_email,
        required_scopes,
        client_secrets_path=None,
        credentials_base_dir=google_auth_module.DEFAULT_CREDENTIALS_DIR,
        session_id=None,
    ):
        credentials = _load_service_account_credentials(required_scopes)
        if credentials:
            return credentials

        logger.error(
            "Service-account mode enabled but delegated credentials could not be loaded"
        )
        return None

    async def patched_get_authenticated_google_service(
        service_name,
        version,
        tool_name,
        user_google_email,
        required_scopes,
        session_id=None,
    ):
        _, delegated_user = _get_service_account_config()
        if delegated_user:
            user_google_email = delegated_user

        return await original_get_authenticated_google_service(
            service_name=service_name,
            version=version,
            tool_name=tool_name,
            user_google_email=user_google_email,
            required_scopes=required_scopes,
            session_id=session_id,
        )

    google_auth_module.get_credentials = patched_get_credentials
    google_auth_module.get_authenticated_google_service = (
        patched_get_authenticated_google_service
    )

    logger.info("workspace-mcp service-account patch applied")


_apply_patch()
