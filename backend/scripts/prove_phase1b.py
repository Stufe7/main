"""Prove Phase 1B schema: projections, composite FKs, last-admin, campaign horizon."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.db import require_database_url
from app.phase1b import prove_schema


def main() -> None:
    require_database_url()
    result = prove_schema()
    print(json.dumps(result, indent=2, default=str))
    required = (
        "activity_projects_to_company",
        "projection_did_not_stamp_company_updated_by",
        "next_action_projects",
        "activity_revision_written",
        "cross_tenant_activity_fk_blocked",
        "cross_tenant_chain_fk_blocked",
        "second_admin_downgrade_allowed",
        "last_admin_downgrade_blocked",
        "campaign_horizon_blocked",
    )
    missing = [name for name in required if not result.get(name)]
    if missing:
        raise SystemExit(f"FAIL: {', '.join(missing)}")
    print("PASS: Phase 1B schema isolation and integrity hold")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:
        print(exc, file=sys.stderr)
        raise SystemExit(1) from exc
