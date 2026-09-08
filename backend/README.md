# Backend

FastAPI business API for Stufe7.

```bash
python3 -m venv .venv
.venv/bin/pip install -e ".[dev]"
.venv/bin/uvicorn app.main:app --reload --port 8000
```

Export the OpenAPI contract (committed):

```bash
.venv/bin/python scripts/export_openapi.py
```
