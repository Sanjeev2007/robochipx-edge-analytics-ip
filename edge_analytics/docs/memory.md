# Project Memory — Edge Analytics IP (ROBOCHIPX '26)

> Working notes and decisions for this project. Read this first when resuming.
> Keep it up to date as things change.

## 🧭 NEW AGENT? ONBOARD HERE (a different agent may run each phase)
Read in order, then do your assigned phase:
1. **this file** (`docs/memory.md`) — goal, constraints, decisions, module status (§6).
2. `docs/INTERFACES.md` — frozen signal + live-stream contract; build against it exactly.
3. `docs/BUILD_PLAN.md` — phase-by-phase steps; find your phase.
4. `docs/CHANGELOG.md` — what's already done.
5. `docs/FEATURES.md`, `docs/ROADMAP.md` — feature detail + team/timeline (reference).

**On finishing work, update `CHANGELOG.md` + this file's status table by default (no
asking).** RTL `.v` files live at `edge_analytics/`; docs at `edge_analytics/docs/`.

---

## 1. What we're building
- **Event:** ROBOCHIPX '26 chip-design hackathon.
- **Chosen problem:** #5 — Edge Analytics IP (full spec in `PROBLEM_STATEMENT.md`).
- **Real-world application (LOCKED IN):** **Smart Agriculture — Precision Crop
  Monitor.** A chip in the field that reads soil moisture, nutrient level, and
  temperature, smooths the noisy readings, and:
    - **auto-deploys water** (turns on an irrigation pump) when soil is dry,
    - raises alerts for low nutrients or out-of-range temperature,
    - detects "resource theft" (a weed) by spotting an abnormal depletion rate.
  All on-device, no cloud.
- **Pitch line:** "Our chip waters the crop automatically the moment the soil
  runs dry, flags missing nutrients, and detects resource-stealing weeds — right
  in the field, instantly, without the cloud."

## 2. KEY CONSTRAINTS (do not forget)
- ✅ **Hardware implementation is NOT required.** The deliverable is **Verilog
  RTL + simulations + test results** (waveforms + console output). No FPGA/board.
- Code must be **synthesizable Verilog** (teammates may synthesize later on
  Windows via Vivado/Quartus), but proving it in `iverilog`/`gtkwave` is enough.
- **No cameras / computer vision.** Weed detection is done via anomalous
  resource-depletion rate (scalar sensor math), NOT image processing — that keeps
  it beginner- and simulation-friendly.
- User is a **beginner** at Verilog / first hackathon. Plain-English explanations,
  tiny modular blocks, a testbench for every block.
- Dev machine: **macOS (MacBook Air)**. Simulate locally.

## 3. Toolchain
- `icarus-verilog` — INSTALLED via Homebrew (`iverilog`, `vvp`). ✅
- `gtkwave` — NOT installed yet. `brew install --cask gtkwave` when we want to
  view waveforms visually. Console `$display` output works without it.

## 4. Inner-loop commands (per CLAUDE.md)
```bash
cd edge_analytics
iverilog -o simulation.vvp <design>.v <testbench>.v   # compile
vvp simulation.vvp                                    # run + generate dump.vcd
gtkwave dump.vcd                                       # view waveform
```
Every testbench must `$dumpfile("dump.vcd")` + `$dumpvars` so waveforms exist.

## 5. Code rules (from CLAUDE.md — repo dev conventions, auto-loaded by agents)
- Synthesizable Verilog only; avoid software-like constructs.
- Explicit plain-English comments on every module (inputs/outputs/registers/logic).
- No code dumps — one small block at a time, each with its own testbench.
- Always include `clk` and `rst` on sequential modules.

## 6. Architecture / module plan
Three sensor channels for the demo: **soil moisture, nutrient (NPK), temperature.**

| # | Module | Role | Status |
|---|---|---|---|
| 1 | `sensor_collector` | Collect the 3 sensor channels in parallel, add a timestamp counter | ✅ built + simulated |
| 2 | `moving_avg` | Per-channel smoothing (running accumulator + shift-divide) | ✅ built + simulated |
| 2b | `smoothing_stage` | Phase 2 wiring: `moving_avg` ×3 (one/channel) + 1-cycle timestamp delay to keep "when" aligned with the smoothed set | ✅ built + simulated |
| 3 | `analytics_engine` | Thresholds → status; plus depletion-rate check for weed/anomaly | ✅ built + simulated |
| 4 | `output_analytics` | Registered actuator/alert bus: `pump_on` (hysteresis), `dose_nutrient`, `alert_*`, PUMP_ON/OFF events, status pass-through | ✅ built + simulated |
| 5 | `edge_analytics_top` | Wire the 4 blocks + latency-alignment delay lines (raw/ts +3, avg +2); aligned output bundle | ✅ built + simulated |
| 5.5 | `edge_analytics_tb` egress | Testbench-only: emit the dashboard's 17-field CSV (header once + row/cycle) with count→display-unit scaling; RTL untouched | ✅ done + simulated |

## 7. Key design decisions
- **Window size is a power of two** (`N = 2^LOG2_N`) so "divide by N" is a cheap
  right-shift — no divider hardware. Beginner-friendly and area-efficient.
- **Running accumulator:** `acc = acc + newest - oldest` → O(1) per sample.
- Moving average SMOOTHS/hides spikes; the analytics/threshold engine CATCHES
  problems (dry soil, low nutrient, abnormal depletion). Complementary blocks.
- **Auto-irrigation = closed-loop control.** The output does something real
  (`pump_on`), not just an alert — the standout demo moment.
