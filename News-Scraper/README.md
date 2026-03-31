# NewsPulse AI FastAPI Service

This folder contains the news disruption monitor migrated from Streamlit to FastAPI. The scraper still reads Google News RSS, the analyzer still uses Gemini, and the UI is now served through a FastAPI HTML template with static CSS.

## Project Structure

```text
News-Scraper/
├── app.py
├── main.py
├── news_scraper_api/
│   ├── api/
│   │   └── routes.py
│   ├── core/
│   │   └── config.py
│   ├── schemas/
│   │   ├── disruption.py
│   │   └── news.py
│   ├── services/
│   │   ├── disruption_service.py
│   │   └── news_service.py
│   ├── static/
│   │   └── styles.css
│   └── templates/
│       └── index.html
├── disruption_analyzer.py
├── news_extractor.py
└── test_runner.py
```

## Endpoints

- `GET /` renders the web interface.
- `GET /health` returns service health and Gemini configuration status.
- `POST /api/v1/scan` scans a location and returns headlines plus disruption analysis.

Example request body:

```json
{
  "location": "Chennai",
  "max_articles": 15
}
```

## Run Locally

1. Install dependencies:

```bash
pip install -r requirements.txt
```

2. Add `GEMINI_API_KEY` to the root `.env` file one level above this folder.

3. Start the server:

```bash
python main.py
```

4. Open `http://127.0.0.1:8000`.

## Notes

- `app.py` exposes the ASGI app for deployment targets.
- `main.py` is the local development runner using Uvicorn.
- `news_extractor.py` and `disruption_analyzer.py` remain as compatibility wrappers around the new service layer.
