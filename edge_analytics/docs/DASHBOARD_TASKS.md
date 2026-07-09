# Dashboard — Task Sheet

**Branch:** `dashboard`  ·  Owns: the real-time dashboard + timestamped event log.
Can start NOW against a stub — you don't need the RTL finished.

---

## Goal
A **real-time** dashboard (Python) that reads the chip's live output stream and shows:
- **Live charts** — raw vs smoothed for each channel (moisture, nutrient, temp). Plotting
  raw and smoothed together visibly proves the moving-average filter works.
- **Gauges/indicators** — pump ON/OFF, status (SAFE/WARNING/CRITICAL), crop-health 0–255.
- **Timestamped event log** — a scrolling list: `[t=65000] 💧 Pump ON`,
  `[t=120000] 🌿 Weed detected`, …

## The data you read (frozen contract — build to this)
See `INTERFACES.md §3` for the exact format + field glossary. Two line types on stdin:
```
D,<timestamp>,<moisture>,<nutrient>,<temp>,<avg_m>,<avg_n>,<avg_t>,<pump>,<status>,<health>
E,<timestamp>,<EVENT_NAME>
```
- `D` line (every cycle) → update charts + gauges.
- `E` line (only on an event) → append to the event log with its timestamp.
- Event names: PUMP_ON, PUMP_OFF, WEED_DETECTED, NUTRIENT_LOW, HEAT_STRESS,
  FROST_RISK, SENSOR_ANOMALY, STATUS_CRITICAL.

## How it connects (real-time, no file)
The final wiring is a live pipe:
```
vvp simulation.vvp | python3 dashboard.py
```
Your script reads **stdin** line by line and redraws as each line arrives.

## Start now (in parallel, before the RTL is done)
Build against a **stub** that prints fake `D`/`E` lines in the same format, e.g.
`python3 stub_stream.py | python3 dashboard.py`. Ask the RTL lead for a stub (or write
a tiny one that loops through the story arc). Swap to the real `vvp ...` at Phase 6.

## Suggested tools
- **Streamlit** (fastest good-looking dashboard) or **matplotlib** animation.
- Values are raw 0–4095 counts — scale for display (e.g. moisture 0–4095 → 0–100%,
  temp 0–4095 → 0–50°C). That mapping is your choice.

## Done when
Dashboard updates live from the stream, shows raw-vs-smoothed charts + gauges, and the
event log fills with timestamped events.
