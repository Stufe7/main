"""Prove Phase 1A kernel: claim-read RLS, composite FK, helper grants.

Env:
  DATABASE_URL  transaction-pooler URI as postgres.PROJECT_REF on port 6543.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.db import require_database_url
from app.phase1a import prove_kernel


def main() -> None:
    require_database_url()
    result = prove_kernel()
    print(json.dumps(result, indent=2))
    required = (
        "cross_tenant_company_insert_blocked",
        "cross_tenant_contact_fk_blocked",
        "set_role_app_authz_denied",
        "helpers_not_executable_by_anon_authenticated",
        "helper_stable_under_search_path",
        "two_primaries_blocked",
        "primary_transfer_commits",
        "helper_true_for_member",
        "helper_empty_for_non_member",
    )
    missing = [name for name in required if not result.get(name)]
    if missing:
        raise SystemExit(f"FAIL: {', '.join(missing)}")
    print("PASS: Phase 1A kernel isolation holds; policies use claim-read, not auth.uid()")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:
        print(exc, file=sys.stderr)
        raise SystemExit(1) from exc
