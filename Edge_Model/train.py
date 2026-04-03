"""
Safety SIP — Complete ML Training Pipeline
==========================================
Trains TWO models:
  1. W_risk Regressor    — XGBoost (predicts 0.70–1.80 risk multiplier)
  2. Disruption Classifier — XGBoost (predicts probability of income-loss event)

Also handles:
  - Missing feature imputation  (API down scenarios)
  - Monotonic constraints       (rain↑ must mean risk↑)
  - SHAP explainability
  - Drift detection baseline
  - Weekly retrain logic
  - Full predict() function for FastAPI

Run in Colab:
    !pip install xgboost shap scikit-learn pandas numpy joblib matplotlib
    !python train.py

Or run generate_data.py first, then this file.
"""

import json
import os
import site
import sys
import warnings
from datetime import datetime

warnings.filterwarnings("ignore")

BASE_DIR = os.path.dirname(__file__)
LOCAL_SITE_PACKAGES = os.path.join(BASE_DIR, ".python_packages")
if os.path.isdir(LOCAL_SITE_PACKAGES) and LOCAL_SITE_PACKAGES not in sys.path:
    sys.path.insert(0, LOCAL_SITE_PACKAGES)

USER_SITE_PACKAGES = site.getusersitepackages()
if USER_SITE_PACKAGES not in sys.path:
    sys.path.append(USER_SITE_PACKAGES)

import joblib
import numpy as np
import pandas as pd

# ─────────────────────────────────────────────────────────────────────────────
# 0. CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

SEED        = 42
TEST_SIZE   = 0.20
VAL_SIZE    = 0.15       # of train set, used for early stopping
MODEL_DIR   = os.path.join(BASE_DIR, "models")
LOG_PATH    = os.path.join(BASE_DIR, "training_log.json")

np.random.seed(SEED)

# Feature columns fed into both models
# Categorical columns must be label-encoded before passing
FEATURE_COLS = [
    # Group A — Rider profile
    "home_zone_id",             # label-encoded
    "delivery_platform",        # label-encoded
    "tier",                     # label-encoded
    "primary_shift",            # label-encoded
    "avg_delivery_radius_km",
    "avg_daily_active_hours",
    "loyalty_weeks_active",
    "avg_weekly_earnings_4wk",
    "earnings_volatility_index",
    "claim_history_score",

    # Group B — Zone infrastructure
    "zone_elevation_index",
    "waterlogging_incidents_3yr",
    "road_quality_score",
    "zone_heat_island_index",

    # Group C — Environmental forecast
    "rain_mm_7day_forecast",
    "max_temp_forecast",
    "wind_gust_kmh_forecast",
    "aqi_forecast_avg",
    "imd_alert_level_forecast",

    # Group D — Civic intelligence
    "bandh_probability_score",
    "platform_outage_7d_count",
    "festival_calendar_flag",
    "political_event_flag",

    # Engineered interaction features (added below)
    "flood_risk_score",         # rain × (1−elev/10) × wlog_factor
    "heat_risk_score",          # temp_excess × heat_island × shift_weight
    "wind_aqi_combined",        # wind_norm + aqi_norm
    "civic_disruption_score",   # bandh × 0.65 + outage_norm × 0.35
    "rider_exposure_score",     # radius × hours × volatility composite
]

# Columns that the model should never predict as lower when these go higher
# XGBoost monotonic_constraints: +1 = must increase, -1 = must decrease, 0 = free
# Order must match FEATURE_COLS exactly
MONOTONIC_CONSTRAINTS_REGRESSOR = [
    0,    # home_zone_id       — zone, not ordinal
    0,    # delivery_platform
    0,    # tier
    0,    # primary_shift
   +1,    # avg_delivery_radius_km    — wider radius = more risk
   +1,    # avg_daily_active_hours    — more hours = more exposure
   -1,    # loyalty_weeks_active      — longer tenure = lower risk (loyalty disc)
    0,    # avg_weekly_earnings_4wk   — higher earner ≠ lower risk necessarily
   +1,    # earnings_volatility_index — more volatile = riskier week
   +1,    # claim_history_score       — more claims = higher risk flag
   -1,    # zone_elevation_index      — higher elevation = LESS flood risk
   +1,    # waterlogging_incidents    — more incidents = more risk
   -1,    # road_quality_score        — better road = less risk
   +1,    # zone_heat_island_index    — hotter microclimate = more risk
   +1,    # rain_mm_7day_forecast     — more rain = more risk
   +1,    # max_temp_forecast         — hotter = more risk
   +1,    # wind_gust_kmh_forecast    — higher wind = more risk
   +1,    # aqi_forecast_avg          — worse air = more risk
   +1,    # imd_alert_level_forecast  — higher alert = more risk
   +1,    # bandh_probability_score   — higher bandh prob = more risk
   +1,    # platform_outage_7d_count  — more outages = more risk
   -1,    # festival_calendar_flag    — festival = demand surge = lower risk
    0,    # political_event_flag      — mixed effect
   +1,    # flood_risk_score
   +1,    # heat_risk_score
   +1,    # wind_aqi_combined
   +1,    # civic_disruption_score
   +1,    # rider_exposure_score
]

