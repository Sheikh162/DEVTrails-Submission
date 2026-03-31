import argparse
import sys
from dotenv import load_dotenv

from news_extractor import fetch_local_news
from disruption_analyzer import check_for_disruption

def main():
    # Load environment variables
    load_dotenv()
    
    parser = argparse.ArgumentParser(description="Check a location for active disruptions.")
    parser.add_argument("location", help="The city or country to check (e.g., 'London', 'Kyiv', 'Tokyo')")
    args = parser.parse_args()
    
    location = args.location
    print(f"[*] Fetching latest news for: {location}")
    
    try:
        articles = fetch_local_news(location, max_articles=15)
        if not articles:
            print("[!] No news articles found. Assuming no disruption.")
            sys.exit(0)
    except Exception as e:
        print(f"[!] Error fetching news: {e}")
        sys.exit(1)
        
    print(f"[*] Found {len(articles)} articles. Analyzing...")
    
    # Format news text for the prompt
    formatted_text = "\n".join([f"- {a['title']} ({a['published']})" for a in articles])
    
    try:
        result = check_for_disruption(location, formatted_text)
        
        # Output results nicely
        print("\n" + "="*50)
        print(f"LOCATION: {location.upper()}")
        print("DISRUPTION DETECTED: ", end="")
        
        if result.get("disruption_found") is True:
            print("\033[91mYES\033[0m") # Red text
            print(f"REASON: {result.get('reasoning')}")
        else:
            print("\033[92mNO\033[0m")  # Green text
            print(f"REASON: {result.get('reasoning')}")
        print("="*50)

    except ValueError as ve:
        print(f"\n[!] Configuration Error: {ve}")
        sys.exit(1)
    except Exception as e:
        print(f"\n[!] Unexpected Error during analysis: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
