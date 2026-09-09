from __future__ import annotations

import json
from typing import Annotated, Any

import jwt
from fastapi import Depends, Header, HTTPException
from jwt import InvalidTokenError

from app.settings import settings

Claims = dict[str, Any]


def bearer_claims(
    authorization: Annotated[str | None, Header()] = None,
) -> Claims:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()
    if not settings.supabase_jwt_secret:
        raise HTTPException(status_code=503, detail="SUPABASE_JWT_SECRET is not set")
    try:
        return jwt.decode(
            token,
            settings.supabase_jwt_secret,
            algorithms=["HS256"],
            audience="authenticated",
        )
    except InvalidTokenError as exc:
        raise HTTPException(status_code=401, detail="Invalid session") from exc


def require_user_id(claims: Annotated[Claims, Depends(bearer_claims)]) -> str:
    sub = claims.get("sub")
    if not sub:
        raise HTTPException(status_code=401, detail="Invalid session")
    return str(sub)


def claims_json(claims: Claims) -> str:
    return json.dumps(
        {
            "sub": claims.get("sub"),
            "email": claims.get("email"),
            "role": claims.get("role") or "authenticated",
        }
    )
