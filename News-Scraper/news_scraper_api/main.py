from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from news_scraper_api.api.routes import router
from news_scraper_api.core.config import BASE_DIR, get_settings


def create_app() -> FastAPI:
    settings = get_settings()

    application = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        description="FastAPI service for disruption monitoring based on local news.",
    )
    application.include_router(router)
    application.mount(
        "/static",
        StaticFiles(directory=str(BASE_DIR / "news_scraper_api" / "static")),
        name="static",
    )
    return application


app = create_app()
