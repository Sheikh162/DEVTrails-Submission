import json

import google.generativeai as genai

from news_scraper_api.core.config import get_settings
from news_scraper_api.schemas.disruption import DisruptionResult


def check_for_disruption(location: str, formatted_news_text: str) -> DisruptionResult:
    """
    Analyze the latest headlines for disruptions affecting a location.
    """
    settings = get_settings()
    api_key = settings.gemini_api_key

    if not api_key or api_key == "your_api_key_here":
        raise ValueError(
            "Valid GEMINI_API_KEY is missing. Please add it to your .env file."
        )

    genai.configure(api_key=api_key)
    model = genai.GenerativeModel(settings.gemini_model)

    prompt = f"""
    You are an AI disruption monitoring agent.
    A user wants to know if there is an ongoing or imminent disruption in the location: "{location}".

    A disruption is EXCLUSIVELY defined as:
    - Deliveries suspended (Swiggy, Zomato, or general e-commerce)
    - Government-ordered shutdowns or lockdowns
    - Natural disasters (floods, storms, earthquakes) that halt infrastructure
    - Major civil unrest or large-scale protests that stop commercial activity
    - Large-scale power or infrastructure outages

    SPECIAL FOCUS: You MUST flag true if news indicates that delivery services
    (like Swiggy or Zomato) have halted or if the government has announced a
    city-wide suspension of services.

    Given the following recent news headlines about this location, determine if
    there is a disruption. Be nuanced. Standard crime, minor localized accidents,
    or political debates do NOT constitute a disruption for our purposes.

    If there is not enough information to conclude there is a disruption, default
    to false.

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
        parsed_response = json.loads(response.text)
        return DisruptionResult(**parsed_response)
    except Exception as exc:
        return DisruptionResult(
            disruption_found=False,
            reasoning=f"Error calling AI API: {exc}",
            error=True,
        )
