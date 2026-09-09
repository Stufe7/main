from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager

import psycopg
from psycopg_pool import ConnectionPool

from app.settings import settings

_runtime_pool: ConnectionPool | None = None


def require_database_url() -> str:
    if not settings.database_url:
        raise RuntimeError("DATABASE_URL is not set")
    return settings.database_url


def _pool() -> ConnectionPool:
    global _runtime_pool
    if _runtime_pool is None:
        # prepare_threshold=None: hosted DATABASE_URL is PgBouncer transaction
        # mode, which cannot keep prepared statements across checkouts.
        _runtime_pool = ConnectionPool(
            conninfo=require_database_url(),
            min_size=1,
            max_size=8,
            open=True,
            kwargs={"prepare_threshold": None},
        )
    return _runtime_pool


def close_runtime_pool() -> None:
    global _runtime_pool
    if _runtime_pool is not None:
        _runtime_pool.close()
        _runtime_pool = None


@contextmanager
def runtime_connection() -> Iterator[psycopg.Connection]:
    with _pool().connection() as connection:
        yield connection


@contextmanager
def job_connection() -> Iterator[psycopg.Connection]:
    """Privileged scheduler path. Callers must not SET ROLE app_runtime."""
    connection = psycopg.connect(require_database_url())
    try:
        yield connection
    finally:
        connection.close()
