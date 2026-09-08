from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager

import psycopg

from app.settings import settings


def require_database_url() -> str:
    if not settings.database_url:
        raise RuntimeError("DATABASE_URL is not set")
    return settings.database_url


@contextmanager
def runtime_connection() -> Iterator[psycopg.Connection]:
    connection = psycopg.connect(require_database_url())
    try:
        yield connection
    finally:
        connection.close()
