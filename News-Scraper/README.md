# NewsPulse AI Scraper

FastAPI service that scans Google News RSS results for local disruption signals and uses Gemini to classify whether a city has an income-impacting event such as transport strikes, unrest, flooding, cyclones, shutdowns, or other civic disruptions.

## Role In Vritti

Weather APIs do not catch every reason a delivery rider loses work. This service acts as the civic-intelligence layer for the backend by converting local news headlines and article summaries into structured disruption analysis.

## Tech Stack

- FastAPI and Uvicorn
- Jinja2 HTML templates
- Google News RSS through `feedparser`
- Gemini through `google-generativeai`
- Pydantic request/response schemas

## Setup

Install dependencies:

```bash
pip install -r requirements.txt
```

Create `News-Scraper/.env` or a root `.env` file:

```env
GEMINI_API_KEY=your_key_here
GEMINI_MODEL=gemini-2.5-flash
```

Run locally:

```bash
python main.py
```

Open:

```text
http://127.0.0.1:8000
```

## API

- `GET /` renders the browser UI.
- `GET /health` returns app health and Gemini configuration status.
- `POST /api/v1/scan` scans a location and returns fetched articles plus disruption analysis.

Example:

```json
{
  "location": "Chennai",
  "max_articles": 15
}
```

## Project Structure

```text
News-Scraper/
|-- app.py
|-- main.py
|-- config.py
|-- news_extractor.py
|-- disruption_analyzer.py
|-- test_logic.py
|-- test_runner.py
|-- test_results.md
|-- requirements.txt
`-- news_scraper_api/
    |-- api/
    |-- core/
    |-- schemas/
    |-- services/
    |-- static/
    `-- templates/
```

See [news_scraper_api/README.md](./news_scraper_api/README.md) for the package layout.

## Compatibility Files

`app.py`, `config.py`, `news_extractor.py`, and `disruption_analyzer.py` keep older import/deployment paths working while the main implementation lives under `news_scraper_api/`.
