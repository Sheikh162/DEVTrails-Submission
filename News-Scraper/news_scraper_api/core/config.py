import os
from functools import lru_cache
from pathlib import Path

from dotenv import load_dotenv
from pydantic import BaseModel


BASE_DIR = Path(__file__).resolve().parents[2]

# Prefer the local News-Scraper/.env file, then fall back to the repo-level .env.
ENV_CANDIDATES = [
    BASE_DIR / ".env",
    BASE_DIR.parent / ".env",
]

for env_path in ENV_CANDIDATES:
    if env_path.exists():
        load_dotenv(dotenv_path=env_path, override=False)
        break


class Settings(BaseModel):
    app_name: str = "NewsPulse AI"
    app_version: str = "2.0.0"
    gemini_api_key: str | None = os.getenv("GEMINI_API_KEY")
    gemini_model: str = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
    default_news_limit: int = 15


@lru_cache
def get_settings() -> Settings:
    return Settings()
