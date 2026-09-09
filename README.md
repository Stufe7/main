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

## Render Cron Job (Phase 5)

Create a Cron Job that calls the API. It does not need its own database.

| Field | Value |
|---|---|
| **Schedule** | `0 * * * *` |
| **Command** | `curl -fsS -X POST "$JOB_URL" -H "X-Job-Secret: $JOB_SECRET"` |

Set `JOB_URL` to `https://stufe7-api.onrender.com/v1/jobs/run` (or the current API URL). Set the same `JOB_SECRET` on the API service and the Cron Job.

The hourly run dispatches Action Digest and campaign closure, upserts the weekly stat rollup, refreshes the disposable-domain deny list when the last success is older than seven days, and runs retention. Auth-orphan deletes run only when `SUPABASE_SERVICE_ROLE_KEY` is set on the API.

