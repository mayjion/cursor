"""App 连接密码校验（首次对接）。"""

from __future__ import annotations

from fastapi import Header, HTTPException, Request
from fastapi.responses import JSONResponse

from app.config import SETTINGS

DEFAULT_APP_PASSWORD = "sprite123"
HEADER_NAME = "x-app-password"


def expected_app_password() -> str:
    value = SETTINGS.get("app_password")
    if value is None or str(value).strip() == "":
        return DEFAULT_APP_PASSWORD
    return str(value)


def verify_app_password(password: str | None) -> bool:
    return (password or "") == expected_app_password()


def require_app_password(x_app_password: str | None = Header(default=None)) -> None:
    if not verify_app_password(x_app_password):
        raise HTTPException(status_code=401, detail="invalid app password")


async def app_password_middleware(request: Request, call_next):
    path = request.url.path
    if path.startswith("/api/") and path not in ("/api/health", "/api/auth"):
        pwd = request.headers.get(HEADER_NAME)
        if not verify_app_password(pwd):
            return JSONResponse(
                status_code=401,
                content={"detail": "invalid app password", "auth_required": True},
            )
    return await call_next(request)
