"""Prove Spike 2: Gmail signup is rejected at the Auth hook, bypassing the UI.

Env:
  PUBLIC_SUPABASE_URL
  PUBLIC_SUPABASE_ANON_KEY
  SUPABASE_SERVICE_ROLE_KEY (optional; confirms no Auth user was created)
"""

from __future__ import annotations

import json
import os
import sys
import uuid
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

HOOK_MESSAGE = (
    "Use a company email address. Personal or disposable providers are not accepted."
)
GENERIC_HOOK_FAILURE = "invalid payload sent to hook"


def _env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(f"{name} is not set")
    return value.rstrip("/")


def _request(url: str, *, api_key: str, method: str = "POST", body: dict | None = None) -> tuple[int, dict]:
    payload = None if body is None else json.dumps(body).encode("utf-8")
    request = Request(
        url,
        data=payload,
        method=method,
        headers={
            "apikey": api_key,
            "authorization": f"Bearer {api_key}",
            "content-type": "application/json",
        },
    )
    try:
        with urlopen(request, timeout=30) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else {}
    except HTTPError as exc:
        raw = exc.read().decode("utf-8")
        try:
            parsed = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            parsed = {"message": raw}
        return exc.code, parsed
    except URLError as exc:
        raise SystemExit(f"request failed: {exc}") from exc


def main() -> None:
    base = _env("PUBLIC_SUPABASE_URL")
    anon = _env("PUBLIC_SUPABASE_ANON_KEY")
    service = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    email = f"spike2-{uuid.uuid4().hex}@gmail.com"

    status, body = _request(
        f"{base}/auth/v1/otp",
        api_key=anon,
        body={"email": email, "create_user": True},
    )
    message = str(body.get("msg") or body.get("message") or body.get("error_description") or "")
    print(json.dumps({"status": status, "body": body, "email": email}, indent=2))

    if status < 400:
        raise SystemExit("FAIL: Gmail OTP succeeded; hook did not reject")
    if GENERIC_HOOK_FAILURE in message.lower():
        raise SystemExit("FAIL: client saw generic hook payload error, not the company-email message")
    if HOOK_MESSAGE not in message and "company email" not in message.lower():
        raise SystemExit(f"FAIL: rejection message was not usable: {message!r}")

    if service:
        admin_status, admin_body = _request(
            f"{base}/auth/v1/admin/users?page=1&per_page=200",
            api_key=service,
            method="GET",
        )
        if admin_status >= 400:
            raise SystemExit(f"FAIL: admin user list returned {admin_status}")
        users = admin_body.get("users") if isinstance(admin_body, dict) else None
        if isinstance(users, list) and any(
            str(user.get("email", "")).lower() == email for user in users
        ):
            raise SystemExit("FAIL: Auth user was created for the rejected Gmail address")

    print("PASS: Gmail signup rejected with a usable company-email message")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:
        print(exc, file=sys.stderr)
        raise SystemExit(1) from exc
