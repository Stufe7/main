from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.account import router as account_router
from app.approvals import router as approvals_router
from app.campaigns import router as campaigns_router
from app.companies import router as companies_router
from app.contacts import router as contacts_router
from app.crm import router as crm_router
from app.db import close_runtime_pool
from app.domains import router as domains_router
from app.imports import router as imports_router
from app.invitations import router as invitations_router
from app.jobs import router as jobs_router
from app.members import router as members_router
from app.observability import CorrelationIdMiddleware, configure_logging
from app.phase1a import prove_kernel
from app.phase1b import prove_schema
from app.prefs import router as prefs_router
from app.privacy import router as privacy_router
from app.ratelimit import RateLimitMiddleware
from app.settings import settings
from app.signup import router as signup_router
from app.spike1 import prove_auth_uid

configure_logging()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    yield
    close_runtime_pool()


app = FastAPI(
    title="Stufe7 API",
    version=settings.app_version,
    docs_url="/docs" if settings.app_env != "production" else None,
    redoc_url=None,
    lifespan=lifespan,
)

app.add_middleware(CorrelationIdMiddleware)
app.add_middleware(RateLimitMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)
app.include_router(signup_router)
app.include_router(account_router)
app.include_router(approvals_router)
app.include_router(invitations_router)
app.include_router(members_router)
app.include_router(domains_router)
app.include_router(companies_router)
app.include_router(contacts_router)
app.include_router(campaigns_router)
app.include_router(imports_router)
app.include_router(crm_router)
app.include_router(jobs_router)
app.include_router(prefs_router)
app.include_router(privacy_router)


@app.get("/health", tags=["ops"])
def health() -> dict[str, str]:
    return {"status": "ok", "env": settings.app_env, "version": settings.app_version}


@app.get("/v1/meta", tags=["ops"])
def meta() -> dict[str, str]:
    return {"product": "Stufe7", "env": settings.app_env, "version": settings.app_version}


@app.get("/v1/ops/spike1", tags=["ops"])
def spike1() -> dict[str, object]:
    if settings.app_env == "production":
        raise HTTPException(status_code=404, detail="Not found")
    if not settings.database_url:
        raise HTTPException(status_code=503, detail="DATABASE_URL is not set")
    return prove_auth_uid()


@app.get("/v1/ops/phase1a", tags=["ops"])
def phase1a() -> dict[str, object]:
    if settings.app_env == "production":
        raise HTTPException(status_code=404, detail="Not found")
    if not settings.database_url:
        raise HTTPException(status_code=503, detail="DATABASE_URL is not set")
    return prove_kernel()


@app.get("/v1/ops/phase1b", tags=["ops"])
def phase1b() -> dict[str, object]:
    if settings.app_env == "production":
        raise HTTPException(status_code=404, detail="Not found")
    if not settings.database_url:
        raise HTTPException(status_code=503, detail="DATABASE_URL is not set")
    return prove_schema()
