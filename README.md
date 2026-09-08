# Stufe7

Lightweight multi-tenant CRM. Application source for [`Stufe7/main`](https://github.com/Stufe7/main).

| Tree | Role |
|---|---|
| `frontend/` | SvelteKit |
| `backend/` | FastAPI |
| `supabase/` | Schema, roles, Auth hooks (applied by the GitHub → Supabase integration) |

Contract: FastAPI commits `backend/openapi.json`; SvelteKit generates types with `openapi-typescript`. Do not copy source between the trees.

Local product documentation is **not** in this repository.
