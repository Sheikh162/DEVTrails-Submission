"""
Safety SIP — Synthetic Training Data Generator
================================================
Generates 2000 realistic rider-week rows for training the
W_risk XGBoost regressor and disruption classifier.

Run:
    pip install pandas numpy scikit-learn xgboost shap
    python generate_data.py

Outputs:
    training_data.csv   — main dataset (2000 rows x 25 cols)
    data_summary.txt    — basic stats for sanity check
"""

import site
import sys
from datetime import datetime, timedelta
import random
import os

LOCAL_SITE_PACKAGES = os.path.join(os.path.dirname(__file__), ".python_packages")
if os.path.isdir(LOCAL_SITE_PACKAGES) and LOCAL_SITE_PACKAGES not in sys.path:
    sys.path.insert(0, LOCAL_SITE_PACKAGES)

# Ensure user-site packages are available when Python is installed without
# write access to the global site-packages directory.
USER_SITE_PACKAGES = site.getusersitepackages()
if USER_SITE_PACKAGES not in sys.path:
    sys.path.append(USER_SITE_PACKAGES)

import numpy as np
import pandas as pd

# ── reproducibility ──────────────────────────────────────────────────────────
SEED = 42
np.random.seed(SEED)
random.seed(SEED)

N_ROWS = 2000

# ── Chennai zone definitions ──────────────────────────────────────────────────
# (zone_id, elevation_index, waterlogging_incidents_3yr, road_quality, heat_island)
ZONES = {
    "velachery":     (2,  14, 4, 2.5),
    "adyar":         (3,   8, 6, 2.0),
    "anna_nagar":    (7,   2, 8, 1.0),
    "t_nagar":       (5,   5, 5, 2.2),
    "tambaram":      (4,   7, 5, 1.8),
    "perambur":      (3,   9, 4, 2.3),
    "guindy":        (6,   3, 7, 1.5),
    "royapuram":     (2,  12, 3, 2.8),
    "chromepet":     (4,   6, 6, 1.6),
    "sholinganallur":(5,   4, 7, 1.4),
}

PLATFORMS   = ["swiggy", "zomato", "zepto", "blinkit"]
TIERS       = ["starter", "standard", "shield"]
SHIFTS      = ["morning", "afternoon", "evening", "night"]

# Platform reliability — higher = more outages historically
PLATFORM_OUTAGE_BIAS = {
    "swiggy": 0.8, "zomato": 0.9, "zepto": 1.4, "blinkit": 1.2
}

# Chennai seasonal rain profile (mm per week, approximate)
# Jan–Feb: dry, Mar–May: hot, Jun–Sep: SW monsoon, Oct–Dec: NE monsoon
WEEKLY_RAIN_PROFILE = [
    5, 5, 8, 10, 15, 40, 60, 70, 55, 80, 90, 70,   # Jan–Dec
    60, 50, 30, 15, 8, 5, 5, 8, 12, 70, 85, 60,    # Jan–Dec (yr 2)
    6, 4, 9, 12, 18, 45, 65, 75, 60, 85, 95, 75,   # yr 3
    55, 45, 25, 14, 7, 5, 4, 7, 11, 68, 80, 58,    # yr 4
]

# ── helper functions ──────────────────────────────────────────────────────────

def pick_rain(week_of_year: int, noise: float = 0.4) -> float:
    """Return rain mm for a given week with seasonal pattern + noise."""
    month = int((week_of_year % 52) / 52 * 12)
    base = WEEKLY_RAIN_PROFILE[month % len(WEEKLY_RAIN_PROFILE)]
    return float(np.clip(base * np.random.lognormal(0, noise), 0, 280))

def pick_temp(week_of_year: int) -> float:
    """Chennai temp: 22°C winter, 42°C peak summer, 32°C monsoon."""
    month = int((week_of_year % 52) / 52 * 12)
    base_temps = [27, 28, 31, 34, 38, 36, 33, 32, 32, 30, 28, 27]
    base = base_temps[month % 12]
    return float(np.clip(np.random.normal(base, 2), 20, 48))

