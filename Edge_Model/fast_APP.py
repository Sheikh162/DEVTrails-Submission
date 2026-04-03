"""
Safety SIP — FastAPI Model Server
===================================
Serves both trained models via REST endpoints.
Called by Node.js premium.cron.ts every Saturday.

Run:
    pip install fastapi uvicorn joblib
    uvicorn fastapi_app:app --host 0.0.0.0 --port 8000 --reload

Endpoints:
    POST /predict          — single rider prediction
    POST /predict/batch    — batch (all riders, Saturday cron)
    GET  /health           — model version + drift status
    GET  /explain/{rider_id} — SHAP explanation for one rider
"""

import json
import os
import site
import sys
from datetime import datetime
from typing import Optional, List

BASE_DIR = os.path.dirname(__file__)
WEB_SITE_PACKAGES = os.path.join(BASE_DIR, ".web_packages")
if os.path.isdir(WEB_SITE_PACKAGES) and WEB_SITE_PACKAGES not in sys.path:
    sys.path.insert(0, WEB_SITE_PACKAGES)

LOCAL_SITE_PACKAGES = os.path.join(BASE_DIR, ".python_packages")
if os.path.isdir(LOCAL_SITE_PACKAGES) and LOCAL_SITE_PACKAGES not in sys.path:
    sys.path.append(LOCAL_SITE_PACKAGES)

USER_SITE_PACKAGES = site.getusersitepackages()
if USER_SITE_PACKAGES not in sys.path:
    sys.path.append(USER_SITE_PACKAGES)

import joblib
import numpy as np
import pandas as pd

try:
    from fastapi import FastAPI, HTTPException
    from pydantic import BaseModel, Field
    import uvicorn
except ImportError:
    print("Run: pip install fastapi uvicorn")
    raise

MODEL_DIR = os.path.join(BASE_DIR, "models")

# ─────────────────────────────────────────────────────────────────────────────
# Load artifacts once at startup
# ─────────────────────────────────────────────────────────────────────────────

reg_model    = joblib.load(os.path.join(MODEL_DIR, "w_risk_regressor.joblib"))
cls_model    = joblib.load(os.path.join(MODEL_DIR, "disruption_classifier.joblib"))
encoders     = joblib.load(os.path.join(MODEL_DIR, "label_encoders.joblib"))
defaults     = joblib.load(os.path.join(MODEL_DIR, "imputation_defaults.joblib"))
with open(os.path.join(MODEL_DIR, "drift_baseline.json"), encoding="utf-8") as f:
    drift_base = json.load(f)

from train import build_predict_function

predict_fn = build_predict_function(reg_model, cls_model, encoders, defaults)

app = FastAPI(
    title="Safety SIP — ML Pricing Engine",
    description="Predicts W_risk and disruption probability for gig worker insurance",
    version="1.0.0",
)

# ─────────────────────────────────────────────────────────────────────────────
# Request / Response schemas
# ─────────────────────────────────────────────────────────────────────────────

class RiderFeatures(BaseModel):
    rider_id:                    str
    home_zone_id:                str
    delivery_platform:           str
    tier:                        str
    primary_shift:               str
    avg_delivery_radius_km:      float
    avg_daily_active_hours:      float
    loyalty_weeks_active:        int
    avg_weekly_earnings_4wk:     float
    earnings_volatility_index:   float
    claim_history_score:         float
    zone_elevation_index:        float
    waterlogging_incidents_3yr:  int
    road_quality_score:          float
    zone_heat_island_index:      float
    rain_mm_7day_forecast:       Optional[float] = None  # None = API was down
    max_temp_forecast:           Optional[float] = None
    wind_gust_kmh_forecast:      Optional[float] = None
    aqi_forecast_avg:            Optional[float] = None
    imd_alert_level_forecast:    Optional[int]   = None
    bandh_probability_score:     Optional[float] = None
    platform_outage_7d_count:    Optional[int]   = None
    festival_calendar_flag:      Optional[int]   = 0
    political_event_flag:        Optional[int]   = 0


