from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI, Query, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import router as api_router
from app.auth import app_password_middleware
from app.db.store import init_db
from app.discovery.beacon import start_discovery_beacon, stop_discovery_beacon
from app.jobs.scheduler import start_scheduler, stop_scheduler
from app.services import dashboard as dash
from app.services import stock_screen as stock_svc

WEB_DIR = Path(__file__).resolve().parent / "web"
templates = Jinja2Templates(directory=str(WEB_DIR / "templates"))

app = FastAPI(title="stockserver", version="0.3.0", description="投资观察后台（公开数据）")
app.middleware("http")(app_password_middleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(api_router)
app.mount("/static", StaticFiles(directory=str(WEB_DIR / "static")), name="static")


@app.on_event("startup")
async def _startup() -> None:
    init_db()
    start_scheduler()
    start_discovery_beacon()


@app.on_event("shutdown")
async def _shutdown() -> None:
    await stop_discovery_beacon()
    stop_scheduler()


@app.get("/", response_class=HTMLResponse)
async def page_home(request: Request, refresh: bool = Query(False)) -> HTMLResponse:
    data = await dash.build_dashboard(force_refresh=refresh)
    return templates.TemplateResponse(
        request,
        "dashboard.html",
        {"data": data},
    )


@app.get("/alerts", response_class=HTMLResponse)
async def page_alerts(request: Request, refresh: bool = Query(False)) -> HTMLResponse:
    data = await dash.build_alerts(force_refresh=refresh)
    return templates.TemplateResponse(
        request,
        "alerts.html",
        {"data": data},
    )


@app.get("/etf/{code}", response_class=HTMLResponse)
async def page_etf(request: Request, code: str, refresh: bool = Query(False)) -> HTMLResponse:
    detail = await dash.build_etf_detail(code, force_refresh=refresh)
    if detail is None:
        return templates.TemplateResponse(
            request,
            "not_found.html",
            {"code": code},
            status_code=404,
        )
    return templates.TemplateResponse(
        request,
        "etf_detail.html",
        {"etf": detail},
    )


@app.get("/stocks", response_class=HTMLResponse)
async def page_stocks(request: Request, refresh: bool = Query(False)) -> HTMLResponse:
    data = await stock_svc.ensure_pool(force=refresh) if refresh else stock_svc.get_cached_pool()
    return templates.TemplateResponse(
        request,
        "stocks.html",
        {"data": data},
    )


@app.get("/stocks/{code}", response_class=HTMLResponse)
async def page_stock_detail(request: Request, code: str) -> HTMLResponse:
    detail = stock_svc.get_stock_detail(code)
    if detail is None:
        return templates.TemplateResponse(
            request,
            "not_found.html",
            {"code": code},
            status_code=404,
        )
    return templates.TemplateResponse(
        request,
        "stock_detail.html",
        {"stock": detail, "data": {"disclaimer": detail.get("disclaimer")}},
    )