def pick_wind(rain_mm: float) -> float:
    """Wind gusts correlated with rain — cyclone season spikes."""
    base = 15 + rain_mm * 0.25
    return float(np.clip(np.random.lognormal(np.log(max(base,1)), 0.5), 0, 130))

def pick_aqi(temp: float, week: int) -> float:
    """AQI worst Oct–Feb (stubble burning + winter inversion)."""
    month = int((week % 52) / 52 * 12)
    seasonal = [200, 180, 120, 90, 80, 70, 75, 80, 90, 150, 200, 220]
    base = seasonal[month % 12]
    heat_reduction = max(0, (temp - 35) * 3)
    return float(np.clip(np.random.lognormal(np.log(max(base - heat_reduction, 40)), 0.4), 20, 500))

def imd_alert_level(rain_mm: float, wind_kmh: float, temp: float) -> int:
    """0=none, 1=yellow, 2=orange, 3=red, 4=cyclone."""
    if wind_kmh > 90 or rain_mm > 200:
        return 4
    if rain_mm > 130 or (rain_mm > 80 and wind_kmh > 50):
        return 3
    if rain_mm > 70 or wind_kmh > 45 or temp > 44:
        return 2
    if rain_mm > 40 or wind_kmh > 30 or temp > 42:
        return 1
    return 0

def r_alert_from_level(level: int) -> float:
    """R_alert multiplier from IMD alert level."""
    return [1.0, 0.75, 0.50, 0.25, 0.0][level]

def bandh_probability(week: int, zone: str) -> float:
    """Simulate civic disruption probability — higher near elections."""
    # Election years tend to have more bandhs
    base = 0.05
    if week % 52 in range(0, 8):        # Jan = protest season
        base += 0.15
    if week % 52 in range(43, 52):      # Nov = NE monsoon + political season
        base += 0.10
    noise = np.random.beta(1, 8)
    return float(np.clip(base + noise, 0, 0.95))

def platform_outage_count(platform: str) -> int:
    """Outages in last 7 days per platform."""
    bias = PLATFORM_OUTAGE_BIAS[platform]
    return int(np.random.poisson(bias))

def festival_flag(week: int) -> int:
    """1 if major festival week (Pongal wk2, Diwali wk43~44, Dussehra wk40)."""
    w = week % 52
    return int(w in [2, 3, 40, 43, 44, 51, 0])

def political_flag(week: int) -> int:
    """1 if election / major political event week."""
    w = week % 52
    return int(w in [15, 16, 17, 22, 23])


# ── W_risk ground truth formula ───────────────────────────────────────────────
# This is your DOMAIN KNOWLEDGE encoded as labels.
# XGBoost will learn to approximate this from features.

