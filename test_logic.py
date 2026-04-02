import os
import sys
from pathlib import Path

# Add News-Scraper to path so we can import the logic
SCRAPER_DIR = str(Path(__file__).parent / "News-Scraper")
if SCRAPER_DIR not in sys.path:
    sys.path.append(SCRAPER_DIR)

from dotenv import load_dotenv
from disruption_analyzer import check_for_disruption

# Load env
env_path = Path(__file__).parent / '.env'
load_dotenv(dotenv_path=env_path)

def test_refined_logic():
    print("--- Testing Refined Delivery Disruption Logic ---")
    
    # Test Case 1: Delivery Suspension (Should be True)
    location_1 = "Chennai"
    news_1 = """
    - Government orders immediate shutdown of non-essential services due to heavy rain.
    - Swiggy and Zomato suspend all operations in Chennai until further notice.
    - Delivery partners advised to stay home as flooding increases.
    """
    print(f"\nTesting {location_1} with delivery suspension news...")
    result_1 = check_for_disruption(location_1, news_1)
    print(f"Result Disruption Found: {result_1.get('disruption_found')}")
    print(f"AI Reasoning: {result_1.get('reasoning')}")

    # Test Case 2: Normal News (Should be False)
    location_2 = "Chennai"
    news_2 = """
    - New shopping mall opens in T. Nagar.
    - Minor traffic congestion near Central Station.
    - Local authorities announce street-light maintenance.
    """
    print(f"\nTesting {location_2} with regular news...")
    result_2 = check_for_disruption(location_2, news_2)
    print(f"Result Disruption Found: {result_2.get('disruption_found')}")
    print(f"AI Reasoning: {result_2.get('reasoning')}")

if __name__ == "__main__":
    if not os.getenv("GEMINI_API_KEY"):
        print("Error: GEMINI_API_KEY not found in environment.")
    else:
        test_refined_logic()
