from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.observability import CorrelationIdMiddleware, configure_logging
from app.settings import settings

configure_logging()

app = FastAPI(
    title="Stufe7 API",
    version=settings.app_version,
    docs_url="/docs" if settings.app_env != "production" else None,
    redoc_url=None,
)

app.add_middleware(CorrelationIdMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)


@app.get("/health", tags=["ops"])
def health() -> dict[str, str]:
    return {"status": "ok", "env": settings.app_env, "version": settings.app_version}


@app.get("/v1/meta", tags=["ops"])
def meta() -> dict[str, str]:
    return {"product": "Stufe7", "env": settings.app_env, "version": settings.app_version}