def compute_w_risk(row: dict) -> float:
    """
    Compute ground-truth W_risk from features using domain rules.
    Range: 0.70 – 1.80
    """
    rain        = row["rain_mm_7day_forecast"]
    elev        = row["zone_elevation_index"]
    wlog        = row["waterlogging_incidents_3yr"]
    road        = row["road_quality_score"]
    temp        = row["max_temp_forecast"]
    heat_island = row["zone_heat_island_index"]
    wind        = row["wind_gust_kmh_forecast"]
    aqi         = row["aqi_forecast_avg"]
    bandh       = row["bandh_probability_score"]
    outage      = row["platform_outage_7d_count"]
    radius      = row["avg_delivery_radius_km"]
    hours       = row["avg_daily_active_hours"]
    shift       = row["primary_shift"]           # "morning","afternoon","evening","night"
    vol         = row["earnings_volatility_index"]
    claim_hist  = row["claim_history_score"]
    festival    = row["festival_calendar_flag"]

    # ── Flood risk ─────────────────────────────────────────────────────────
    # Interaction: rain × (1 - elevation/10) × waterlogging_weight
    flood_base = (rain / 250)                        # 0–1
    elev_factor = 1.0 - (elev / 10.0)               # low elev = high factor
    wlog_factor = 1.0 + (wlog / 20.0)               # more incidents = worse
    road_factor = 1.0 - (road / 20.0)               # poor roads amplify
    flood_score = flood_base * elev_factor * wlog_factor * road_factor
    flood_score = min(flood_score, 1.0)

    # ── Heat risk ──────────────────────────────────────────────────────────
    # Interaction: temp × heat_island × shift_exposure
    if temp > 42:
        heat_base = min((temp - 42) / 8.0, 1.0)
    else:
        heat_base = 0.0
    # Afternoon shift fully exposed to peak heat 11AM-4PM
    shift_heat_weights = {
        "morning": 0.3, "afternoon": 1.0, "evening": 0.5, "night": 0.0
    }
    shift_w = shift_heat_weights.get(shift, 0.5)
    heat_score = heat_base * (1 + heat_island / 5.0) * shift_w
    heat_score = min(heat_score, 1.0)

    # ── Wind / cyclone risk ────────────────────────────────────────────────
    wind_score = max(0.0, min((wind - 30) / 90.0, 1.0))

    # ── AQI risk ───────────────────────────────────────────────────────────
    aqi_score = max(0.0, min((aqi - 150) / 350.0, 1.0))

    # ── Civic disruption ──────────────────────────────────────────────────
    civic_score = bandh * 0.65 + (outage / 10.0) * 0.25
    civic_score = min(civic_score, 1.0)

    # ── Rider exposure ────────────────────────────────────────────────────
    # Wide radius = more zone crossings during disruptions
    radius_score = min(radius / 20.0, 1.0)
    hours_score  = min(hours / 14.0, 1.0)
    rider_score  = radius_score * 0.4 + hours_score * 0.25 + vol * 0.25 + claim_hist * 0.1
    rider_score  = min(rider_score, 1.0)

    # ── Festival adjustment ────────────────────────────────────────────────
    # Festivals increase demand → rider earns more → lower risk
    festival_adj = -0.05 if festival else 0.0

    # ── Weighted combination ──────────────────────────────────────────────
    w_risk_raw = (
        0.70                        # base minimum
        + flood_score   * 0.35
        + heat_score    * 0.20
        + wind_score    * 0.15
        + aqi_score     * 0.08
        + civic_score   * 0.12
        + rider_score   * 0.18
        + festival_adj
    )

    # Hard clip — never price someone out during crisis
    return float(np.clip(w_risk_raw, 0.70, 1.80))


def disruption_occurred(row: dict, w_risk: float) -> int:
    """
    Binary label: did an income-loss disruption occur this week?
    Used to train the disruption classifier.
    Probability driven by W_risk + alert level.
    """
    level = row["imd_alert_level_forecast"]
    base_prob = {0: 0.05, 1: 0.20, 2: 0.45, 3: 0.80, 4: 0.97}[level]
    # W_risk above 1.3 also raises probability
    extra = max(0, (w_risk - 1.0) * 0.3)
    prob = min(base_prob + extra, 0.98)
    return int(np.random.random() < prob)


# ── main generation loop ──────────────────────────────────────────────────────

