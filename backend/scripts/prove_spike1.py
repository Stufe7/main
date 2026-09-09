"""Prove Spike 1: spec 17 claim-read under app_runtime + set_config.

Env:
  DATABASE_URL  transaction-pooler URI. Hosted Supavisor cannot log in as
  app_runtime; use postgres.PROJECT_REF on port 6543. The script then
  SET LOCAL ROLE app_runtime (never authenticated).
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
        raise SystemExit(f"FAIL: current_user is {result.get('current_user')}, expected app_runtime")
    if result.get("request_uid") is None:
        raise SystemExit(
            "FAIL: spec 17 claim-read is NULL. Stop Phase 1A. "
            "set_config('request.jwt.claims') did not yield a sub."
        )
    if not result.get("request_uid_matches_sub"):
        raise SystemExit("FAIL: spec 17 claim-read did not match the configured sub")
    if not result.get("set_role_app_authz_denied"):
        raise SystemExit("FAIL: app_runtime was able to SET ROLE app_authz")

    print("PASS: request.jwt.claims sub resolves under app_runtime; SET ROLE app_authz is denied")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:
        print(exc, file=sys.stderr)
        raise SystemExit(1) from exc
