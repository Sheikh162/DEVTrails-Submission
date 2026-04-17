# Vritti ML Pricing Engine

Python model and FastAPI service for Vritti's dynamic weekly premium calculation. This component turns rider profile, zone infrastructure, weather forecast, and civic disruption signals into a risk multiplier, disruption probability, alert multiplier, and final INR premium.

## Model Flow

1. `generate_data.py` creates synthetic rider-week training data for the prototype.
2. `train.py` engineers features, applies imputation defaults, trains risk and disruption models, and writes model artifacts under `models/`.
3. `fast_APP.py` loads those artifacts and exposes prediction endpoints consumed by the Node backend.

The checked-in CSV files make the training assumptions visible and reproducible. The trained `models/` directory is expected at runtime but may be generated locally rather than committed.

## Inputs

The engine combines:

- Rider profile: platform, tier, shift, active hours, delivery radius, loyalty, earnings, volatility, claim history.
- Zone infrastructure: elevation, waterlogging history, road quality, heat-island index.
- Weather forecast: 7-day rain, max temperature, wind gusts, AQI, IMD alert level.
- Civic signals: bandh probability, platform outages, festival flag, political event flag.

## Outputs

- `w_risk`: weekly risk multiplier.
- `disruption_prob`: probability of income-loss disruption.
- `disruption_flag`: boolean risk decision.
- `r_alert`: rule-based IMD/heat alert multiplier.
- `loyalty_discount`: discount derived from active tenure.
- `premium_final_inr`: final weekly premium.
- `top_risk_factors`: concise explanation data for demos/debugging.

## Setup

Install the Python dependencies used by training and serving:

```bash
pip install fastapi uvicorn joblib pandas numpy scikit-learn xgboost shap matplotlib
```

Generate synthetic data if needed:

```bash
python generate_data.py
```

Train models:

```bash
python train.py
```

Start the API:

```bash
python fast_APP.py
```

The service listens on `http://0.0.0.0:8000` by default. Configure the backend with:

```env
PRICING_ENGINE_URL=http://localhost:8000
```

## API

- `GET /health` returns model readiness and drift baseline metadata.
- `GET /r_alert/{zone_id}?imd_level=0&max_temp=30` returns the alert multiplier without running full prediction.
- `POST /predict` predicts premium and risk for one rider.
- `POST /predict/batch` predicts for multiple riders and returns per-rider fallback results when individual records fail.

Example single prediction shape:

```json
{
  "rider_id": "demo-rider-1",
  "home_zone_id": "chennai_central",
  "delivery_platform": "swiggy",
  "tier": "silver",
  "primary_shift": "evening",
  "avg_delivery_radius_km": 8,
  "avg_daily_active_hours": 8,
  "loyalty_weeks_active": 4,
  "avg_weekly_earnings_4wk": 6500,
  "earnings_volatility_index": 0.3,
  "claim_history_score": 0.1,
  "zone_elevation_index": 5,
  "waterlogging_incidents_3yr": 5,
  "road_quality_score": 5,
  "zone_heat_island_index": 1.5,
  "rain_mm_7day_forecast": 20,
  "max_temp_forecast": 34,
  "wind_gust_kmh_forecast": 20,
  "aqi_forecast_avg": 120,
  "imd_alert_level_forecast": 0,
  "bandh_probability_score": 0.05,
  "platform_outage_7d_count": 1,
  "festival_calendar_flag": 0,
  "political_event_flag": 0
}
```

## Files

- `generate_data.py` creates synthetic training datasets.
- `training_data.csv` is the raw synthetic training dataset.
- `training_data_encoded.csv` is the encoded inspection/training variant.
- `train.py` contains feature engineering, model training, artifact writing, and prediction function construction.
- `fast_APP.py` is the FastAPI model server.
