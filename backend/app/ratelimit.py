from __future__ import annotations

import time
from collections import defaultdict
from threading import Lock

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

LIMITS: dict[tuple[str, str], tuple[int, int]] = {
    ("POST", "/v1/signup/complete"): (8, 3600),
    ("POST", "/v1/account/email-change/start"): (8, 3600),
    ("POST", "/v1/invitations"): (30, 3600),
    ("POST", "/v1/companies/import"): (12, 3600),
}

_hits: dict[tuple[str, str, str], list[float]] = defaultdict(list)
_lock = Lock()


class RateLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        key_path = (request.method.upper(), request.url.path.rstrip("/") or "/")
        limit = LIMITS.get(key_path)
        if limit is None:
            return await call_next(request)
        count, window = limit
        ip = _client_ip(request)
        now = time.monotonic()
        bucket = (ip, key_path[0], key_path[1])
        with _lock:
            recent = [stamp for stamp in _hits[bucket] if now - stamp < window]
            if len(recent) >= count:
                retry = max(1, int(window - (now - recent[0])))
                return JSONResponse(
                    {"detail": "Too many requests. Try again later."},
                    status_code=429,
                    headers={"Retry-After": str(retry)},
                )
            recent.append(now)
            _hits[bucket] = recent
        return await call_next(request)


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",", 1)[0].strip() or "unknown"
    if request.client and request.client.host:
        return request.client.host
    return "unknown"


def clear_hits() -> None:
    with _lock:
        _hits.clear()