- **Weed detection = anomaly, not vision.** A weed steals water/nutrients, so
  moisture/nutrient dropping abnormally fast (even right after watering) = a weed.
  Handled by trend/rate logic; no camera.
- **Dashboard egress = LIVE STREAM, not a saved file.** The sim `$display`s each
  result line to stdout; we pipe it straight into Python for a REAL-TIME dashboard:
  `vvp simulation.vvp | python3 dashboard.py`. No CSV file. Two line types:
  `D,...` = continuous data (charts/gauges), `E,<timestamp>,<event>` = discrete
  events (feeds the timestamped event log). See `INTERFACES.md` for the format.

## 8. Demo plan

### ⚠️ DASHBOARD INTEGRATION CHECKPOINT (don't forget — happens at Phase 6)
The dashboard is built in parallel against `stub_stream.py`. **Integration is one
command change**, done ON THE MAC after Phase 5 gives the real stream:
- Get the dashboard person's `dashboard.py` (their `dashboard` branch or they send it).
- `pip install` whatever it needs (streamlit/matplotlib), ensure `python3` is present.
- Swap the stub for the real sim — SAME dashboard, no code change (both use `INTERFACES.md §3`):
  - dev:         `python3 stub_stream.py | python3 dashboard.py`
  - integrated:  `vvp simulation.vvp     | python3 dashboard.py`
- If a field mismatches, it shows instantly → quick fix on either side (contract is truth).

Testbench acts as the field sensors. Sequence:
1. Healthy crop — steady soil moisture / nutrient / temp with realistic jitter.
2. Soil dries out slowly → filter confirms the real downward trend (not noise) →
   `pump_on` fires → moisture recovers. (Closed-loop control shown.)
3. Nutrient level drops below threshold → `alert_nutrient` pulses.
4. Abnormally fast moisture drain right after watering → `alert_weed` (resource
   theft) pulses.
Waveform to capture: raw sensor → smoothed average → `pump_on` / alert flags.

## 9. Requirement coverage (mandatory vs bonus)
- Mandatory: features 1–4 (all must exist). See table in `PROBLEM_STATEMENT.md`.
- Bonus we get "for free": anomaly detection (depletion rate) + multi-sensor
  fusion (combined plant-health verdict).
- **Cloud-sync bonus = on-chip UART egress + a local real-time dashboard.** The
  actual cloud *service* is out of scope, but the chip's egress interface and the
  live dashboard are what we build and demo. (Corrected: earlier note said "out of
  RTL scope" — the egress interface IS in scope.)

## 10. 🔴 CURRENT STATUS — read this to know where we are RIGHT NOW
_(Last live snapshot. Update when the situation changes.)_
- **Built:** Phases 1–5 (FULL chip integrated + aligned output bundle) **and Phase 5.5
  (egress reconciled to the dashboard's 17-field CSV)**. All pushed to `main`.
- **✅ Phase 5.5 DONE (contract mismatch RESOLVED):** `edge_analytics_tb.v` now emits
  the dashboard's 17-field CSV — header once, then one row per `out_valid` cycle:
  `timestamp,moisture_raw,nutrient_raw,temp_raw,moisture_avg,nutrient_avg,temp_avg,
  pump_on,dose_nutrient,alert_nutrient,alert_weed,alert_heat,alert_frost,alert_anomaly,
  status,crop_health,relocate_recommend`. Count→display scaling in the testbench:
  moisture/nutrient `count/5` (clamp 0–100), temp `count/10`, crop_health `health*100/255`,
  status numeric 0/1/2, pump/dose/alert_* pass-through, `relocate_recommend = status==2 &&
  scaled_health<35`. **No `.v` module touched.** `INTERFACES.md §3` updated to own this
  contract. Verified: 56 rows × exactly 17 fields, ranges in-band, RESULT PASS (0 errors),
  and the dashboard's own `parse_sample()` ingests header (skipped) + rows cleanly.
  The dashboard (`robochipx_dashboard_handoff/edge_agri_dashboard.py`) stays UNTOUCHED.
- **Data teammate:** on ChatGPT, at lunch. NOT a blocker — the lead/Claude can generate
  and verify the canonical story-trace directly against the RTL (Phase 5 tb already has
  a working 56-sample trace). Their trace is a later realism refinement.
- **Teammates have NO coding assistant** (plain ChatGPT, no repo access) → each task
  sheet carries a fully self-contained paste-in prompt (see `DATA_TASKS.md`).
- **⚠️ TWO INTEGRATION FOLLOW-UPS found while verifying Phase 5.5 (fix before Phase 6 live demo):**
  1. **tkinter missing on the Mac** — `python3` (Homebrew) has no `_tkinter`, so the
     dashboard GUI won't launch. Fix: `brew install python-tk` (match the brew python
     version). Needed for `vvp simulation.vvp | python3 edge_agri_dashboard.py`.
  2. **Diagnostic banner pollutes the stream** — the testbench's `RESULT: PASS ...`
     summary prints to stdout and the dashboard's loose parser turns it into ONE bogus
     zero-sample. Fix: prefix all non-CSV/diagnostic testbench lines with `#` (the
     dashboard's `parse_sample` skips `#` lines). Also mind the `VCD info:` line (it's
     harmlessly skipped — 7 tokens < 8).
- **NEXT ACTIONS:** (1) ~~reconcile egress~~ ✅ done; (2) fix the two follow-ups above;
  (3) generate + verify the canonical story-trace; (4) Phase 6 full demo (swap trace,
  capture waveforms, live dashboard integration on the Mac — see §8 checkpoint).
