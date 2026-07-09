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

---

## 🤖 If you only have ChatGPT (no coding assistant): paste this in

ChatGPT can't see our project, so this prompt contains everything it needs. Copy the
whole block below into ChatGPT. It will give you all three deliverables.

```
I'm on a hackathon team building a Verilog chip for "smart agriculture" — it reads 3
soil sensors and reacts. I'm the DATA person: I don't write Verilog, I produce demo
data and one small Python script. Here is all the context you need.

THE CHIP reads 3 sensors every cycle — soil moisture, nutrient (NPK), temperature.
Each is a 12-bit number (raw sensor counts, range 0-4095). It smooths each one (moving
average of the last 8 samples) and makes decisions with these thresholds:
- dry: moisture < 200  -> turns ON an irrigation pump
- pump turns OFF only when moisture > 350 (this gap is hysteresis, to stop chatter)
- low nutrient: nutrient < 250
- hot: temp > 400
- cold: temp < 100
- WEED: moisture dropping abnormally FAST (more than 100 counts over 4 samples) AND not
  hot. A gentle slow drop = normal drying = NOT a weed. A steep fast drop at normal
  temperature = a weed stealing water. If it's hot, a fast drop is just evaporation = NOT
  a weed.

Give me THREE things:

1) DEMO STORY-TRACE — a list of sensor readings, one row per sample as CSV
"moisture,nutrient,temp", with small +/-5 random jitter on steady values, walking through:
  - Phase A Healthy (8 samples): moisture ~320, nutrient ~305, temp ~380 (all safe)
  - Phase B Dry spell (12 samples): moisture falls GENTLY ~320 -> ~180 (~10/sample; must
    NOT trigger weed), nutrient ~305, temp ~380
  - Phase C Recovery (6 samples): moisture rises ~180 -> ~360, others same
  - Phase D Weed (8 samples): moisture drops STEEPLY ~360 -> ~200 (~40/sample; MUST
    trigger weed), nutrient ~300, temp ~380 (normal)
  - Phase E Heat (8 samples): temp climbs ~380 -> ~430 (crosses 400), moisture drifts
    down a little (weed must be SUPPRESSED here because it's hot), nutrient ~300
  - Phase F Nutrient low (6 samples): nutrient falls ~300 -> ~220 (crosses 250),
    moisture ~320, temp ~380
  Output the full row list, labelled by phase, ready to paste into a Verilog testbench.

2) CALIBRATION TABLE mapping raw counts (0-4095) to real farm units, and what each
threshold means in real units: moisture 0-4095 -> 0-100% water content; temperature
0-4095 -> 0-50 C; nutrient 0-4095 -> 0-1000 ppm. E.g. "dry threshold 200 = X% moisture",
"hot threshold 400 = Y C".

3) A PYTHON SCRIPT called stub_stream.py that PRINTS the live stream our dashboard reads.
Loop through the story-trace above and print two kinds of lines to standard output:
  - every sample, a data line:
    D,<timestamp>,<moisture>,<nutrient>,<temp>,<avg_moisture>,<avg_nutrient>,<avg_temp>,<pump_on>,<status>,<crop_health>
    timestamp starts at 100 and increments by 100 each sample; the avg_ values are a
    moving average of the last 8 samples; pump_on is 1 when smoothed moisture < 200 and
    stays 1 until smoothed moisture > 350; status is 0=safe / 1=one problem / 2=weed or
    two+ problems; crop_health is 0-255 (255 minus: dry 60, low_nutrient 50, hot 50,
    cold 50, weed 80).
  - whenever something starts, also an event line:
    E,<timestamp>,<EVENT_NAME>
    event names: PUMP_ON, PUMP_OFF, WEED_DETECTED, NUTRIENT_LOW, HEAT_STRESS, FROST_RISK,
    SENSOR_ANOMALY, STATUS_CRITICAL
  Put a 0.3 second delay between samples so it looks live. It must be pipeable:
  `python3 stub_stream.py | python3 dashboard.py`.

Give me: the story-trace rows, the calibration table, and the complete stub_stream.py.
```

### What to do with ChatGPT's answer
1. Save its Python as `stub_stream.py`; test it: `python3 stub_stream.py` (you should see
   `D,...` and `E,...` lines scrolling). Send this file to the dashboard person.
2. Copy the story-trace row list and send it to the RTL lead (for the Phase 6 testbench).
3. Copy the calibration table and send it to the dashboard person (for display scaling).
4. To share files without git: use GitHub's **Add file → Upload** on your `data` branch
   in the web browser, or just message the files to the team lead.

