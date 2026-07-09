# Build Plan — phase by phase (multi-agent ready)

> The project is built one phase at a time. A **different agent may run each phase**,
> so this file + the other docs must be enough to onboard cold. Keep them current.

---

## HOW TO USE THIS FILE (agent protocol)

**Before starting any phase, an agent MUST read (in order):**
1. `docs/memory.md` — project goal, constraints, decisions, module status.
2. `docs/INTERFACES.md` — the frozen signal + stream contract (build against this).
3. `docs/BUILD_PLAN.md` (this file) — find your phase below.
4. `docs/CHANGELOG.md` — what's already done.

**Rules while working:**
- Follow the README code rules (synthesizable, commented, `clk`/`rst`, one small
  block + its own testbench, VCD dump).
- Build against `INTERFACES.md` signal names/widths EXACTLY. If you must change the
  contract, update `INTERFACES.md` and shout about it in the changelog.
- Compile + simulate before declaring done: `iverilog -o simulation.vvp <files>` then `vvp simulation.vvp`.

**On finishing a phase, an agent MUST (no need to ask permission):**
- Update `docs/CHANGELOG.md` (what was added/verified).
- Update `docs/memory.md` module-status table (⬜ → ✅).
- Note any interface changes in `docs/INTERFACES.md`.

**Status legend:** ⬜ not started · 🟡 in progress · ✅ done + simulated

---

## Phase 1 — `sensor_collector`   (mandatory #1)   Status: ⬜
- **Owner:** RTL lead. **Depends on:** nothing.
- **Goal:** the 3-channel sensor front-end that timestamps every reading.
- **Build (`sensor_collector.v`):**
  - A free-running **32-bit timestamp counter** that increments every clock (resets to 0).
  - Register the 3 raw inputs (`moisture_in`, `nutrient_in`, `temp_in`) and pass them
    out aligned as `moisture`, `nutrient`, `temp` with the current `timestamp` and `sample_valid`.
  - Interface: see `INTERFACES.md` §2 `sensor_collector` (parallel).
- **Testbench (`sensor_collector_tb.v`):** feed 3 changing fake sensor values; check
  they appear on the outputs with a monotonically increasing timestamp and correct `valid`.
- **Done when:** waveform/console shows the 3 channels passing through, each set
  tagged with an increasing timestamp.

## Phase 2 — wire in `moving_avg` (×3)   (mandatory #2)   Status: ✅ built + simulated  (`moving_avg` ✅ already built)
- **Owner:** RTL lead. **Depends on:** Phase 1.
- **Goal:** smooth each of the 3 channels.
- **Build (`smoothing_stage.v`, with its own testbench):** instantiate `moving_avg`
  three times — one per channel — fed by `sensor_collector` outputs
  (`moisture`/`nutrient`/`temp`, each with `sample_valid`). Produce `avg_moisture`,
  `avg_nutrient`, `avg_temp` + `avg_valid`.
- **⚠️ Alignment (must handle):** `moving_avg` registers its output, so the smoothed
  value appears ONE cycle after the raw input. Delay `timestamp` by one cycle inside
  this stage (a single register) so the timestamp exits aligned with the smoothed
  outputs and `avg_valid`. The 3 channels share identical timing, so one `avg_valid`
  represents the set.
- **Reuse:** `moving_avg` is already built at `edge_analytics/moving_avg.v` — do not
  rewrite it; instantiate it (params `DATA_WIDTH=12`, `LOG2_N=3`).
- **Test:** feed a noisy per-channel input; confirm each smoothed output tracks its
  channel with noise removed, and that `avg_*` + the delayed `timestamp` + `avg_valid`
  all line up on the same cycle.
- **Done when:** each smoothed output follows its channel, and timestamp stays aligned.

## Phase 3 — `analytics_engine`   (mandatory #3 + bonuses)   Status: ⬜
- **Owner:** RTL lead. **Depends on:** Phase 2.  **Interface:** `INTERFACES.md` §2 `analytics_engine`.
- **Goal:** turn the smoothed set into decisions, a health score, a status, AND
  timestamp each event. Register all outputs (1-cycle), so `out_valid` = `in_valid`
  delayed one cycle. Params/thresholds live in `INTERFACES.md` §5 — use named params.

- **(a) Threshold conditions (combinational):**
  - `dry        = avg_moisture < DRY_THRESH`   (200)
  - `low_nutrient = avg_nutrient < NUT_THRESH`  (250)
  - `hot        = avg_temp > HOT_THRESH`        (400)
  - `cold       = avg_temp < COLD_THRESH`       (100)

- **(b) Weed = abnormal moisture DEPLETION RATE, temperature-compensated:**
  - Keep a small history of `avg_moisture` from `HIST_DEPTH` valid-samples ago
    (shift register depth `HIST_DEPTH`=4; push `avg_moisture` on each `in_valid`).
  - `dropped = moist_hist[HIST_DEPTH-1] - avg_moisture` (only meaningful when
    `moist_hist[HIST_DEPTH-1] > avg_moisture`; guard the subtract against underflow).
  - `weed = (moist_hist[HIST_DEPTH-1] > avg_moisture)
            && (dropped > RATE_THRESH)   // 100: steeper than a normal dry-spell
            && !hot`                      // hot ⇒ it's evaporation, not a weed
  - This is the temp-compensated fusion: fast drop + NOT hot ⇒ something is stealing water.