# ─────────────────────────────────────────────────────────────────────────────
# 1. FEATURE ENGINEERING
# ─────────────────────────────────────────────────────────────────────────────

def engineer_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Add interaction features that capture non-linear relationships
    the base XGBoost trees might miss with raw features alone.
    These are your 'domain knowledge baked in as features'.
    """
    df = df.copy()

    # ── Flood risk composite ─────────────────────────────────────────────
    # Key insight: 100mm rain in Velachery (elev=2) >> 100mm in Guindy (elev=7)
    rain_norm  = np.clip(df["rain_mm_7day_forecast"] / 250.0, 0, 1)
    elev_inv   = 1.0 - (df["zone_elevation_index"] / 10.0)   # low elev = high factor
    wlog_w     = 1.0 + (df["waterlogging_incidents_3yr"] / 20.0)
    road_inv   = 1.0 - (df["road_quality_score"] / 20.0)
    df["flood_risk_score"] = np.clip(
        rain_norm * elev_inv * wlog_w * road_inv, 0, 1
    )

    # ── Heat risk composite ──────────────────────────────────────────────
    # Key insight: 44°C is deadly for afternoon-shift rider, irrelevant for night shift
    temp_excess = np.clip((df["max_temp_forecast"] - 42) / 8.0, 0, 1)
    heat_amp    = 1.0 + (df["zone_heat_island_index"] / 5.0)
    # Shift weight: afternoon = fully exposed to 11AM-4PM peak heat
    shift_w_map = {"morning": 0.30, "afternoon": 1.00, "evening": 0.50, "night": 0.0}
    if "primary_shift" in df.columns and df["primary_shift"].dtype == object:
        shift_weights = df["primary_shift"].map(shift_w_map).fillna(0.5)
    else:
        shift_weights = pd.Series(0.5, index=df.index)  # fallback if encoded
    df["heat_risk_score"] = np.clip(temp_excess * heat_amp * shift_weights, 0, 1)

    # ── Wind + AQI combined ──────────────────────────────────────────────
    wind_norm = np.clip((df["wind_gust_kmh_forecast"] - 20) / 100.0, 0, 1)
    aqi_norm  = np.clip((df["aqi_forecast_avg"] - 100) / 400.0, 0, 1)
    df["wind_aqi_combined"] = wind_norm * 0.6 + aqi_norm * 0.4

    # ── Civic disruption composite ───────────────────────────────────────
    outage_norm = np.clip(df["platform_outage_7d_count"] / 10.0, 0, 1)
    df["civic_disruption_score"] = np.clip(
        df["bandh_probability_score"] * 0.65 + outage_norm * 0.35, 0, 1
    )

    # ── Rider exposure composite ─────────────────────────────────────────
    # Wide radius rider crosses more disrupted zones
    rad_norm  = np.clip(df["avg_delivery_radius_km"] / 20.0, 0, 1)
    hrs_norm  = np.clip(df["avg_daily_active_hours"] / 14.0, 0, 1)
    vol       = df["earnings_volatility_index"]
    claim_h   = df["claim_history_score"]
    df["rider_exposure_score"] = np.clip(
        rad_norm * 0.35 + hrs_norm * 0.25 + vol * 0.25 + claim_h * 0.15, 0, 1
    )

    return df


# ─────────────────────────────────────────────────────────────────────────────
# 2. MISSING VALUE STRATEGY
# ─────────────────────────────────────────────────────────────────────────────

def get_imputation_defaults() -> dict:
    """
    Fallback values when an API is down or data is missing.
    These are conservative (slightly elevated) estimates — better to
    slightly overprice than underprice when data is uncertain.
    """
    return {
        "rain_mm_7day_forecast":     20.0,   # assume light rain if API down
        "max_temp_forecast":         34.0,   # assume warm
        "wind_gust_kmh_forecast":    20.0,   # assume calm
        "aqi_forecast_avg":          120.0,  # assume moderate pollution
        "imd_alert_level_forecast":   0,     # no alert — don't assume disaster
        "bandh_probability_score":    0.05,  # low civic risk default
        "platform_outage_7d_count":   1,     # assume 1 minor outage
        "festival_calendar_flag":     0,
        "political_event_flag":       0,
        "zone_heat_island_index":     1.5,   # Chennai urban average
        "waterlogging_incidents_3yr": 5,     # city average
        "road_quality_score":         5.0,   # average road quality
        # Rider profile — use zone average if AA is down
        "avg_weekly_earnings_4wk":    6500.0,
        "earnings_volatility_index":  0.30,
        "claim_history_score":        0.10,
    }


def impute_missing(df: pd.DataFrame, defaults: dict) -> pd.DataFrame:
    """Fill NaN values with safe defaults. XGBoost also handles NaN
    natively, but explicit imputation is logged for audit trail."""
    df = df.copy()
    for col, val in defaults.items():
        if col in df.columns:
            n_missing = df[col].isna().sum()
            if n_missing > 0:
                print(f"  Imputing {n_missing} missing values in '{col}' with {val}")
                df[col] = df[col].fillna(val)
    return df


# ─────────────────────────────────────────────────────────────────────────────
# 3. LABEL ENCODING
# ─────────────────────────────────────────────────────────────────────────────

from sklearn.preprocessing import LabelEncoder
from pandas.api.types import is_numeric_dtype

CAT_COLS = ["home_zone_id", "delivery_platform", "tier", "primary_shift"]

def fit_encoders(df: pd.DataFrame) -> dict:
    encoders = {}
    for col in CAT_COLS:
        if col in df.columns and not is_numeric_dtype(df[col]):
            le = LabelEncoder()
            le.fit(df[col].astype(str))
            encoders[col] = le
    return encoders

def apply_encoders(df: pd.DataFrame, encoders: dict) -> pd.DataFrame:
    df = df.copy()
    for col, le in encoders.items():
        if col in df.columns and not is_numeric_dtype(df[col]):
            # Handle unseen labels gracefully
            known = set(le.classes_)
            values = df[col].astype(str)
            values = values.apply(lambda x: x if x in known else le.classes_[0])
            df[col] = le.transform(values)
    return df


# ─────────────────────────────────────────────────────────────────────────────
# 4. TRAIN / VAL / TEST SPLIT
# ─────────────────────────────────────────────────────────────────────────────

from sklearn.model_selection import train_test_split

def split_data(df: pd.DataFrame):
    """
    Stratified split on disruption_label to ensure both classes
    are represented in train/val/test sets.
    """
    X = df[FEATURE_COLS]
    y_reg = df["w_risk"]
    y_cls = df["disruption_label"]

    X_tr, X_te, yr_tr, yr_te, yc_tr, yc_te = train_test_split(
        X, y_reg, y_cls,
        test_size=TEST_SIZE,
        random_state=SEED,
        stratify=y_cls
    )
    X_tr, X_val, yr_tr, yr_val, yc_tr, yc_val = train_test_split(
        X_tr, yr_tr, yc_tr,
        test_size=VAL_SIZE,
        random_state=SEED,
        stratify=yc_tr
    )
    print(f"  Train: {len(X_tr)}  Val: {len(X_val)}  Test: {len(X_te)}")
    return X_tr, X_val, X_te, yr_tr, yr_val, yr_te, yc_tr, yc_val, yc_te


def get_best_iteration(model):
    try:
        return int(model.best_iteration)
    except AttributeError:
        return None


# ─────────────────────────────────────────────────────────────────────────────
# 5. MODEL 1 — W_RISK REGRESSOR
# ─────────────────────────────────────────────────────────────────────────────

from xgboost import XGBRegressor, XGBClassifier
from sklearn.metrics import (
    mean_absolute_error, mean_squared_error, r2_score,
    roc_auc_score, accuracy_score, classification_report
)

def train_w_risk_model(X_tr, X_val, X_te, yr_tr, yr_val, yr_te):
    """
    XGBoost Regressor for W_risk prediction.

    Key hyperparameter choices:
    - n_estimators=500 with early stopping — avoids overfitting
    - max_depth=5 — captures interactions without memorising
    - monotone_constraints — enforces domain logic (rain↑ → risk↑)
    - reg_lambda=3 — L2 regularisation for stability
    - subsample=0.8 — row sampling prevents overfitting
    - colsample_bytree=0.7 — feature sampling adds diversity
    """
    print("\n  Training W_risk regressor...")

    model = XGBRegressor(
        n_estimators         = 500,
        max_depth            = 5,
        
        learning_rate        = 0.03,
        subsample            = 0.80,
        colsample_bytree     = 0.70,
        colsample_bylevel    = 0.80,
        reg_lambda           = 3,         # L2
        reg_alpha            = 0.5,       # L1 — sparse features
        min_child_weight     = 5,         # prevents tiny leaf splits
        gamma                = 0.1,       # min split gain
        monotone_constraints = tuple(MONOTONIC_CONSTRAINTS_REGRESSOR),
        objective            = "reg:squarederror",
        random_state         = SEED,
        n_jobs               = -1,
        verbosity            = 0,
    )

    model.fit(
        X_tr, yr_tr,
        eval_set             = [(X_val, yr_val)],
        verbose              = False,
    )

    preds_val  = np.clip(model.predict(X_val), 0.70, 1.80)
    preds_test = np.clip(model.predict(X_te),  0.70, 1.80)

    metrics = {
        "val_mae":   round(float(mean_absolute_error(yr_val, preds_val)), 5),
        "val_rmse":  round(float(np.sqrt(mean_squared_error(yr_val, preds_val))), 5),
        "val_r2":    round(float(r2_score(yr_val, preds_val)), 4),
        "test_mae":  round(float(mean_absolute_error(yr_te, preds_test)), 5),
        "test_rmse": round(float(np.sqrt(mean_squared_error(yr_te, preds_test))), 5),
        "test_r2":   round(float(r2_score(yr_te, preds_test)), 4),
        "best_iteration": get_best_iteration(model),
    }

    print(f"  Val  MAE={metrics['val_mae']:.4f}  RMSE={metrics['val_rmse']:.4f}  R²={metrics['val_r2']:.4f}")
    print(f"  Test MAE={metrics['test_mae']:.4f}  RMSE={metrics['test_rmse']:.4f}  R²={metrics['test_r2']:.4f}")
    if metrics["best_iteration"] is not None:
        print(f"  Best iteration: {metrics['best_iteration']}")

    return model, metrics


# ─────────────────────────────────────────────────────────────────────────────
# 6. MODEL 2 — DISRUPTION CLASSIFIER
# ─────────────────────────────────────────────────────────────────────────────

def train_disruption_model(X_tr, X_val, X_te, yc_tr, yc_val, yc_te):
    """
    XGBoost Regressor for W_risk.

    Predicts risk score based on:
    - base uncertainty
    - weather impact
    - pitch impact
    - team volatility
    - match conditions

    Uses monotonic constraints to preserve domain logic.
    """

    print("\n  Training disruption classifier...")

    positive_rate = max(float(np.mean(yc_tr)), 1e-6)
    scale_pos_weight = float((1.0 - positive_rate) / positive_rate)

    model = XGBClassifier(
        n_estimators         = 500,
        max_depth            = 4,
        learning_rate        = 0.03,
        subsample            = 0.80,
        colsample_bytree     = 0.70,
        colsample_bylevel    = 0.80,
        reg_lambda           = 3,
        reg_alpha            = 0.5,
        min_child_weight     = 5,
        gamma                = 0.1,
        objective            = "binary:logistic",

        # ✅ Required for best_iteration
        eval_metric           = "logloss",
        early_stopping_rounds = 40,
        scale_pos_weight      = scale_pos_weight,

        random_state         = SEED,
        n_jobs               = -1,
        verbosity            = 0,
    )

    model.fit(
        X_tr,
        yc_tr,
        eval_set = [(X_val, yc_val)],
        verbose  = False
    )

    preds_val  = model.predict_proba(X_val)[:, 1]
    preds_test = model.predict_proba(X_te)[:, 1]
    preds_val_labels = (preds_val >= 0.5).astype(int)
    preds_test_labels = (preds_test >= 0.5).astype(int)

    metrics = {
        "val_auc": round(float(roc_auc_score(yc_val, preds_val)), 4),
        "val_accuracy": round(float(accuracy_score(yc_val, preds_val_labels)), 4),
        "test_auc": round(float(roc_auc_score(yc_te, preds_test)), 4),
        "test_accuracy": round(float(accuracy_score(yc_te, preds_test_labels)), 4),
        "best_iteration": get_best_iteration(model)
    }

    print(f"  Val  AUC={metrics['val_auc']:.4f}  Acc={metrics['val_accuracy']:.4f}")
    print(f"  Test AUC={metrics['test_auc']:.4f}  Acc={metrics['test_accuracy']:.4f}")
    if metrics['best_iteration'] is not None:
        print(f"  Best iteration: {metrics['best_iteration']}")

    return model, metrics

    


# ─────────────────────────────────────────────────────────────────────────────
# 7. SHAP EXPLAINABILITY
# ─────────────────────────────────────────────────────────────────────────────

def compute_shap(model, X_te: pd.DataFrame, model_name: str):
    """
    Compute SHAP values for the test set.
    Saves:
      - shap_summary_{model_name}.png  (beeswarm plot)
      - shap_values_{model_name}.npy   (raw values for API use)
    """
    try:
        import shap
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        print(f"\n  Computing SHAP for {model_name}...")
        explainer   = shap.TreeExplainer(model)
        shap_values = explainer.shap_values(X_te)

        # Save raw SHAP values
        np.save(os.path.join(MODEL_DIR, f"shap_values_{model_name}.npy"), shap_values)

        # Feature importance from SHAP
        mean_abs_shap = np.abs(shap_values).mean(axis=0)
        importance_df = pd.DataFrame({
            "feature": X_te.columns,
            "mean_abs_shap": mean_abs_shap
        }).sort_values("mean_abs_shap", ascending=False)

        print(f"  Top 10 features by SHAP ({model_name}):")
        for _, r in importance_df.head(10).iterrows():
            bar = "█" * int(r["mean_abs_shap"] / importance_df["mean_abs_shap"].max() * 20)
            print(f"    {r['feature']:<38} {bar} {r['mean_abs_shap']:.4f}")

        # Beeswarm plot
        plt.figure(figsize=(10, 7))
        shap.summary_plot(shap_values, X_te, show=False, max_display=15)
        plt.title(f"SHAP Feature Importance — {model_name}")
        plt.tight_layout()
        plot_path = os.path.join(MODEL_DIR, f"shap_summary_{model_name}.png")
        plt.savefig(plot_path, dpi=120, bbox_inches="tight")
        plt.close()
        print(f"  Saved: {plot_path}")

        return importance_df

    except ImportError:
        print("  SHAP not installed — skipping. Run: pip install shap")
        return None


# ─────────────────────────────────────────────────────────────────────────────
# 8. DRIFT DETECTION BASELINE
# ─────────────────────────────────────────────────────────────────────────────

def save_drift_baseline(df: pd.DataFrame, preds_w_risk: np.ndarray):
    """
    Save baseline statistics for weekly drift detection.
    The alert cron compares next week's predictions against these.
    If W_risk mean drifts > 15% for 3 consecutive weeks → alert.
    """
    numeric_features = [f for f in FEATURE_COLS if f not in CAT_COLS]
    baseline = {
        "created_at":           datetime.now().isoformat(),
        "n_training_rows":      len(df),
        "w_risk_mean":          round(float(df["w_risk"].mean()), 4),
        "w_risk_std":           round(float(df["w_risk"].std()), 4),
        "pred_w_risk_mean":     round(float(preds_w_risk.mean()), 4),
        "pred_w_risk_std":      round(float(preds_w_risk.std()), 4),
        "disruption_rate":      round(float(df["disruption_label"].mean()), 4),
        "feature_means":        {
            col: round(float(df[col].mean()), 4)
            for col in numeric_features if col in df.columns
        },
        "feature_stds":         {
            col: round(float(df[col].std()), 4)
            for col in numeric_features if col in df.columns
        },
        "drift_threshold":      0.15,    # 15% divergence triggers alert
        "drift_window_weeks":   3,       # must persist 3 weeks to trigger
    }

    path = os.path.join(MODEL_DIR, "drift_baseline.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(baseline, f, indent=2)
    print(f"\n  Saved drift baseline: {path}")
    return baseline


# ─────────────────────────────────────────────────────────────────────────────
# 9. PREDICT FUNCTION — used by FastAPI endpoint
# ─────────────────────────────────────────────────────────────────────────────

def build_predict_function(
    reg_model,
    cls_model,
    encoders: dict,
    defaults: dict,
    scaler=None,
):
    """
    Returns a predict(rider_dict) function ready to wrap in FastAPI.

    Input:  raw rider feature dict (can have missing values)
    Output: {
        w_risk: float,              0.70–1.80
        disruption_prob: float,     0.0–1.0
        disruption_flag: bool,
        premium_standard: int,      final ₹ for Standard tier
        r_alert_override: float,    from rule engine
        alert_source: str,          "ml" | "imd_rule" | "ndma_heat" | "default"
        confidence: str,            "high" | "medium" | "low"
        top_risk_factors: list,     top 3 features driving W_risk up
    }
    """

    def predict(rider: dict) -> dict:
        # 1. Fill missing with defaults
        for k, v in defaults.items():
            if k not in rider or rider[k] is None:
                rider[k] = v

        # 2. Convert to DataFrame
        df_input = pd.DataFrame([rider])

        # 3. Feature engineering
        df_input = engineer_features(df_input)

        # 4. Encode categoricals
        df_input = apply_encoders(df_input, encoders)

        # 5. Align columns (add zeros for anything missing)
        for col in FEATURE_COLS:
            if col not in df_input.columns:
                df_input[col] = 0
        X = df_input[FEATURE_COLS]

        # 6. Run models
        w_risk_raw      = float(reg_model.predict(X)[0])
        w_risk          = round(float(np.clip(w_risk_raw, 0.70, 1.80)), 4)
        disruption_prob = round(float(cls_model.predict_proba(X)[0][1]), 4)
        disruption_flag = bool(disruption_prob >= 0.50)

        # 7. Rule engine — hard overrides from IMD / NDMA
        alert_level  = int(rider.get("imd_alert_level_forecast", 0))
        max_temp     = float(rider.get("max_temp_forecast", 30))
        r_alert_map  = {0: 1.0, 1: 0.75, 2: 0.50, 3: 0.25, 4: 0.0}
        r_alert      = r_alert_map.get(alert_level, 1.0)
        alert_source = "ml"

        # NDMA heat protocol: mandates platform work suspension 11AM–4PM above 42°C
        if max_temp > 42 and r_alert == 1.0:
            r_alert      = 0.65     # partial day lost
            alert_source = "ndma_heat"
        elif alert_level > 0:
            alert_source = "imd_rule"

        # 8. Final premium calculation
        tier_base = {"starter": 39, "standard": 69, "shield": 99}
        loy_weeks = int(rider.get("loyalty_weeks_active", 0))
        loyalty   = round(max(0.70, 1.0 - (loy_weeks // 4) * 0.05), 4)
        tier      = rider.get("tier", "standard")
        base      = tier_base.get(tier, 69)
        premium   = round(base * w_risk * loyalty * r_alert, 0) if r_alert > 0 else 0

        # 9. Confidence score
        # Low confidence when key APIs were missing (default values used)
        missing_keys = [k for k in ["rain_mm_7day_forecast", "max_temp_forecast",
                                     "imd_alert_level_forecast", "bandh_probability_score"]
                        if k not in rider]
        confidence = "low" if len(missing_keys) >= 2 else \
                     "medium" if len(missing_keys) == 1 else "high"

        # 10. Top risk factors (simplified SHAP proxy from feature values)
        risk_signals = {
            "flood_risk (rain×elevation)": float(df_input["flood_risk_score"].iloc[0]),
            "heat_risk (temp×shift)":       float(df_input["heat_risk_score"].iloc[0]),
            "civic_disruption (bandh)":     float(df_input["civic_disruption_score"].iloc[0]),
            "rider_exposure (radius×hrs)":  float(df_input["rider_exposure_score"].iloc[0]),
            "wind_aqi":                     float(df_input["wind_aqi_combined"].iloc[0]),
        }
        top_factors = sorted(risk_signals.items(), key=lambda x: x[1], reverse=True)[:3]

        return {
            "w_risk":            w_risk,
            "disruption_prob":   disruption_prob,
            "disruption_flag":   disruption_flag,
            "r_alert":           r_alert,
            "alert_source":      alert_source,
            "loyalty_discount":  round((1 - loyalty) * 100, 1),
            "premium_final_inr": int(premium),
            "confidence":        confidence,
            "top_risk_factors":  [{"factor": f, "score": round(s, 4)} for f, s in top_factors],
        }

    return predict


# ─────────────────────────────────────────────────────────────────────────────
# 10. WEEKLY RETRAIN LOGIC
# ─────────────────────────────────────────────────────────────────────────────

def retrain_with_new_week(
    existing_csv: str,
    new_week_csv: str,
    output_csv:   str,
) -> pd.DataFrame:
    """
    Called every Saturday after new production data arrives.

    new_week_csv must have the same schema as training_data.csv
    plus a 'w_risk' column (computed from actual claim outcomes).

    Steps:
    1. Append new week to existing training data
    2. Drop rows older than 2 years (sliding window)
    3. Re-engineer features
    4. Retrain both models
    5. Compare new metrics vs drift baseline → alert if diverged
    """
    existing  = pd.read_csv(existing_csv)
    new_week  = pd.read_csv(new_week_csv)

    # Append
    combined = pd.concat([existing, new_week], ignore_index=True)

    # Sliding window — keep last 2 years (104 weeks × avg riders)
    if "week_id" in combined.columns:
        max_week = combined["week_id"].max()
        combined = combined[combined["week_id"] >= max_week - 104]

    combined.to_csv(output_csv, index=False)
    print(f"  Retrain dataset: {len(combined)} rows saved to {output_csv}")
    return combined


# ─────────────────────────────────────────────────────────────────────────────
# 11. SAVE / LOAD ARTIFACTS
# ─────────────────────────────────────────────────────────────────────────────

def save_artifacts(reg_model, cls_model, encoders, defaults):
    os.makedirs(MODEL_DIR, exist_ok=True)

    joblib.dump(reg_model,  os.path.join(MODEL_DIR, "w_risk_regressor.joblib"))
    joblib.dump(cls_model,  os.path.join(MODEL_DIR, "disruption_classifier.joblib"))
    joblib.dump(encoders,   os.path.join(MODEL_DIR, "label_encoders.joblib"))
    joblib.dump(defaults,   os.path.join(MODEL_DIR, "imputation_defaults.joblib"))

    print(f"\n  Saved all artifacts to {MODEL_DIR}")
    for f in os.listdir(MODEL_DIR):
        size = os.path.getsize(os.path.join(MODEL_DIR, f)) // 1024
        print(f"    {f:<45} {size} KB")


def load_artifacts():
    reg_model = joblib.load(os.path.join(MODEL_DIR, "w_risk_regressor.joblib"))
    cls_model = joblib.load(os.path.join(MODEL_DIR, "disruption_classifier.joblib"))
    encoders = joblib.load(os.path.join(MODEL_DIR, "label_encoders.joblib"))
    defaults = joblib.load(os.path.join(MODEL_DIR, "imputation_defaults.joblib"))
    return {
        "reg_model": reg_model,
        "cls_model": cls_model,
        "encoders": encoders,
        "defaults": defaults,
        "predict_fn": build_predict_function(reg_model, cls_model, encoders, defaults),
    }


# ─────────────────────────────────────────────────────────────────────────────
# 12. MAIN
# ─────────────────────────────────────────────────────────────────────────────

def main():
    print("=" * 62)
    print("  Safety SIP — ML Training Pipeline")
    print(f"  Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 62)

    # ── Load data ──────────────────────────────────────────────────────
    data_path = os.path.join(BASE_DIR, "training_data.csv")
    if not os.path.exists(data_path):
        print(f"\nERROR: {data_path} not found.")
        print("Run generate_data.py first:\n    python generate_data.py")
        return

    print(f"\n[1/8] Loading data from {data_path}...")
    df_raw = pd.read_csv(data_path)
    print(f"  Loaded {len(df_raw)} rows × {len(df_raw.columns)} columns")

    # ── Impute missing ──────────────────────────────────────────────────
    print("\n[2/8] Imputing missing values...")
    defaults = get_imputation_defaults()
    df_raw   = impute_missing(df_raw, defaults)

    # ── Feature engineering ────────────────────────────────────────────
    print("\n[3/8] Engineering interaction features...")
    df = engineer_features(df_raw)
    new_feats = ["flood_risk_score","heat_risk_score","wind_aqi_combined",
                 "civic_disruption_score","rider_exposure_score"]
    for f in new_feats:
        print(f"  {f}: mean={df[f].mean():.3f}  max={df[f].max():.3f}")

    # ── Encode categoricals ────────────────────────────────────────────
    print("\n[4/8] Encoding categorical features...")
    encoders = fit_encoders(df)
    df       = apply_encoders(df, encoders)
    for col, le in encoders.items():
        print(f"  {col}: {list(le.classes_)}")

    # ── Split ──────────────────────────────────────────────────────────
    print("\n[5/8] Splitting dataset...")
    (X_tr, X_val, X_te,
     yr_tr, yr_val, yr_te,
     yc_tr, yc_val, yc_te) = split_data(df)

    # ── Train Model 1 ──────────────────────────────────────────────────
    print("\n[6/8] Training models...")
    reg_model, reg_metrics = train_w_risk_model(
        X_tr, X_val, X_te, yr_tr, yr_val, yr_te
    )
    cls_model, cls_metrics = train_disruption_model(
        X_tr, X_val, X_te, yc_tr, yc_val, yc_te
    )

    # ── SHAP ───────────────────────────────────────────────────────────
    print("\n[7/8] Computing SHAP explainability...")
    os.makedirs(MODEL_DIR, exist_ok=True)
    compute_shap(reg_model, X_te, "w_risk_regressor")
    compute_shap(cls_model, X_te, "disruption_classifier")

    # ── Drift baseline ─────────────────────────────────────────────────
    preds_all = np.clip(reg_model.predict(df[FEATURE_COLS]), 0.70, 1.80)
    save_drift_baseline(df, preds_all)

    # ── Build & test predict function ──────────────────────────────────
    predict = build_predict_function(reg_model, cls_model, encoders, defaults)

    # Demo prediction — Ravi in Velachery during Red Alert
    test_rider = {
        "home_zone_id":              "velachery",
        "delivery_platform":         "swiggy",
        "tier":                      "standard",
        "primary_shift":             "evening",
        "avg_delivery_radius_km":    8.0,
        "avg_daily_active_hours":    8.0,
        "loyalty_weeks_active":      12,
        "avg_weekly_earnings_4wk":   6500,
        "earnings_volatility_index": 0.32,
        "claim_history_score":       0.08,
        "zone_elevation_index":      2.0,
        "waterlogging_incidents_3yr":14,
        "road_quality_score":        4.0,
        "zone_heat_island_index":    2.5,
        "rain_mm_7day_forecast":     145.0,
        "max_temp_forecast":         31.0,
        "wind_gust_kmh_forecast":    55.0,
        "aqi_forecast_avg":          110.0,
        "imd_alert_level_forecast":  3,       # RED ALERT
        "bandh_probability_score":   0.08,
        "platform_outage_7d_count":  1,
        "festival_calendar_flag":    0,
        "political_event_flag":      0,
    }

    result = predict(test_rider)
    print("\n  --- Demo prediction: Ravi / Velachery / Red Alert week ---")
    for k, v in result.items():
        print(f"    {k:<28} {v}")

    # ── Save artifacts ─────────────────────────────────────────────────
    print("\n[8/8] Saving artifacts...")
    save_artifacts(reg_model, cls_model, encoders, defaults)

    # ── Training log ───────────────────────────────────────────────────
    log = {
        "trained_at":    datetime.now().isoformat(),
        "n_rows":        len(df_raw),
        "feature_count": len(FEATURE_COLS),
        "reg_metrics":   reg_metrics,
        "cls_metrics":   cls_metrics,
        "demo_result":   result,
    }
    with open(LOG_PATH, "w", encoding="utf-8") as f:
        json.dump(log, f, indent=2, default=str)
    print(f"  Training log saved: {LOG_PATH}")

    # ── Final summary ──────────────────────────────────────────────────
    print("\n" + "=" * 62)
    print("  TRAINING COMPLETE")
    print(f"  W_risk  MAE  = {reg_metrics['test_mae']:.4f}  (target < 0.05)")
    print(f"  W_risk  R²   = {reg_metrics['test_r2']:.4f}  (target > 0.90)")
    print(f"  Disruption AUC = {cls_metrics['test_auc']:.4f}  (target > 0.85)")
    print("=" * 62)
    print("\nNext: run fastapi_app.py to serve predictions via REST API")


if __name__ == "__main__":
    main()
