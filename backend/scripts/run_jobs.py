"""Run Phase 5 jobs locally without HTTP. Uses DATABASE_URL; does not SET ROLE."""

from __future__ import annotations

import json

from app.jobs import run_all_jobs


def main() -> None:
    print(json.dumps(run_all_jobs(), default=str, indent=2))


if __name__ == "__main__":
    main()
