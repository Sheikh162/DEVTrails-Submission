# News Scraper API Package

Implementation package for the NewsPulse AI FastAPI service.

## Layout

- `main.py` creates the FastAPI application and includes the route module.
- `api/routes.py` defines the HTML UI, health check, and scan endpoint.
- `core/config.py` loads `.env` settings from `News-Scraper/.env` or the repository root.
- `schemas/news.py` and `schemas/disruption.py` define Pydantic request/response contracts.
- `services/news_service.py` fetches and formats Google News RSS articles.
- `services/disruption_service.py` calls Gemini and returns structured disruption analysis.
- `static/styles.css` styles the browser UI.
- `templates/index.html` renders the scan form and result page.

## Endpoint Flow

`POST /api/v1/scan` validates the location, fetches local articles, formats them for analysis, sends the article context to Gemini, and returns articles plus the disruption result. Empty news results return a successful response with `analysis: null`.
