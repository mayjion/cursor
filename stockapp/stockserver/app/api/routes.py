from __future__ import annotations

from fastapi import APIRouter, Header, HTTPException, Query, Request

from app.auth import verify_app_password
from app.config import SETTINGS, reload_configs
from app.services import dashboard as dash
from app.services import limitup_board as limitup_svc
from app.services import stock_screen as stock_svc

router = APIRouter(prefix="/api")


@router.get("/health")
async def health() -> dict:
    from app.discovery.beacon import health_payload

    payload = health_payload()
    payload["auth_required"] = True
    return payload


@router.post("/auth")
async def api_auth(
    request: Request,
    x_app_password: str | None = Header(default=None),
) -> dict:
    password = x_app_password or ""
    try:
        data = await request.json()
        if isinstance(data, dict):
            raw = data.get("password")
            if raw is not None and str(raw).strip():
                password = str(raw).strip()
    except Exception:  # noqa: BLE001
        pass
    if not verify_app_password(password):
        raise HTTPException(status_code=401, detail="invalid app password")
    return {"ok": True, "authenticated": True}


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


@router.get("/boards/limitup")
async def api_limitup_board(refresh: bool = Query(False)) -> dict:
    if refresh:
        return await limitup_svc.ensure_board(force=True)
    return limitup_svc.get_cached_board()


@router.get("/stocks/{code}/analysis")
async def api_stock_analysis(
    code: str,
    refresh: bool = Query(False),
) -> dict:
    from app.services import stock_analysis as analysis_svc

    try:
        return await analysis_svc.build_stock_analysis(code, force=refresh)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=502, detail=f"analysis failed: {exc}") from exc


@router.get("/stocks/{code}")
async def api_stock_detail(code: str) -> dict:
    detail = stock_svc.get_stock_detail(code)
    if detail is None:
        raise HTTPException(status_code=404, detail="stock not in recommended pool")
    return detail


@router.get("/watchlist")
async def api_watchlist(refresh: bool = Query(True)) -> dict:
    from app.services import watchlist as wl

    return await wl.list_watchlist(with_quotes=refresh)


@router.post("/watchlist")
async def api_watchlist_add(request: Request) -> dict:
    from app.services import watchlist as wl

    try:
        body = await request.json()
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail="invalid json") from exc
    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="invalid body")
    code = str(body.get("code") or "").strip()
    if not code:
        raise HTTPException(status_code=400, detail="code required")
    try:
        return await wl.add_watchlist_item(
            code=code,
            name=body.get("name"),
            market=body.get("market"),
            asset_type=body.get("asset_type"),
            index_name=str(body.get("index_name") or ""),
            note=str(body.get("note") or ""),
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/watchlist/batch")
async def api_watchlist_batch(request: Request) -> dict:
    from app.services import watchlist as wl

    try:
        body = await request.json()
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail="invalid json") from exc
    items = body.get("items") if isinstance(body, dict) else None
    if not isinstance(items, list):
        raise HTTPException(status_code=400, detail="items list required")
    return await wl.add_watchlist_batch(items)


@router.delete("/watchlist/{code}")
async def api_watchlist_delete(code: str) -> dict:
    from app.services import watchlist as wl

    result = wl.remove_watchlist_item(code)
    if not result.get("ok"):
        raise HTTPException(status_code=404, detail="not in watchlist")
    return result


@router.post("/watchlist/delete")
async def api_watchlist_delete_batch(request: Request) -> dict:
    from app.services import watchlist as wl

    try:
        body = await request.json()
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail="invalid json") from exc
    codes = body.get("codes") if isinstance(body, dict) else None
    if not isinstance(codes, list):
        raise HTTPException(status_code=400, detail="codes list required")
    return wl.remove_watchlist_batch([str(c) for c in codes])


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


@router.post("/admin/limitup-board")
async def admin_limitup_board(x_admin_token: str | None = Header(default=None)) -> dict:
    expected = SETTINGS.get("admin_token") or ""
    if expected and x_admin_token != expected:
        raise HTTPException(status_code=401, detail="invalid admin token")
    result = await limitup_svc.ensure_board(force=True)
    return {
        "ok": True,
        "focus_n": len(result.get("focus") or []),
        "watch_n": len(result.get("watch") or []),
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