- **(c) Anomaly (simple range check now; adaptive/AI version is Phase 8):**
  - `anomaly = (avg_moisture == 0) || (avg_moisture == 4095)`  (rail-stuck sensor).

- **(d) crop_health (8-bit fusion score, start 255, subtract, clamp ≥0):**
  penalties: dry −60, low_nutrient −50, hot −50, cold −50, weed −80, anomaly −40.

- **(e) status:**
  - `active = dry + low_nutrient + hot + cold` (count of mild conditions).
  - `status = 2 (CRITICAL)` if `weed | anomaly | cold | active>=2`
  - else `status = 1 (WARNING)` if `active == 1`
  - else `status = 0 (SAFE)`.

- **(f) event_id + event_timestamp (edge-triggered, prioritized):**
  - Remember each condition's previous value; an event fires on a 0→1 RISING edge.
  - Among edges that rise the same cycle, pick by priority (high→low):
    `SENSOR_ANOMALY(7) > WEED_DETECTED(3) > FROST_RISK(6) > HEAT_STRESS(5) >
     NUTRIENT_LOW(4) > STATUS_CRITICAL(8 = status just became 2)`.
    (`FROST_RISK` = `cold` rising; PUMP_ON/OFF events are produced later in Phase 4.)
  - `event_id = 0 (NONE)` when nothing new fired this cycle.
  - `event_timestamp` = the `timestamp` of the sample that caused the event.

- **Testbench (`analytics_engine_tb.v`):** drive smoothed values directly (no need to
  chain the whole pipeline) through the story arc: healthy → slow dry-spell (dry fires,
  NOT weed) → sharp moisture drop with normal temp (weed fires) → temp climb (heat).
  Self-check that each condition + event_id + event_timestamp is correct, and that a
  slow dry-spell does NOT false-trigger weed.
- **Done when:** all conditions, status, health, and event timestamps are correct on
  the story arc, and weed stays low during ordinary drying/heat.
- **⚠️ Tuning note:** `RATE_THRESH`/`HIST_DEPTH` must be consistent with the story-trace
  slopes (normal dry-spell gentle, weed steep). If the trace changes, retune here.

## Phase 4 — `output_analytics`   (mandatory #4)   Status: ⬜
- **Owner:** RTL lead. **Depends on:** Phase 3.
- **Goal:** clean, registered actuator/alert outputs.
- **Build (`output_analytics.v`):** register all outputs; implement **pump hysteresis**
  (`pump_on` = 1 when `dry`, stays on until `avg_moisture > 350`, then 0 — no chatter);
  map conditions to `alert_*`; pass through `status`, `crop_health`, `event_id`, `event_timestamp`.
- **Test:** verify pump doesn't oscillate; outputs stable and match decisions.
- **Done when:** actuator/alert bus is clean and correct.

## Phase 5 — egress (live stream)   (cloud-sync bonus, egress half)   Status: ⬜
- **Owner:** RTL lead. **Depends on:** Phase 4.
- **Goal:** stream results live for the dashboard — NO saved file.
- **Build:** in the top testbench, `$display` a `D` line every valid cycle and an `E`
  line whenever `event_id != 0`, EXACTLY per `INTERFACES.md` §3. (Stretch: `uart_tx.v`
  to serialize into real bytes.)
- **Test:** run `vvp simulation.vvp` and confirm well-formed `D`/`E` lines print to stdout.
- **Done when:** stdout shows correct `D`/`E` lines; ready to pipe into Python.

## Phase 6 — `edge_analytics_top` + integration   (all mandatory)   Status: ⬜
- **Owner:** RTL lead. **Depends on:** Phases 1–5.
- **Goal:** one chip, full demo.
- **Build (`edge_analytics_top.v` + `edge_analytics_tb.v`):** wire collector → 3×avg →
  analytics → output; testbench plays the full story trace and prints the stream.
- **Done when:** end-to-end sim runs, prints the live stream, every feature demonstrates.
- **Handoffs fire here:** Teammate B synthesizes the full top for reports; Teammate C
  points the dashboard at the real stream (`vvp simulation.vvp | python3 dashboard.py`).

## Phase 7 — real-time dashboard   (Teammate C, parallel from Phase 0)   Status: ⬜
- **Owner:** Teammate C. **Depends on:** the `INTERFACES.md` §3 stream format only.
- **Goal:** live dashboard + timestamped event log.
- **Build (`dashboard/dashboard.py`):** read stdin lines live; `D` → update charts
  (raw vs smoothed) + pump/status/health gauges; `E` → append to the event log with timestamp.
- **Parallel start:** build against a stub that prints fake `D`/`E` lines until Phase 6 is ready.
- **Done when:** dashboard updates live and the event log shows timestamps.

## Phase 8 — bonuses   Status: ⬜
- `adaptive_anomaly.v` (self-learning thresholds = AI bonus); extra channels
  (humidity/light); `uart_tx.v` realism; Teammate B synthesis reports; Teammate D slides.

## Phase 9 — integrate, rehearse, submit   Status: ⬜
- Full run-through, capture waveforms + a dashboard recording, finalize the deck.

---

## Timestamp thread (across phases)
`sensor_collector` **makes** it (P1) → `analytics_engine` **captures** it per event (P3)
→ `output_analytics` **exposes** `event_timestamp` (P4) → stream `E` line **carries** it
(P5) → dashboard **displays** it in the event log (P7).
