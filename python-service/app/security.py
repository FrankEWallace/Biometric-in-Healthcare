"""
Internal authentication for the biometric microservice.

The service must only be reachable by the Laravel backend. When the
INTERNAL_API_KEY environment variable is set, every request to the
fingerprint and face routers must carry a matching X-Internal-Api-Key
header. /health remains open for platform probes.

If INTERNAL_API_KEY is not set (local development), requests are allowed
but a warning is logged once at import time so the gap is visible.
"""
from __future__ import annotations

import hmac
import logging
import os

from fastapi import Header, HTTPException

logger = logging.getLogger(__name__)

_INTERNAL_API_KEY = os.environ.get("INTERNAL_API_KEY", "")

if not _INTERNAL_API_KEY:
    logger.warning(
        "INTERNAL_API_KEY is not set — biometric endpoints are UNAUTHENTICATED. "
        "Set it in production and configure PYTHON_SERVICE_API_KEY in Laravel."
    )


async def require_internal_key(
    x_internal_api_key: str | None = Header(default=None),
) -> None:
    if not _INTERNAL_API_KEY:
        return  # dev mode — no key configured

    if x_internal_api_key is None or not hmac.compare_digest(
        x_internal_api_key, _INTERNAL_API_KEY
    ):
        raise HTTPException(status_code=401, detail="Invalid or missing internal API key.")
