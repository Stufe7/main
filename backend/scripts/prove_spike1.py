"""Prove Spike 1: auth.uid() under app_runtime + set_config, and SET ROLE app_authz fails.

Env:
  DATABASE_URL  transaction-pooler URI as app_runtime (never postgres/service_role)
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.db import require_database_url
from app.spike1 import prove_auth_uid


def main() -> None:
    require_database_url()
    result = prove_auth_uid()
    print(json.dumps(result, indent=2))

    if result.get("current_user") != "app_runtime":
        raise SystemExit(f"FAIL: connected as {result.get('current_user')}, expected app_runtime")
    if result.get("auth_uid") is None:
        raise SystemExit(
            "FAIL: auth.uid() is NULL. Stop Phase 1A. Revise spec 17 to read "
            "current_setting('request.jwt.claims', true)::json ->> 'sub'."
        )
    if not result.get("matches_sub"):
        raise SystemExit("FAIL: auth.uid() did not match the configured sub")
    if not result.get("set_role_app_authz_denied"):
        raise SystemExit("FAIL: app_runtime was able to SET ROLE app_authz")

    print("PASS: auth.uid() resolves under app_runtime; SET ROLE app_authz is denied")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:
        print(exc, file=sys.stderr)
        raise SystemExit(1) from exc
