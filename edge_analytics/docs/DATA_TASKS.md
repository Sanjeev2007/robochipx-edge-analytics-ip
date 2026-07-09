# Demo Data & Calibration — Task Sheet

**Branch:** `data`  ·  Owns: the canonical demo story-trace, realistic sensor
calibration, and a stub data feed for the dashboard. Can start NOW — no RTL needed.

This role feeds everyone: the RTL lead bakes your trace into the integration
testbench (Phase 6), and the dashboard person develops live against your stub feed.

---

## Task 1 — The canonical demo story-trace (most important)
Design ONE authoritative sequence of sensor readings that tells the whole story. Every
demo/testbench uses this. Values are 12-bit counts (0–4095). Keep it consistent with
the thresholds in `INTERFACES.md §5` (DRY=200, PUMP_OFF=350, RATE=100 over 4 samples,
HOT=400, NUT=250, COLD=100).

| Phase | ~samples | moisture | nutrient | temp | Must demonstrate |
|---|---|---|---|---|---|
| A. Healthy | 8 | ~320 (±5 jitter) | ~305 | ~380 | SAFE baseline; filter smooths jitter |
| B. Dry spell | 12 | falls gently ~320→180 (~10/sample) | ~305 | ~380 | `dry`→pump ON; slope gentle so **weed does NOT fire** |
| C. Recovery | 6 | rises ~180→360 | ~305 | ~380 | pump hysteresis; pump OFF at >350 |
| D. Weed | 8 | drops STEEPLY ~360→200 (~40/sample) | ~300 | ~380 | fast drop + not hot → **`weed` fires** |
| E. Heat | 8 | drifts down | ~300 | climbs ~380→430 | `hot` fires; weed **suppressed** (hot = evaporation) |
| F. Nutrient low | 6 | ~320 | falls ~300→220 (<250) | ~380 | `alert_nutrient` |

**Deliverable:** the table above turned into **exact per-sample number lists** (e.g. a
plain list of `moisture,nutrient,temp` rows) the RTL lead can paste into the Phase 6
testbench. The key contrast: phase B gentle slope = NO weed, phase D steep slope = weed.

## Task 2 — Realistic calibration (makes the demo credible)
The chip works in raw 0–4095 counts. Research real farm ranges and give a
**count → real-unit mapping** so the dashboard and thresholds look believable:
- soil moisture % (e.g. 0–4095 → 0–100 %VWC),
- nutrient / NPK (ppm or an index),
- temperature °C (e.g. 0–4095 → 0–50 °C).
Note what each threshold means in real units (e.g. "DRY=200 ≈ 5% moisture").
Hand this mapping to the dashboard person for display scaling.

## Task 3 — Dashboard stub feed (unblocks the dashboard person NOW)
Write a tiny generator that prints fake `D`/`E` lines (per `INTERFACES.md §3`) following
the story-trace above — e.g. `stub_stream.py`. Then the dashboard person can build the
live dashboard today with realistic data:
```
python3 stub_stream.py | python3 dashboard.py
```
Later this is swapped for the real `vvp simulation.vvp | ...`.

## Done when
- The canonical trace exists as concrete number lists (given to RTL lead).
- The count→real-unit calibration is documented (given to dashboard person).
- `stub_stream.py` runs and emits valid `D`/`E` lines for the whole story.
