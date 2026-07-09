# Teammate B — Task Sheet (Synthesis + Story-Trace Data)

You own two things that aren't slides or the dashboard: **(1) synthesis + hardware
reports**, and **(2) the demo story-trace data**. Both can start now.

---

## PART 1 — Synthesis & hardware reports

**Why it matters:** hardware isn't required (we deliver simulation), so this is
*bonus credibility* — it proves our Verilog is genuinely buildable silicon and gives
real numbers ("uses 3% of the chip, runs at 150 MHz, 40 mW") for the slides.

### Setup (do this first — the install is slow)
1. Install **Xilinx Vivado** (or **Intel Quartus**) on your Windows machine.
2. Pick a target device for reporting — e.g. **Xilinx Artix-7 (Basys-3, xc7a35t)**.
3. Clone the repo and make your branch (see `WORKFLOW.md`): `git checkout -b teammate-b-synth`.

### Rolling synthesis (start NOW — 3 modules are already done)
Already in the repo and ready to synthesize:
`moving_avg.v`, `sensor_collector.v`, `smoothing_stage.v`.
For each finished module as it lands (later: `analytics_engine.v`, `output_analytics.v`):
1. New Vivado project → **Add Sources** → add the `.v` files → set the top module.
2. **Run Synthesis.** Confirm it finishes with **no errors**.
3. Note any **warnings** (inferred latches, un-reset registers, multi-driven nets) and
   report them back to the RTL lead — these are real bugs to fix early.

### Phase 6 — the big one (full chip)
When `edge_analytics_top.v` exists, synthesize the whole design and capture:
- **Utilization report** — LUTs / flip-flops / % of chip → proves "lightweight".
- **Timing report** — max frequency (Fmax) → proves "real-time".
- **Power report** — estimated mW → proves "efficient edge".
- **RTL / synthesized schematic** — screenshot for the architecture slide.

Hand those 4 items to Teammate D for the deck. **Stop at reports** — no bitstream / no
board needed (hardware is out of scope). Don't let tool trouble block the demo.

---

## PART 2 — Demo story-trace data (you own this)

Every testbench in Phases 3–6 plays the same sensor sequence. Design it once, here, so
it's consistent. Values are 12-bit counts (0–4095). Keep it consistent with the
thresholds in `INTERFACES.md §5` (DRY=200, RATE=100 over 4 samples, HOT=400, NUT=250).

| Phase | ~samples | moisture | nutrient | temp | What it demonstrates |
|---|---|---|---|---|---|
| A. Healthy | 8 | ~320 (±5 jitter) | ~305 | ~380 | SAFE baseline; filter smooths jitter |
| B. Dry spell | 12 | falls gently ~320→180 (~10/sample) | ~305 | ~380 | `dry` fires (<200) → pump; slope gentle so **weed does NOT fire** |
| C. Recovery | 6 | rises ~180→360 (pump watered) | ~305 | ~380 | pump hysteresis; moisture recovers |
| D. Weed | 8 | drops STEEPLY ~360→200 (~40/sample) | ~300 | ~380 (normal) | fast drop + not hot → **`weed` fires** |
| E. Heat | 8 | drifts down | ~300 | climbs ~380→430 (>400) | `hot` fires; and weed **suppressed** because hot = evaporation (temp-compensation) |
| F. Nutrient low (opt) | 6 | ~320 | falls ~300→220 (<250) | ~380 | `alert_nutrient` |

**Key design intent:** phase B (gentle slope) must NOT trigger weed, but phase D (steep
slope, same temp) MUST — that contrast is the proof the rate detector works. Give this
table (or exact number lists) to the RTL lead to bake into the testbenches.
