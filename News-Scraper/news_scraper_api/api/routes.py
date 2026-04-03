from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from news_scraper_api.core.config import BASE_DIR, get_settings
from news_scraper_api.schemas.disruption import ScanRequest, ScanResponse
from news_scraper_api.services.disruption_service import check_for_disruption
from news_scraper_api.services.news_service import (
    fetch_local_news,
    format_articles_for_analysis,
)


router = APIRouter()
templates = Jinja2Templates(directory=str(BASE_DIR / "news_scraper_api" / "templates"))


@router.get("/", response_class=HTMLResponse)
def home(request: Request) -> HTMLResponse:
    settings = get_settings()
    return templates.TemplateResponse(
        request=request,
        name="index.html",
        context={
            "app_name": settings.app_name,
            "app_version": settings.app_version,
            "api_ready": bool(settings.gemini_api_key),
        },
    )


@router.get("/health")
def health_check() -> dict:
    settings = get_settings()
    return {
        "status": "ok",
        "app_name": settings.app_name,
        "version": settings.app_version,
        "gemini_configured": bool(settings.gemini_api_key),
    }


@router.post("/api/v1/scan", response_model=ScanResponse)
def scan_location(payload: ScanRequest) -> ScanResponse:
    location = payload.location.strip()
    if not location:
        raise HTTPException(status_code=400, detail="Location is required.")

    articles = fetch_local_news(location=location, max_articles=payload.max_articles)
    if not articles:
        return ScanResponse(
            location=location,
            article_count=0,
            articles=[],
            analysis=None,
        )

    formatted_news = format_articles_for_analysis(articles)
    analysis = check_for_disruption(location, formatted_news)

    return ScanResponse(
        location=location,
        article_count=len(articles),
        articles=articles,
        analysis=analysis,
    )
