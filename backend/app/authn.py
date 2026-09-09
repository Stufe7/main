from __future__ import annotations

import json
from typing import Annotated, Any

import jwt
from fastapi import Depends, Header, HTTPException
from jwt import InvalidTokenError, PyJWKClient

from app.settings import settings

Claims = dict[str, Any]

_jwks_client: PyJWKClient | None = None
_ASYMMETRIC = {"ES256", "RS256"}


def _jwks() -> PyJWKClient:
    global _jwks_client
    if _jwks_client is None:
        base = settings.supabase_url.rstrip("/")
        if not base:
            raise HTTPException(status_code=503, detail="SUPABASE_URL is not set")
        _jwks_client = PyJWKClient(f"{base}/auth/v1/.well-known/jwks.json", cache_keys=True)
    return _jwks_client


def decode_access_token(token: str) -> Claims:
    header = jwt.get_unverified_header(token)
    alg = str(header.get("alg") or "")
    options = {"verify_aud": True}
    if alg in _ASYMMETRIC:
        key = _jwks().get_signing_key_from_jwt(token)
        return jwt.decode(
            token,
            key.key,
            algorithms=[alg],
            audience="authenticated",
            leeway=30,
            options=options,
        )
    if alg == "HS256":
        if not settings.supabase_jwt_secret:
            raise HTTPException(status_code=503, detail="SUPABASE_JWT_SECRET is not set")
        return jwt.decode(
            token,
            settings.supabase_jwt_secret,
            algorithms=["HS256"],
            audience="authenticated",
            leeway=30,
            options=options,
        )
    raise InvalidTokenError(f"Unsupported JWT alg {alg or 'missing'}")


def bearer_claims(
    authorization: Annotated[str | None, Header()] = None,
) -> Claims:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()
    try:
        return decode_access_token(token)
    except HTTPException:
        raise
    except jwt.exceptions.PyJWKClientConnectionError as exc:
        raise HTTPException(status_code=503, detail="Could not load Auth signing keys") from exc
    except (InvalidTokenError, jwt.exceptions.PyJWKClientError) as exc:
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
