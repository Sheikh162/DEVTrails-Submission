import os
import json
import google.generativeai as genai
from pydantic import BaseModel

def check_for_disruption(location: str, formatted_news_text: str) -> dict:
    """
    Calls Google Gemini API to analyze news and determine if there's a disruption
    in the requested location.
    """
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key or api_key == "your_api_key_here":
        raise ValueError("Valid GEMINI_API_KEY is missing. Please add it to your .env file.")

    genai.configure(api_key=api_key)

    # Use a solid model capable of text analysis and JSON output
    model = genai.GenerativeModel("gemini-2.5-flash") # Cost-effective and fast

    prompt = f"""
    You are an AI disruption monitoring agent. 
    A user wants to know if there is an ongoing or imminent disruption in the location: "{location}".

    A disruption can be:
    - Natural disaster (earthquake, hurricane, flood, storm)
    - Civil unrest or large protests
    - Terrorist attacks or active shooter situations
    - Major transportation strikes or massive delays
    - Large-scale power/infrastructure outages
    - Major political instability disrupting normal life
    
    Given the following recent news headlines about this location, determine if there is a disruption.
    Be nuanced. Standard crime, minor traffic accidents, or political debates do NOT constitute a location-wide disruption. 

    If there is not enough information to conclude there is a disruption, default to false.

    Output your response STRICTLY as valid JSON with the following keys exactly:
    "disruption_found": true or false
    "reasoning": "A concise, 1-2 sentence explanation of why based on the headlines."

    News Articles:
    {formatted_news_text}
    """

    try:
        response = model.generate_content(
            prompt,
            generation_config=genai.types.GenerationConfig(
                response_mime_type="application/json",
            ),
        )
        return json.loads(response.text)
    except Exception as e:
        return {
            "disruption_found": False,
            "reasoning": f"Error calling AI API: {str(e)}",
            "error": True
        }