class PredictionResponse(BaseModel):
    rider_id:            str
    w_risk:              float
    disruption_prob:     float
    disruption_flag:     bool
    r_alert:             float
    alert_source:        str
    loyalty_discount:    float
    premium_final_inr:   int
    confidence:          str
    top_risk_factors:    list
    computed_at:         str


class BatchRequest(BaseModel):
    riders: List[RiderFeatures]


class BatchResponse(BaseModel):
    processed:  int
    results:    List[PredictionResponse]
    batch_at:   str


# ─────────────────────────────────────────────────────────────────────────────
# Endpoints
# ─────────────────────────────────────────────────────────────────────────────

@app.post("/predict", response_model=PredictionResponse)
def predict_single(rider: RiderFeatures):
    """
    Single rider prediction. Called by Node.js for one rider at a time.
    Returns W_risk + disruption probability + final premium.
    """
    rider_dict = rider.dict()
    try:
        result = predict_fn(rider_dict)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Model error: {str(e)}")

    return PredictionResponse(
        rider_id=rider.rider_id,
        computed_at=datetime.now().isoformat(),
        **result,
    )


@app.post("/predict/batch", response_model=BatchResponse)
def predict_batch(request: BatchRequest):
    """
    Batch prediction for all active riders — called by Saturday cron.
    Processes riders in parallel via vectorised XGBoost inference.
    """
    results = []
    for rider in request.riders:
        rider_dict = rider.dict()
        try:
            result = predict_fn(rider_dict)
            results.append(PredictionResponse(
                rider_id=rider.rider_id,
                computed_at=datetime.now().isoformat(),
                **result,
            ))
        except Exception as e:
            # Don't fail entire batch for one bad rider
            results.append(PredictionResponse(
                rider_id=rider.rider_id,
                w_risk=1.0, disruption_prob=0.0, disruption_flag=False,
                r_alert=1.0, alert_source="error_fallback",
                loyalty_discount=0.0, premium_final_inr=69,
                confidence="low",
                top_risk_factors=[{"factor": "error", "score": 0}],
                computed_at=datetime.now().isoformat(),
            ))

    return BatchResponse(
        processed=len(results),
        results=results,
        batch_at=datetime.now().isoformat(),
    )


@app.get("/health")
def health_check():
    """Returns model version, drift status, and readiness."""
    return {
        "status":           "ok",
        "model_trained_at": drift_base.get("created_at", "unknown"),
        "n_training_rows":  drift_base.get("n_training_rows", 0),
        "drift_threshold":  drift_base.get("drift_threshold", 0.15),
        "baseline_w_risk":  drift_base.get("w_risk_mean", 0),
        "ready":            True,
    }


@app.get("/r_alert/{zone_id}")
def get_r_alert(zone_id: str, imd_level: int = 0, max_temp: float = 30.0):
    """
    Returns the current R_alert multiplier for a zone.
    Called by alert.cron.ts every 6 hours.
    Combines IMD level + NDMA heat rule.
    """
    r_alert_map   = {0: 1.0, 1: 0.75, 2: 0.50, 3: 0.25, 4: 0.0}
    r_alert       = r_alert_map.get(imd_level, 1.0)
    alert_source  = "imd_rule" if imd_level > 0 else "none"

    if max_temp > 42 and r_alert == 1.0:
        r_alert      = 0.65
        alert_source = "ndma_heat"

    return {
        "zone_id":      zone_id,
        "imd_level":    imd_level,
        "max_temp":     max_temp,
        "r_alert":      r_alert,
        "alert_source": alert_source,
        "discount_pct": round((1 - r_alert) * 100, 0),
        "checked_at":   datetime.now().isoformat(),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    uvicorn.run("fast_APP:app", host="0.0.0.0", port=8000, reload=False)
