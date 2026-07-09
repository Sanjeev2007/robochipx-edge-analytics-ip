# 🌱 Edge Analytics IP — Smart Agriculture

**An on-chip edge-analytics core for precision farming.** It reads soil sensors,
smooths the noisy signals, decides what's wrong, and **acts automatically** — waters
the crop, flags low nutrients, catches resource-stealing weeds, and shrugs off broken
sensors — all in microseconds, on the device, with **no cloud**.

> *ROBOCHIPX '26 — Problem #5 (Edge Analytics IP) · SDG 9 & 11 · Verilog RTL, verified by simulation.*

---

## What it does

The chip runs a full **detect → decide → act** loop on-device:

| Detects | Automatic response | Signal |
|---|---|---|
| Dry soil | Turns on the irrigation pump (with hysteresis) | `pump_on` |
| Resource-stealing **weed** | Alert — spotted via abnormal moisture depletion rate, temperature-compensated so a hot day isn't a false alarm | `alert_weed` |
| Low nutrients | Fertilizer-doser trigger / alert | `dose_nutrient` |
| Heat / frost | Climate-protection alerts | `alert_heat` / `alert_frost` |
| Faulty sensor | Ignores it, keeps running | `alert_anomaly` |
| Overall crop health | SAFE / WARNING / CRITICAL + fused health score | `status`, `crop_health` |

Every result streams live to a **real-time dashboard** with a timestamped event log.

## Architecture

```
 3 sensors          smoothing          decisions           actions          live stream
┌──────────┐      ┌────────────┐     ┌────────────┐     ┌────────────┐     ┌───────────┐
│ moisture │      │ moving_avg │     │ thresholds │     │ pump_on    │     │ D/E lines │
│ nutrient │─────►│    ×3      │────►│ + weed     │────►│ alerts     │────►│ → Python  │
│ temp     │ +ts  │            │     │ + fusion   │     │ status     │     │ dashboard │
└──────────┘      └────────────┘     └────────────┘     └────────────┘     └───────────┘
 sensor_collector  smoothing_stage    analytics_engine   output_analytics
```

## Repository layout

```
edge_analytics/
├── *.v                    # synthesizable Verilog modules + testbenches
├── docs/
│   ├── PROBLEM_STATEMENT.md   # the official problem #5
│   ├── INTERFACES.md          # frozen signal + live-stream contract (build to this)
│   ├── BUILD_PLAN.md          # phase-by-phase build plan (multi-agent ready)
│   ├── FEATURES.md            # full feature showcase + pitch
│   ├── ROADMAP.md             # tiers, team split, 24h timeline
│   ├── WORKFLOW.md            # git branch-per-task workflow
│   ├── SYNTHESIS_TASKS.md     # task sheet: FPGA synthesis + demo data
│   ├── DASHBOARD_TASKS.md     # task sheet: real-time dashboard
│   ├── PRESENTATION_TASKS.md  # task sheet: slides + demo script
│   ├── memory.md              # project brain (read first)
│   └── CHANGELOG.md           # history
CLAUDE.md                  # dev/code conventions (auto-loaded by Claude agents)
```

## Quick start (simulation)

Requires [Icarus Verilog](http://iverilog.icarus.com/) (`brew install icarus-verilog`).

```bash
cd edge_analytics
# compile a module with its testbench
iverilog -o simulation.vvp analytics_engine.v analytics_engine_tb.v
# run it (prints results, dumps dump.vcd)
vvp simulation.vvp
# optional: view the waveform
gtkwave dump.vcd
```

## Real-time dashboard

The final chip streams `D` (data) and `E` (event) lines to stdout; pipe them straight
into the Python dashboard — no intermediate file:

```bash
vvp simulation.vvp | python3 dashboard/dashboard.py
```

See `edge_analytics/docs/INTERFACES.md §3` for the exact stream format.

## Build status

| Phase | Module | Feature | Status |
|---|---|---|---|
| 1 | `sensor_collector` | Sensor collection + timestamps (#1) | ✅ |
| 2 | `smoothing_stage` | Moving-average filter ×3 (#2) | ✅ |
| 3 | `analytics_engine` | Real-time decisions + weed/anomaly (#3) | ✅ |
| 4 | `output_analytics` | Actuator/alert outputs (#4) | ⬜ |
| 5 | egress stream | Live dashboard feed (cloud-sync bonus) | ⬜ |
| 6 | `edge_analytics_top` | Integration | ⬜ |

## Team workflow

Everyone works on a task branch and merges into `main` via PR — see
`edge_analytics/docs/WORKFLOW.md`. Task sheets: `SYNTHESIS_TASKS.md`,
`DASHBOARD_TASKS.md`, `PRESENTATION_TASKS.md`.

## Note on deliverable

Hardware fabrication is **not required** — the deliverable is synthesizable Verilog
RTL proven by simulation and waveforms. FPGA synthesis (Vivado/Quartus) is a bonus that
provides resource/timing/power numbers.
