import streamlit as st
import os
from news_extractor import fetch_local_news
from disruption_analyzer import check_for_disruption
from dotenv import load_dotenv

# Load environment variables (Local development)
load_dotenv()

# --- Page Config ---
st.set_page_config(
    page_title="AI Disruption Monitor",
    page_icon="🚨",
    layout="centered"
)

# --- App Styling ---
st.markdown("""
<style>
    .main {
        background-color: #f5f7f9;
    }
    .stButton>button {
        width: 100%;
        border-radius: 5px;
        height: 3em;
        background-color: #FF4B4B;
        color: white;
    }
    .disruption-yes {
        padding: 20px;
        border-radius: 10px;
        background-color: #ffecec;
        border: 1px solid #ff4b4b;
        color: #911;
    }
    .disruption-no {
        padding: 20px;
        border-radius: 10px;
        background-color: #e8f5e9;
        border: 1px solid #2e7d32;
        color: #1b5e20;
    }
</style>
""", unsafe_allow_html=True)

# --- Header ---
st.title("🚨 AI Disruption Monitor")
st.subheader("Global News-Based Disruption Detector")
st.write("Enter a location and our AI will scan local news for natural disasters, civil unrest, or major infrastructure failures.")

# --- Sidebar / Settings ---
with st.sidebar:
    st.header("Settings")
    # In Streamlit Cloud, the key is set in 'Secrets'.
    # Locally, it's pulled from os.getenv (handled by load_dotenv).
    api_key_status = "✅ API Key Found" if os.getenv("GEMINI_API_KEY") else "❌ API Key Missing"
    st.write(api_key_status)
    
    st.divider()
    st.write("💡 **Tip:** Try locations like 'Sudan', 'Tokyo', or 'London'.")

# --- User Input ---
location = st.text_input("📍 Enter City or Country", placeholder="e.g. New York, Paris, Gaza")

if st.button("Analyze Location"):
    if not location.strip():
        st.warning("Please enter a location first!")
    else:
        with st.status(f"Scanning news in {location}...", expanded=True) as status:
            try:
                # 1. Fetch News
                st.write("🔍 Fetching latest local headlines...")
                articles = fetch_local_news(location, max_articles=15)
                
                if not articles:
                    st.info(f"No recent news articles found for {location}. This usually means no major disruptions are reported.")
                    status.update(label="Scan Complete (Clean)", state="complete")
                else:
                    # 2. Analyze with Gemini
                    st.write(f"🧠 Found {len(articles)} articles. Analyzing with Gemini AI...")
                    formatted_text = "\n".join([f"- {a['title']} ({a['published']})" for a in articles])
                    
                    result = check_for_disruption(location, formatted_text)
                    status.update(label="Analysis Complete", state="complete")
                    
                    # 3. Display Results
                    st.divider()
                    if result.get("disruption_found") is True:
                        st.markdown(f"""
                        <div class="disruption-yes">
                            <h3>⚠️ DISRUPTION DETECTED</h3>
                            <p><b>Reasoning:</b> {result.get('reasoning')}</p>
                        </div>
                        """, unsafe_allow_html=True)
                    else:
                        st.markdown(f"""
                        <div class="disruption-no">
                            <h3>✅ NO DISRUPTION FOUND</h3>
                            <p><b>Reasoning:</b> {result.get('reasoning')}</p>
                        </div>
                        """, unsafe_allow_html=True)
                    
                    # 4. Show raw headlines in an expander
                    with st.expander("Show Analyzed Headlines"):
                        for a in articles:
                            st.write(f"🔗 [{a['title']}]({a['link']})")

            except Exception as e:
                st.error(f"Error: {e}")
                status.update(label="Error Occurred", state="error")

# --- Footer ---
st.divider()
st.caption("Powered by Gemini AI & Real-time News Feeds.")
