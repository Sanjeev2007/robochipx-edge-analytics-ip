# 🌱 Project Overview — Edge Analytics IP (Smart Agriculture)

*A one-page explainer for anyone picking up this folder cold. For the day-of Q&A crib
sheet, see `JUDGE_CHEATSHEET.md`; for slide-by-slide text, see `../docs/SLIDE_CONTENT.md`.*

## The one-sentence pitch
An on-chip **edge-analytics core for precision farming** — it reads soil sensors, smooths
the noisy signals, decides what's wrong, and **acts automatically** (waters the crop, flags
low nutrients, catches resource-stealing weeds, ignores broken sensors) — all in
microseconds, **on the device, with no cloud**.

## The hackathon context
- **Event:** ROBOCHIPX '26 chip-design hackathon.
- **Problem chosen:** #5 — **Edge Analytics IP** (lightweight on-device sensor analytics).
- **Application chosen:** Smart Agriculture — a Precision Crop Monitor.
- **Deliverable:** synthesizable **Verilog RTL + simulations + test results** (waveforms /
  console output via `iverilog` + `gtkwave`). Building physical hardware is **not** required
  — proving it in simulation is enough.

## What the chip does — detect → decide → act
| Detects | Automatic response | Signal |
|---|---|---|
| Dry soil | Turns on the irrigation pump (with hysteresis so it doesn't chatter) | `pump_on` |
| Resource-stealing **weed** | Alert — spotted via abnormal moisture-depletion rate, temperature-compensated | `alert_weed` |
| Low nutrients | Fertilizer-doser trigger | `dose_nutrient` |
| Heat / frost | Climate-protection alerts | `alert_heat` / `alert_frost` |
| Faulty sensor | Ignores it, keeps running | `alert_anomaly` |
| Overall crop health | SAFE / WARNING / CRITICAL + fused health score | `status`, `crop_health` |

## How it's built (data flow)
```
 3 sensors          smoothing          decisions           actions          live stream
┌──────────┐      ┌────────────┐     ┌────────────┐     ┌────────────┐     ┌───────────┐
│ moisture │      │ moving_avg │     │ thresholds │     │ pump_on    │     │ D/E lines │
│ nutrient │─────►│    ×3      │────►│ + weed     │────►│ alerts     │────►│ → Python  │
│ temp     │ +ts  │            │     │ + fusion   │     │ status     │     │ dashboard │
└──────────┘      └────────────┘     └────────────┘     └────────────┘     └───────────┘
 sensor_collector  smoothing_stage    analytics_engine   output_analytics
```
Each stage is a small, separately-tested Verilog module (`*.v` at `edge_analytics/`, each
with its own `*_tb.v` testbench). They compose into `edge_analytics_top.v`.

## The headline result (the honest numbers)
- **6 packets transmitted vs 223 samples analyzed → ~97% fewer radio transmissions.** That's
  the whole point of edge analytics: only speak up when something matters.
- Resource cost: **~1,245 LUTs · 1,163 FFs · 3 DSPs · ~6% of an Artix-7 (xc7a35t)**.
- Verification: full story trace runs **223 samples, PASS, 0 errors**.
- We do **not** quote Fmax or a power number (those need a Vivado place-and-route we didn't run).

## Seeing it run
Open `../demo/mission_control.html` in a browser and press Play — it replays the 223-sample
story and the transmission counter settles at **223 vs 6 → 97%**.

## Where things live
- `edge_analytics/*.v` — the RTL modules + testbenches (the actual chip).
- `edge_analytics/docs/` — problem statement, interfaces, build plan, slide content.
- `edge_analytics/demo/` — the live browser dashboard used for the demo.
- `edge_analytics/presentation/` — **you are here**: everything for the evaluation day.
