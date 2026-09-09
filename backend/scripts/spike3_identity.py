"""Run Spike 3 company-identity sample. Live HTTP fetches; not a unit test."""

from __future__ import annotations

import json
import sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.identity import verify_company_identity

SAMPLE = Path(__file__).with_name("spike3_sample.json")


def main() -> None:
    cases = json.loads(SAMPLE.read_text(encoding="utf-8"))
    results = []

    def run(case: dict) -> dict:
        verdict = verify_company_identity(
            work_email=case["email"],
            company_name=case["company_name"],
            company_url=case["url"],
        )
        return {
            "case": case["case"],
            "company_name": case["company_name"],
            "email": case["email"],
            "url": case["url"],
            "decision": verdict.decision,
            "reason_code": verdict.reason_code,
            "title": verdict.title,
            "email_domain": verdict.email_domain,
            "website_domain": verdict.website_domain,
            "summary": verdict.summary,
        }

    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = [pool.submit(run, case) for case in cases]
        for future in as_completed(futures):
            results.append(future.result())

    results.sort(key=lambda row: (row["case"], row["company_name"]))
    counts = Counter(row["decision"] for row in results)
    reasons = Counter(row["reason_code"] for row in results)
    total = len(results)
    verified = counts.get("Verified", 0)
    print(json.dumps(
        {
            "total": total,
            "verified": verified,
            "review_required": counts.get("Review Required", 0),
            "auto_verify_rate": round(verified / total, 3) if total else 0,
            "reasons": dict(reasons),
            "results": results,
        },
        indent=2,
    ))


if __name__ == "__main__":
    main()
