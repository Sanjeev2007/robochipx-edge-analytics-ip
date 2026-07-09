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

| Mandatory feature | Our module(s) | Status |
|---|---|---|
| 1. Sensor Data Collection System | `sensor_collector` — 3 channels (moisture, nutrient, temp) + timestamp | ⬜ planned |
| 2. Moving Average Filter | `moving_avg.v` (configurable window via `LOG2_N`) | ✅ built + simulated |
| 3. Real-Time Data Processing | `analytics_engine` — thresholds + depletion-rate anomaly | ⬜ planned |
| 4. Output Analytics System | `output_analytics` — `pump_on`, `alert_nutrient`, `alert_weed`, status | ⬜ planned |
| Bonus: AI-driven anomaly detection | depletion-rate check in `analytics_engine` (weed = resource theft) | ⬜ planned |
| Bonus: Multi-sensor fusion | combined plant-health verdict from 3 channels | ⬜ optional |
| Bonus: Cloud sync | out of RTL scope — mention in writeup only | ⬜ optional |
