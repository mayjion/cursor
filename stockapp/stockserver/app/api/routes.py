from __future__ import annotations

from fastapi import APIRouter, Header, HTTPException, Query

from app.config import SETTINGS, reload_configs
from app.services import dashboard as dash
from app.services import stock_screen as stock_svc

router = APIRouter(prefix="/api")


@router.get("/health")
async def health() -> dict:
    from app.discovery.beacon import health_payload

    return health_payload()


@router.get("/universe")
async def api_universe() -> dict:
    return dash.build_universe_payload()


@router.get("/dashboard")
async def api_dashboard(refresh: bool = Query(False)) -> dict:
    return await dash.build_dashboard(force_refresh=refresh)


@router.get("/etf/{code}")
async def api_etf(code: str, refresh: bool = Query(False)) -> dict:
    detail = await dash.build_etf_detail(code, force_refresh=refresh)
    if detail is None:
        raise HTTPException(status_code=404, detail="ETF not in universe")
    return detail


@router.get("/temperature")
async def api_temperature(refresh: bool = Query(False)) -> dict:
    data = await dash.build_dashboard(force_refresh=refresh)
    return data["temperature"]


@router.get("/allocation")
async def api_allocation(refresh: bool = Query(False)) -> dict:
    data = await dash.build_dashboard(force_refresh=refresh)
    return data["allocation"]


@router.get("/alerts")
async def api_alerts(refresh: bool = Query(False)) -> dict:
    return await dash.build_alerts(force_refresh=refresh)


@router.get("/timing")
async def api_timing(refresh: bool = Query(False)) -> dict:
    return await dash.build_timing(force_refresh=refresh)


@router.get("/timing/backtest")
async def api_timing_backtest(
    window: int | None = Query(None),
    refresh: bool = Query(False),
) -> dict:
    return await dash.build_timing_backtest(window=window, force=refresh)


@router.get("/stocks/pool")
async def api_stock_pool(refresh: bool = Query(False)) -> dict:
    if refresh:
        return await stock_svc.ensure_pool(force=True)
    return stock_svc.get_cached_pool()


@router.get("/stocks/{code}")
async def api_stock_detail(code: str) -> dict:
    detail = stock_svc.get_stock_detail(code)
    if detail is None:
        raise HTTPException(status_code=404, detail="stock not in recommended pool")
    return detail


@router.post("/admin/stock-screen")
async def admin_stock_screen(x_admin_token: str | None = Header(default=None)) -> dict:
    expected = SETTINGS.get("admin_token") or ""
    if expected and x_admin_token != expected:
        raise HTTPException(status_code=401, detail="invalid admin token")
    result = await stock_svc.ensure_pool(force=True)
    return {
        "ok": True,
        "pool_n": len(result.get("pool") or []),
        "stats": result.get("stats"),
        "updated_at": result.get("updated_at"),
    }


@router.post("/admin/collect")
async def admin_collect(x_admin_token: str | None = Header(default=None)) -> dict:
    expected = SETTINGS.get("admin_token") or ""
    if expected and x_admin_token != expected:
        raise HTTPException(status_code=401, detail="invalid admin token")
    return await dash.collect_and_score(force_quote=True)


@router.post("/admin/reload")
async def admin_reload(x_admin_token: str | None = Header(default=None)) -> dict:
    expected = SETTINGS.get("admin_token") or ""
    if expected and x_admin_token != expected:
        raise HTTPException(status_code=401, detail="invalid admin token")
    reload_configs()
    return {"ok": True, "reloaded": True}
