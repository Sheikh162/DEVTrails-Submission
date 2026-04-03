import urllib.parse

import feedparser

from news_scraper_api.schemas.news import Article


def fetch_local_news(location: str, max_articles: int = 15) -> list[Article]:
    """
    Search Google News RSS for a location and return the top headlines.
    """
    query = urllib.parse.quote(f'"{location}"')
    rss_url = (
        f"https://news.google.com/rss/search?q={query}&hl=en-US&gl=US&ceid=US:en"
    )

    feed = feedparser.parse(rss_url)
    articles: list[Article] = []

    for entry in feed.entries[:max_articles]:
        articles.append(
            Article(
                title=entry.title,
                link=entry.link,
                published=getattr(entry, "published", "No Date"),
            )
        )

    return articles


def format_articles_for_analysis(articles: list[Article]) -> str:
    return "\n".join(f"- {article.title} ({article.published})" for article in articles)
