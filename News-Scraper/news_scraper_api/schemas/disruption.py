from pydantic import BaseModel, Field

from news_scraper_api.schemas.news import Article


class ScanRequest(BaseModel):
    location: str = Field(..., min_length=1, description="City or country to scan.")
    max_articles: int = Field(default=15, ge=1, le=50)


class DisruptionResult(BaseModel):
    disruption_found: bool
    reasoning: str
    error: bool = False


class ScanResponse(BaseModel):
    location: str
    article_count: int
    articles: list[Article]
    analysis: DisruptionResult | None = None
