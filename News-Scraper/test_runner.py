import sys
from dotenv import load_dotenv
from news_extractor import fetch_local_news
from disruption_analyzer import check_for_disruption

def run_test(city_name: str, file_handle):
    print(f"Fetching news for {city_name}...")
    articles = fetch_local_news(city_name, max_articles=15)
    formatted_text = "\n".join([f"- {a['title']} ({a['published']})" for a in articles])
    
    print(f"Calling Gemini for {city_name}...")
    result = check_for_disruption(city_name, formatted_text)
    
    file_handle.write(f"# Real Test Results: {city_name}\n\n")
    file_handle.write(f"**Disruption Detected**: `{result.get('disruption_found')}`\n\n")
    file_handle.write(f"**AI Reasoning**: {result.get('reasoning')}\n\n")
    file_handle.write("### Extracted Headlines:\n")
    file_handle.write(formatted_text + "\n\n---\n\n")

if __name__ == "__main__":
    load_dotenv()
    with open("test_results.md", "w", encoding="utf-8") as f:
        run_test("Kelambakkam", f)
    print("Test finished and saved to test_results.md")
