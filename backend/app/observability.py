from __future__ import annotations

import logging
import uuid
from collections.abc import Awaitable, Callable

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.settings import settings

logger = logging.getLogger("stufe7")


def configure_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s env=%(env)s version=%(version)s correlation_id=%(correlation_id)s %(message)s",
    )
    logging.getLogger().handlers[0].addFilter(_ContextFilter())


class _ContextFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.env = getattr(record, "env", settings.app_env)
        record.version = getattr(record, "version", settings.app_version)
        record.correlation_id = getattr(record, "correlation_id", "-")
        return True


class CorrelationIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self, request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        correlation_id = request.headers.get("x-request-id") or str(uuid.uuid4())
        request.state.correlation_id = correlation_id
        extra = {
            "env": settings.app_env,
            "version": settings.app_version,
            "correlation_id": correlation_id,
        }
        logger.info("%s %s", request.method, request.url.path, extra=extra)
        try:
            response = await call_next(request)
        except Exception:
            logger.exception("uncaught %s %s", request.method, request.url.path, extra=extra)
            raise
        response.headers["x-request-id"] = correlation_id
        response.headers["x-app-version"] = settings.app_version
        response.headers["x-app-env"] = settings.app_env
        _apply_security_headers(request, response)
        return response


def _apply_security_headers(request: Request, response: Response) -> None:
    response.headers["x-content-type-options"] = "nosniff"
    response.headers["x-frame-options"] = "DENY"
    response.headers["referrer-policy"] = "strict-origin-when-cross-origin"
    response.headers["permissions-policy"] = "camera=(), microphone=(), geolocation=()"
    forwarded = (request.headers.get("x-forwarded-proto") or request.url.scheme).lower()
    if forwarded == "https":
        response.headers["strict-transport-security"] = "max-age=63072000; includeSubDomains"