def generate_dataset(n: int = N_ROWS) -> pd.DataFrame:
    rows = []
    zone_names = list(ZONES.keys())

    for i in range(n):
        week_of_year = np.random.randint(0, 52 * 4)   # 4 years of history

        # ── Zone ──────────────────────────────────────────────────────────
        zone_name = np.random.choice(zone_names)
        elev, wlog, road, heat_island = ZONES[zone_name]

        # Add small noise to static features to simulate measurement variance
        elev        = float(np.clip(elev + np.random.normal(0, 0.3), 0, 10))
        wlog        = int(max(0, wlog + np.random.randint(-1, 2)))
        road        = float(np.clip(road + np.random.normal(0, 0.4), 0, 10))
        heat_island = float(np.clip(heat_island + np.random.normal(0, 0.2), 0, 5))

        # ── Platform & tier ───────────────────────────────────────────────
        platform = np.random.choice(PLATFORMS, p=[0.35, 0.35, 0.20, 0.10])
        tier     = np.random.choice(TIERS,     p=[0.25, 0.55, 0.20])
        shift    = np.random.choice(SHIFTS,    p=[0.20, 0.25, 0.40, 0.15])

        # ── Rider profile ─────────────────────────────────────────────────
        # Radius correlates loosely with platform (Zepto has shorter radius)
        radius_means = {"swiggy": 7, "zomato": 7, "zepto": 4, "blinkit": 5}
        radius    = float(np.clip(np.random.normal(radius_means[platform], 2), 1, 20))
        hours     = float(np.clip(np.random.normal(8, 2), 2, 14))
        loy_weeks = int(np.random.choice(
            [0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52],
            p=[0.10, 0.12, 0.12, 0.11, 0.10, 0.09, 0.08, 0.06, 0.05,
               0.05, 0.04, 0.03, 0.03, 0.02]
        ))
        avg_earnings = float(np.clip(np.random.normal(6500, 1800), 2000, 15000))
        earn_vol     = float(np.clip(np.random.beta(2, 5), 0.0, 1.0))
        claim_hist   = float(np.clip(np.random.beta(1.5, 8), 0.0, 1.0))

        # ── Environmental ─────────────────────────────────────────────────
        rain  = pick_rain(week_of_year)
        temp  = pick_temp(week_of_year)
        wind  = pick_wind(rain)
        aqi   = pick_aqi(temp, week_of_year)
        alert = imd_alert_level(rain, wind, temp)

        # ── Civic ─────────────────────────────────────────────────────────
        bandh   = bandh_probability(week_of_year, zone_name)
        outage  = platform_outage_count(platform)
        fest    = festival_flag(week_of_year)
        politic = political_flag(week_of_year)

        row = {
            # IDs
            "rider_id":                      f"R{i:05d}",
            "week_id":                       week_of_year,

            # Group A — Rider profile
            "home_zone_id":                  zone_name,
            "delivery_platform":             platform,
            "tier":                          tier,
            "avg_delivery_radius_km":        round(radius, 2),
            "primary_shift":                 shift,
            "avg_daily_active_hours":        round(hours, 1),
            "loyalty_weeks_active":          loy_weeks,
            "avg_weekly_earnings_4wk":       round(avg_earnings, 0),
            "earnings_volatility_index":     round(earn_vol, 4),
            "claim_history_score":           round(claim_hist, 4),

            # Group B — Zone infrastructure
            "zone_elevation_index":          round(elev, 2),
            "waterlogging_incidents_3yr":    wlog,
            "road_quality_score":            round(road, 2),
            "zone_heat_island_index":        round(heat_island, 2),

            # Group C — Environmental forecast
            "rain_mm_7day_forecast":         round(rain, 1),
            "max_temp_forecast":             round(temp, 1),
            "wind_gust_kmh_forecast":        round(wind, 1),
            "aqi_forecast_avg":              round(aqi, 0),
            "imd_alert_level_forecast":      alert,

            # Group D — Civic intelligence
            "bandh_probability_score":       round(bandh, 4),
            "platform_outage_7d_count":      outage,
            "festival_calendar_flag":        fest,
            "political_event_flag":          politic,
        }

        # ── Labels ────────────────────────────────────────────────────────
        w_risk      = compute_w_risk(row)
        disruption  = disruption_occurred(row, w_risk)
        r_alert     = r_alert_from_level(alert)

        # Derived pricing columns (useful for validation)
        loyalty_disc = round(max(0.70, 1.0 - (loy_weeks // 4) * 0.05), 4)
        base_map     = {"starter": 39, "standard": 69, "shield": 99}
        base         = base_map[tier]
        premium_raw  = round(base * w_risk * loyalty_disc, 2)
        premium_final = round(premium_raw * r_alert, 2) if r_alert > 0 else 0.0

        row["w_risk"]                  = round(w_risk, 4)
        row["disruption_label"]        = disruption
        row["r_alert"]                 = r_alert
        row["loyalty_discount"]        = loyalty_disc
        row["premium_charged"]         = premium_final

        rows.append(row)

    df = pd.DataFrame(rows)
    return df


# ── encode categoricals ───────────────────────────────────────────────────────

def encode_for_model(df: pd.DataFrame) -> pd.DataFrame:
    """
    Label-encode categorical columns.
    XGBoost handles label-encoded categoricals natively.
    Returns df_encoded with original columns preserved.
    """
    from sklearn.preprocessing import LabelEncoder
    df_enc = df.copy()
    cat_cols = ["home_zone_id", "delivery_platform", "tier", "primary_shift"]
    for col in cat_cols:
        le = LabelEncoder()
        df_enc[col + "_enc"] = le.fit_transform(df_enc[col])
        # Print mapping for reference
        mapping = dict(zip(le.classes_, le.transform(le.classes_)))
        print(f"  {col}: {mapping}")
    return df_enc


# ── summary stats ─────────────────────────────────────────────────────────────

def print_summary(df: pd.DataFrame):
    lines = []
    lines.append("=" * 60)
    lines.append("Safety SIP — Dataset Summary")
    lines.append(f"Rows: {len(df)}   Columns: {len(df.columns)}")
    lines.append("=" * 60)

    lines.append("\nW_risk distribution:")
    lines.append(f"  Mean:   {df['w_risk'].mean():.3f}")
    lines.append(f"  Std:    {df['w_risk'].std():.3f}")
    lines.append(f"  Min:    {df['w_risk'].min():.3f}")
    lines.append(f"  Max:    {df['w_risk'].max():.3f}")
    lines.append(f"  > 1.4:  {(df['w_risk']>1.4).sum()} rows ({(df['w_risk']>1.4).mean()*100:.1f}%)")
    lines.append(f"  < 0.85: {(df['w_risk']<0.85).sum()} rows ({(df['w_risk']<0.85).mean()*100:.1f}%)")

    lines.append("\nDisruption rate by IMD alert level:")
    for lvl in range(5):
        sub = df[df["imd_alert_level_forecast"] == lvl]
        if len(sub):
            rate = sub["disruption_label"].mean()
            lines.append(f"  Level {lvl}: {len(sub):4d} rows — {rate*100:.1f}% disruption rate")

    lines.append("\nPremium stats (₹):")
    lines.append(f"  Mean:  ₹{df['premium_charged'].mean():.0f}")
    lines.append(f"  Std:   ₹{df['premium_charged'].std():.0f}")
    lines.append(f"  Min:   ₹{df['premium_charged'].min():.0f}")
    lines.append(f"  Max:   ₹{df['premium_charged'].max():.0f}")
    lines.append(f"  Zeros: {(df['premium_charged']==0).sum()} (cyclone free weeks)")

    lines.append("\nZone distribution:")
    zone_counts = df["home_zone_id"].value_counts()
    for zone, cnt in zone_counts.items():
        avg_risk = df[df["home_zone_id"]==zone]["w_risk"].mean()
        lines.append(f"  {zone:<18} {cnt:4d} rows  avg W_risk={avg_risk:.3f}")

    lines.append("\nPlatform distribution:")
    for plat, cnt in df["delivery_platform"].value_counts().items():
        lines.append(f"  {plat:<10} {cnt:4d} rows")

    lines.append("=" * 60)
    summary = "\n".join(lines)
    print(summary)
    return summary


# ── train a quick baseline model (optional smoke test) ────────────────────────

def quick_train_test(df: pd.DataFrame):
    """
    Trains a quick XGBoost model to verify data is learnable.
    Not the production model — just a sanity check.
    """
    try:
        from xgboost import XGBRegressor, XGBClassifier
        from sklearn.model_selection import train_test_split
        from sklearn.metrics import mean_absolute_error, roc_auc_score
        from sklearn.preprocessing import LabelEncoder

        print("\n--- Quick smoke test ---")

        feature_cols = [
            "zone_elevation_index", "waterlogging_incidents_3yr",
            "road_quality_score", "zone_heat_island_index",
            "rain_mm_7day_forecast", "max_temp_forecast",
            "wind_gust_kmh_forecast", "aqi_forecast_avg",
            "imd_alert_level_forecast", "bandh_probability_score",
            "platform_outage_7d_count", "festival_calendar_flag",
            "political_event_flag", "avg_delivery_radius_km",
            "avg_daily_active_hours", "loyalty_weeks_active",
            "earnings_volatility_index", "claim_history_score",
            "avg_weekly_earnings_4wk",
        ]

        # Encode categoricals
        df_enc = df.copy()
        for col in ["home_zone_id", "delivery_platform", "tier", "primary_shift"]:
            le = LabelEncoder()
            df_enc[col] = le.fit_transform(df_enc[col])
        feature_cols_full = feature_cols + ["home_zone_id", "delivery_platform", "tier", "primary_shift"]

        X = df_enc[feature_cols_full]
        y_reg = df_enc["w_risk"]
        y_cls = df_enc["disruption_label"]

        X_tr, X_te, yr_tr, yr_te, yc_tr, yc_te = train_test_split(
            X, y_reg, y_cls, test_size=0.2, random_state=SEED
        )

        # W_risk regressor
        reg = XGBRegressor(
            n_estimators=200, max_depth=5, learning_rate=0.05,
            subsample=0.8, colsample_bytree=0.8,
            reg_lambda=2, random_state=SEED, verbosity=0
        )
        reg.fit(X_tr, yr_tr)
        preds_r = reg.predict(X_te)
        mae = mean_absolute_error(yr_te, preds_r)
        print(f"  W_risk Regressor MAE: {mae:.4f}  (target < 0.05)")

        # Disruption classifier
        cls = XGBClassifier(
            n_estimators=200, max_depth=4, learning_rate=0.05,
            subsample=0.8, colsample_bytree=0.8,
            use_label_encoder=False, eval_metric="logloss",
            random_state=SEED, verbosity=0
        )
        cls.fit(X_tr, yc_tr)
        preds_c = cls.predict_proba(X_te)[:, 1]
        auc = roc_auc_score(yc_te, preds_c)
        print(f"  Disruption Classifier AUC: {auc:.4f}  (target > 0.85)")

        # Top features
        importances = dict(zip(feature_cols_full, reg.feature_importances_))
        top5 = sorted(importances.items(), key=lambda x: x[1], reverse=True)[:5]
        print("  Top 5 features (W_risk model):")
        for fname, fimp in top5:
            print(f"    {fname:<38} {fimp:.4f}")

        return reg, cls

    except ImportError:
        print("  XGBoost not installed — skipping smoke test.")
        print("  Run: pip install xgboost scikit-learn")
        return None, None


# ── main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("Generating Safety SIP training dataset...")
    print(f"N = {N_ROWS} rows | Seed = {SEED}\n")

    df = generate_dataset(N_ROWS)

    # Save main CSV
    out_path = "training_data.csv"
    df.to_csv(out_path, index=False)
    print(f"Saved: {out_path}  ({os.path.getsize(out_path)//1024} KB)")

    # Save encoded version (ready for XGBoost)
    print("\nEncoding categoricals...")
    df_enc = encode_for_model(df)
    enc_path = "training_data_encoded.csv"
    df_enc.to_csv(enc_path, index=False)
    print(f"Saved: {enc_path}")

    # Print and save summary
    summary = print_summary(df)
    with open("data_summary.txt", "w", encoding="utf-8") as f:
        f.write(summary)
    print("\nSaved: data_summary.txt")

    # Quick model smoke test
    quick_train_test(df)

    print("\nDone. Next step: run train.py with training_data_encoded.csv")
