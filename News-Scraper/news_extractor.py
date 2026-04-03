from news_scraper_api.services.news_service import fetch_local_news

if __name__ == "__main__":
    # Simple test
    news = fetch_local_news("Tokyo")
    for n in news:
        print(f"- {n.title} ({n.published})")
