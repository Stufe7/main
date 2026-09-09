from datetime import UTC, datetime, timedelta

import jwt
import pytest
from jwt import InvalidTokenError

from app.authn import decode_access_token
from app.settings import settings


def test_hs256_access_token_decodes(monkeypatch: pytest.MonkeyPatch) -> None:
    secret = "test-hs256-secret"
    monkeypatch.setattr(settings, "supabase_jwt_secret", secret)
    token = jwt.encode(
        {
            "sub": "11111111-1111-1111-1111-111111111111",
            "email": "marc@example.com",
            "aud": "authenticated",
            "role": "authenticated",
            "exp": datetime.now(UTC) + timedelta(minutes=5),
        },
        secret,
        algorithm="HS256",
    )
    claims = decode_access_token(token)
    assert claims["email"] == "marc@example.com"


def test_garbage_token_is_invalid() -> None:
    with pytest.raises(InvalidTokenError):
        decode_access_token("not-a-jwt")
