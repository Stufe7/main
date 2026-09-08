# Stufe7

Lightweight multi-tenant CRM. Application source for [`Stufe7/main`](https://github.com/Stufe7/main).

| Tree | Role |
|---|---|
| `frontend/` | SvelteKit |
| `backend/` | FastAPI |
| `supabase/` | Schema, roles, Auth hooks (applied by the GitHub → Supabase integration) |

Contract: FastAPI commits `backend/openapi.json`; SvelteKit generates types with `openapi-typescript`. Do not copy source between the trees.

Local product documentation is **not** in this repository.

## Render

This repo is a monorepo. Dockerfiles:

| Service | Dockerfile | Context |
|---|---|---|
| Public website | `Dockerfile` (repo root) | repo root |
| FastAPI | `backend/Dockerfile` | `backend/` |

If a dashboard service was created with **Docker** and an empty root directory, it will now find the website Dockerfile. For the API, create a second service with **Root Directory** `backend`.

