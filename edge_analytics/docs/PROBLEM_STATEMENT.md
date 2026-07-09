# 05 - Edge Analytics IP

> **Our chosen ROBOCHIPX '26 problem statement.** This is a faithful copy of the
> official problem so we don't have to reopen the original PDF while working.

**One-line goal:** Create a lightweight system that can analyze sensor data
instantly on edge devices without depending on cloud processing.

**SDG 9** – Industry, Innovation & Infrastructure
**SDG 11** – Sustainable Cities & Communities

---

## Background

Modern IoT systems generate massive amounts of sensor data, but relying solely on
cloud processing introduces latency, bandwidth costs, and privacy concerns. A
chip-level IP core for edge analytics can enable instant, lightweight data
processing directly on devices, improving responsiveness and efficiency.

## The Challenge

Design and implement a chip-level IP core that collects sensor data, applies
real-time filtering, and generates analytics outputs **without cloud dependency**.
The solution must be lightweight, efficient, and suitable for integration into
embedded IoT systems.

---

## Mandatory Features

*Each feature must be implemented as part of a unified solution.*

### 1. Sensor Data Collection System
- Interface with multiple sensor inputs.
- Ensure reliable acquisition with minimal noise.
- Provide timestamped data for processing.

### 2. Moving Average Filter
- Implement a hardware-efficient moving average algorithm.
- Smooth sensor data to reduce fluctuations.
- Support configurable window sizes.

### 3. Real-Time Data Processing
- Perform analytics directly on edge devices.
- Maintain low latency and minimal resource usage.
- Optimize for embedded system constraints.

### 4. Output Analytics System
- Generate processed insights for immediate use.
- Provide digital outputs for dashboards or controllers.
- Support integration with IoT platforms.

---

## Bonus Features (Optional)
- AI-driven anomaly detection at the edge.
- Multi-sensor fusion for advanced analytics.
- Cloud sync option for hybrid edge-cloud systems.

---

## How our build maps to these features

Application: **Smart Agriculture — Precision Crop Monitor** (soil moisture +
nutrient + temperature → auto-irrigation + alerts).

### Mandatory — all 4 built + simulated

| Mandatory feature | Our module(s) | Status |
|---|---|---|
| 1. Sensor Data Collection System | `sensor_collector` — 3 channels (moisture, nutrient, temp) + timestamp | ✅ built + simulated |
| 2. Moving Average Filter | `moving_avg.v` (configurable window via `LOG2_N`) | ✅ built + simulated |
| 3. Real-Time Data Processing | `analytics_engine` — thresholds + temp-compensated weed detection + joint/correlated fusion | ✅ built + simulated |
| 4. Output Analytics System | `output_analytics` — `pump_on` (hysteresis), `dose_nutrient`, 5 alert lines, status/health | ✅ built + simulated |

### Bonus — all 3 covered, and each EXCEEDED (this is a headline slide)

| Official bonus | What we actually built | Verdict |
|---|---|---|
| AI-driven anomaly detection at the edge | **TEDA self-tuning anomaly** (`adaptive_anomaly.v`, Phase 8F) — a divider-free adaptive statistical detector (running μ+σ², Chebyshev eccentricity), NOT a fixed threshold. Self-calibrates per node. | ✅ **exceeded** |
| Multi-sensor fusion for advanced analytics | **Joint / correlated fusion** (`analytics_engine`, Phase 8C) — interaction-aware `crop_health`; catches channel *combinations* an OR-of-thresholds engine misses. | ✅ **exceeded** |
| Cloud sync option for hybrid edge-cloud systems | **Event-triggered caretaker link** (`comms_tx.v`, Phase 8A) — the *efficient* form of cloud sync: local edge actuation + sparse remote sync ONLY when a human is needed (~85–93% fewer transmissions). | ✅ **covered (smartly)** |

**Talking point:** 4/4 mandatory + 3/3 bonus, and we went *past* each bonus (adaptive vs
fixed anomaly; correlated vs independent fusion; event-triggered vs always-on cloud sync).

### Proposed extra — CROP + SOIL PROFILES (judge-suggested, responsive-to-feedback)

> A judge suggested collecting per-plant data (nutrition / water needs). This feature is
> the direct answer — implementing a judge's own idea is the loudest "we listened" signal.

- **Idea:** thresholds are one-size-fits-all today (`DRY_THRESH`/`NUT_THRESH`/`HOT_THRESH`).
  A **crop profile** makes them *configurable per crop* — a `crop_id` selects the ideal
  moisture / NPK / temperature band for that plant (tomato ≠ wheat ≠ lettuce).
- **Soil too (real agronomic axis):** a `soil_id` adjusts the profile — sandy drains fast
  (higher moisture target, faster depletion baseline), clay holds water (lower trigger,
  slower baseline), loam between. So the setpoints are a `{crop_id, soil_id}` lookup.
- **Build:** a small `crop_profile.v` ROM → `{moisture_target, nutrient_target, temp_hi,
  temp_lo, depletion_baseline}` feeding `analytics_engine`. Synthesizable, clean.
- **Story synergy (why it's not filler):** the profile = agronomy defaults baked in silicon
  (static knowledge); TEDA = the chip self-tuning around them per field (adaptive learning).
  Static + adaptive, working together.
- **Status:** ⬜ proposed. Cost: `analytics_engine` thresholds must become input PORTS
  (currently params) — a bounded change with a built-in regression (defaults must reproduce
  the exact verified behavior). Do AFTER integration + Phase 8D; only if schematic is underway.
