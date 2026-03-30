import urllib.parse
import feedparser

def fetch_local_news(location: str, max_articles: int = 15) -> list[dict]:
    """
    Searches Google News RSS for a specific location and returns the top headlines.
    """
    # URL encode the query string
    query = urllib.parse.quote(f'"{location}"')
    
    # We query google news RSS
    # Using 'hl=en-US&gl=US&ceid=US:en' keeps it english but retrieves global news
    rss_url = f"https://news.google.com/rss/search?q={query}&hl=en-US&gl=US&ceid=US:en"
    
    # Parse the feed
    feed = feedparser.parse(rss_url)
    
    articles = []
    for entry in feed.entries[:max_articles]:
        article = {
            "title": entry.title,
            "link": entry.link,
            "published": getattr(entry, "published", "No Date"),
        }
        articles.append(article)
        
    return articles

if __name__ == "__main__":
    # Simple test
    news = fetch_local_news("Tokyo")
    for n in news:
        print(f"- {n['title']} ({n['published']})")
