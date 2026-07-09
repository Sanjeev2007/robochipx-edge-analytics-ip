# Changelog — Edge Analytics IP

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Planning — Grill-session decisions (refined the Phase-8 differentiator)
Stress-tested the differentiator plan. Decisions locked (full record: `memory.md §11`):
- **Differentiator = on-chip triage + quantified sparseness, NOT "sends a message."**
  Pitch the chip deciding *whether a human is needed* + ~85–93% fewer transmissions.
- **Two physically distinct links:** local telemetry (dashboard §3, streams everything,
  cheap) vs long-range caretaker radio (`comms_tx` §6, sparse). **The 85% edge-win applies
  ONLY to the caretaker link** — pre-empts the "but your dashboard streams every sample"
  attack. Saved as a talking point in `PRESENTATION_TASKS.md`.
- **"Unique implementation" answer = silicon framing + non-trivial RTL.** Deepened two
  blocks so the code survives inspection:
  - **Phase 8C reworked → JOINT/correlated fusion** (was: add humidity). Upgrade
    `analytics_engine` from OR-of-thresholds to interaction-aware `crop_health`. **No
    humidity channel** — it would break the frozen 17-field dashboard contract.
  - **New Phase 8F `adaptive_anomaly` (TEDA)** — self-tuning anomaly: running μ+σ² per
    channel, Chebyshev eccentricity, divider-free (cross-multiplication). Replaces the
    fixed rail-check; the researcher-impressive block. Backed by the TEDA-FPGA paper.
- **New Phase 8G — visualization artifacts** ("show the chip" like rival teams):
  gtkwave/EPWave waveforms + block diagram + **synthesized schematic** (Vivado *RTL
  Analysis → Schematic*, or local **Yosys** — added a ready command to `SYNTHESIS_TASKS.md`).
  Schematic flagged as our biggest missing, highest-impact artifact.
- **`INTERFACES.md`:** added `TEDA_SIGMA_M`/`TEDA_WARMUP` params (§7); anomaly row (§5)
  now points to the Phase-8F TEDA detector; fusion note = joint, 3 channels.
- **`FEATURES.md`:** feature 6 rewritten as self-tuning TEDA; fusion detail = joint/correlated.
- **Open thread:** real-world *acres-of-land scale* differentiation (spatial/cross-node
  anomaly, aggregation, collision-aware uplink) — next grill branch, not yet resolved.

### Docs — Research paper summaries (individual + aggregate)
- Read and summarized all 10 downloaded reference PDFs in `papers/`. New files:
  - `papers/SUMMARIES.md` — one structured summary per paper (citation, what-it-is,
    key numbers, which of our features it backs, how we go beyond / what to change),
    grouped as baseline / why-edge surveys / differentiator evidence ⭐.
  - `papers/AGGREGATE_SUMMARY.md` — cross-paper synthesis: feature→citation map,
    major-feature framing, and a prioritized **"things we need to change/add"** list.
- **Headline finding:** every surveyed system stops at software on a Pi/ESP32/gateway/cloud —
  **none does analytics in dedicated RTL/silicon** (our contribution's empty box).
- **Top actionable changes surfaced:** (1) fuse sensors *jointly* (correlation), not
  independent per-sensor thresholds; (2) adopt TEDA-style recursive eccentricity
  (mean+variance+Chebyshev, fixed-point) for the anomaly block; (3) download the Lozoya
  paper + quantify our own egress reduction; (4) implement the rogue-sensor T1/T2/T3
  fault taxonomy for `alert_anomaly`. Full list in `papers/AGGREGATE_SUMMARY.md §5`.

### Planning — Differentiator bonus tier (Phase 8) added after judge feedback
- **Evaluation feedback:** a judge called the project "too common — just automation, no
  unique factor," and pushed for a **caretaker communication system** (message a human
  what to do), not only a dashboard. See `memory.md §11` for the full context + rationale.
- **Added Phase 8 "Differentiator Bonus Tier"** to `BUILD_PLAN.md` (docs-only, no RTL yet):
  - **8A `comms_tx` ⭐** — event-triggered alert packet to the remote caretaker with a
    recommended `action_code`; rate-limited; `msg_count`. The direct answer to the judge.
  - **8B `predictor`** — divider-free moisture-slope extrapolation → `PREDICT_DRY` early
    warning (reuses the weed `dropped` primitive).
  - **8C** — strengthen the (already-existing) sensor fusion: add humidity channel or
    weighted `crop_health`.
  - **8D** — quantify the edge win: samples-processed vs packets-transmitted → % data /
    radio-on saved (ties comms + "why edge" into one number).
- **`INTERFACES.md`:** added event id 9 `PREDICT_DRY`; `predictor` + `comms_tx` port
  lists (§2); new §6 comms/alert-packet layout + `action_code` table (the two-tier
  response model); new §7 bonus params (`LEAD`, `MSG_GAP`, edge-win byte sizes), all
  flagged TUNE pending the grill session + the judge's reference papers.
- **`FEATURES.md`:** new "Beyond automation: two-tier response model" section; showcase
  rows 8 (predictive) + 9 (caretaker comms); per-feature detail + requirement-map + pitch
  updated.
- **`ROADMAP.md`:** new Tier 1.5 differentiator table (promotes predictive from stretch).
- **Not built yet:** Phase 8 RTL is deferred until the grill session runs and the judge's
  papers arrive (constants may retune). Structure is fixed; params stay `parameter`s.

### Repository & process
- **Public GitHub repo created & pushed:**
  https://github.com/Sanjeev2007/robochipx-edge-analytics-ip (branch `main`).
  `.gitignore` excludes build artifacts (`*.vvp`, `*.vcd`).
- **Task docs renamed by task, not person:** `SYNTHESIS_TASKS.md`,
  `DASHBOARD_TASKS.md`, `PRESENTATION_TASKS.md` (replaces `TEAMMATE_B_TASKS.md`).
  `WORKFLOW.md` documents the branch-per-task → PR-into-`main` flow.
- Expanded `BUILD_PLAN.md` Phase 3 with the full analytics spec and added the
  analytics params to `INTERFACES.md` §5.
- **README split:** the old `README.MD` (agent/code instructions) → `CLAUDE.md`
  (auto-loaded by Claude agents in this repo); new project `README.md` written
  (overview, architecture, quick-start, status, docs index). Doc references to
  "the README rules" now point to `CLAUDE.md`.

### Repository & process (cont.)
- **Dashboard handoff received & reviewed** (`edge_analytics/robochipx_dashboard_handoff/`):
  a working tkinter GUI. ⚠️ It uses a DIFFERENT stream contract than our `INTERFACES.md §3`
  (one 17-field CSV row, physical units 0–100, extra alert/dose/relocate columns).
  **Plan: adopt the dashboard's format** — rewrite the top testbench egress to that CSV
  with count→unit scaling and update `INTERFACES.md §3`; the dashboard stays untouched.
  See `memory.md §10` for the live status snapshot.
- **Reordered Phases 5/6 in `BUILD_PLAN.md`:** Phase 5 is now `edge_analytics_top`
  (integration + live egress stream — they're inseparable), Phase 6 is the full
  story-trace demo + handoffs. Added the critical **latency-alignment** spec (raw +3,
  avg +2 delay lines so every `D`-line field is from the same sample).
- **Split the data role out of synthesis:** new `DATA_TASKS.md` (branch `data`) owns
  the canonical demo story-trace, sensor calibration (count→real-unit), and a dashboard
  stub feed. `SYNTHESIS_TASKS.md` is now synthesis-only. `WORKFLOW.md` branch table updated.

### Fixed / setup
- **Installed `python-tk@3.14`** (Homebrew, matches Python 3.14.6) so the dashboard
  tkinter GUI can launch on the Mac; `import tkinter` verified (Tk 9.0).
- **Banner hygiene in `edge_analytics_tb.v`:** `#`-prefixed the `RESULT`/separator
  diagnostic lines so the dashboard's parser skips them. Re-verified against the real
  `edge_agri_dashboard.py` parser: 56 valid samples, 0 junk. End-to-end
  `vvp simulation.vvp | python3 …/edge_agri_dashboard.py` is ready to run on the Mac.

### Added
- **Phase 5.5 — egress reconciliation to the dashboard's 17-field CSV**
  (`edge_analytics_tb.v` ONLY — **no `.v` module changed**): replaced the two-line
  `D`/`E` stream with the dashboard teammate's contract
  (`robochipx_dashboard_handoff/VERILOG_DASHBOARD_CONTRACT.md`) so their finished
  tkinter UI works unchanged.
  - Header printed ONCE, then one 17-field row per `out_valid` cycle in the exact
    order: `timestamp, moisture_raw, nutrient_raw, temp_raw, moisture_avg,
    nutrient_avg, temp_avg, pump_on, dose_nutrient, alert_nutrient, alert_weed,
    alert_heat, alert_frost, alert_anomaly, status, crop_health, relocate_recommend`.
  - **Count → display-unit scaling** (in the testbench, RTL untouched):
    moisture/nutrient = `count/5` clamped 0–100; temp = `count/10`; crop_health =
    `health*100/255` (wide `integer` multiply → no truncation); status stays numeric
    0/1/2; pump/dose/alert_* pass through; `relocate_recommend = status==2 &&
    scaled_health<35`. `$fflush` after each row so the stream pipes live.
  - The Phase-5 latency-alignment self-check is **kept but silent** (prints only on a
    mismatch), and the pump-ON alignment proof narrative was made silent too, so the
    stdout stream is clean 17-field CSV the dashboard can ingest directly.
  - Updated `INTERFACES.md §3` to own the 17-field CSV contract (field glossary +
    scaling formulas + note that raw counts are scaled to display units, RTL unchanged).
- **Phase 5 — `edge_analytics_top.v`** (integration + live-stream egress): the
  top level that chains the four EXISTING blocks
  `sensor_collector → smoothing_stage → analytics_engine → output_analytics`.
  **Pure wiring + alignment — no sub-module was modified.**
  - **⚠️ LATENCY ALIGNMENT (the whole point of this phase) solved with plain
    shift-register delay lines** exactly per `BUILD_PLAN.md` Phase 5. Each `D`-line
    field is born at a different stage (raw+ts at `sensor_collector`, avg at
    `smoothing_stage`, decisions at `output_analytics`), so they are re-aligned to
    the final `output_analytics` cycle: **raw m/n/t and timestamp delayed +3, avg
    m/n/t delayed +2, decisions +0.** The same lines are tapped at **+1 (avg_moisture)
    and +2 (timestamp)** to feed `output_analytics`'s own inputs on ITS input cycle
    (per `INTERFACES.md` §2 output_analytics inputs). Plain (not valid-gated) shift
    registers are correct because every stage's valid strobe is itself a plain
    1-clock delay, so data and valid stay locked together even across sensor gaps.
  - Exposes one aligned output bundle under a single `out_valid`: all `D`-line
    fields (timestamp, raw m/n/t, avg m/n/t, pump, status, health) plus the alert
    bus and `event_id`/`event_timestamp`. Synthesizable, `clk`/`rst`-driven, fully
    commented.
- `edge_analytics_tb.v` — top-level testbench that plays a 56-sample story trace
  (healthy&wet → gentle dry-spell → irrigation recovery → nutrient low → heat) one
  sample per cycle, and on **every** valid cycle `$display`s the live stream lines
  EXACTLY per `INTERFACES.md` §3: a `D,<ts>,<m>,<n>,<t>,<avgM>,<avgN>,<avgT>,<pump>,
  <status>,<health>` line, plus an `E,<ts>,<EVENT_NAME>` line whenever `event_id!=0`
  (names from `INTERFACES.md` §4). Ready to pipe: `vvp simulation.vvp | python3
  dashboard.py`.
  - **Alignment proof (rigorous):** a tiny in-testbench reference model recomputes,
    per timestamp, the raw value fed and the expected 8-sample moving average, and
    self-checks EVERY `D` line — raw (+3), avg (+2) and decision (+0) all resolve to
    the SAME original sample. A highlighted banner spotlights the PUMP_ON sample.
  - Trace is arranged so `ts` == feed index (reset released so the first valid
    sample is captured while the free-running counter is 0), letting the reference
    arrays be indexed directly by the `timestamp` printed on each line. Dumps `dump.vcd`.
- **Phase 4 — `output_analytics.v`** (mandatory feature #4): the clean, registered
  actuator/alert bus that turns the analytics_engine decisions into the signals the
  outside world acts on. Interface per `INTERFACES.md` §2 (with the two Phase 4 input
  additions noted below).
  - **Pump hysteresis (the headline requirement):** `pump_on` turns ON when `dry`
    (avg_moisture < 200), then STAYS ON through the 200–350 band — even as the soil
    recovers past the dry threshold — until `avg_moisture > PUMP_OFF_THRESH` (350),
    then OFF. The 200→350 gap is the hysteresis band that kills pump chatter. Once
    off, it does not re-trigger until the soil is genuinely dry again.
  - **PUMP_ON(1) / PUMP_OFF(2) events generated here** (the engine deliberately
    leaves ids 1/2 for this stage). event_id merge rule: a real engine event
    (anomaly/weed/frost/heat/nutrient/critical) WINS; when the engine reports NONE,
    the pump's own toggle surfaces as PUMP_ON/PUMP_OFF, stamped with the current
    `timestamp`. Idle cycles HOLD the last real event's timestamp.
  - **Alert bus + doser:** registered mirrors `alert_weed←weed`, `alert_heat←hot`,
    `alert_frost←cold`, `alert_nutrient←low_nutrient`, `alert_anomaly←anomaly`, and
    `dose_nutrient←low_nutrient`. `status`, `crop_health`, `event_id`,
    `event_timestamp` passed through.
  - **All outputs registered** (1-cycle latency); `out_valid = in_valid` delayed one
    cycle. Synthesizable, `clk`/`rst`-driven, fully commented; VCD dump.
  - **⚠️ Interface refinement (`INTERFACES.md` §2):** `output_analytics` takes two
    inputs beyond the analytics_engine outputs — `avg_moisture` (to test the
    `> PUMP_OFF_THRESH` turn-off) and `timestamp` (to stamp generated pump events).
    Both are the corresponding engine INPUTS carried alongside; the top level delays
    them to stay aligned with the registered decisions. §2 table updated.
- `output_analytics_tb.v` — drives the engine decisions directly through a story that
  exercises every requirement, with 8 self-check groups (0 errors): dry→PUMP_ON
  (ev_ts=100); soil recovering into the 200–350 band holds the pump ON (**no
  chatter**); crossing 350 → PUMP_OFF (ev_ts=130); a below-350-but-not-dry dip keeps
  it OFF (no re-trigger); a second dry spell **re-arms** the pump (PUMP_ON ev_ts=150);
  an engine WEED event landing the same cycle the pump turns off proves the engine
  event **wins** `event_id` while the pump still actuates; full `alert_*`/`dose_nutrient`
  mapping (heat/frost/nutrient/anomaly); and `out_valid` dropping with `in_valid`.
  Dumps `dump.vcd`.
- **Phase 3 — `analytics_engine.v`** (mandatory feature #3 + anomaly / sensor-fusion
  bonuses): the "brain" that turns the smoothed set into decisions. Interface exactly
  per `INTERFACES.md` §2 `analytics_engine`; all thresholds are named params from §5.
  - **(a) Threshold conditions** (combinational): `dry` (avg_moisture < 200),
    `low_nutrient` (avg_nutrient < 250), `hot` (avg_temp > 400), `cold` (avg_temp < 100).
  - **(b) Temperature-compensated WEED detector** — the standout logic. Keeps a
    `HIST_DEPTH=4` moisture shift register; `weed = (moist_hist[3] > avg_moisture)
    && (dropped > RATE_THRESH=100) && !hot`. Underflow-guarded subtract. A fast
    moisture drop that is NOT hot ⇒ something is stealing water (weed); a fast drop
    while hot ⇒ evaporation ⇒ suppressed (sensor fusion). A slow dry-spell (gentle
    slope) never trips it.
  - **(c) Anomaly**: rail-stuck check `avg_moisture == 0 || == 4095`.
  - **(d) crop_health**: 8-bit fusion, start 255, subtract penalties (dry −60,
    low_nutrient −50, hot −50, cold −50, weed −80, anomaly −40), clamp ≥0.
  - **(e) status**: CRITICAL(2) if `weed|anomaly|cold|(active≥2)`, else WARNING(1)
    if exactly one mild condition, else SAFE(0).
  - **(f) event_id + event_timestamp**: edge-triggered (0→1 rising), prioritized
    ANOMALY(7) > WEED(3) > FROST(6) > HEAT(5) > NUTRIENT_LOW(4) > STATUS_CRITICAL(8);
    event stamps the `timestamp` of the sample that caused it. Event ids match
    `INTERFACES.md` §4.
  - **All outputs registered** (1-cycle latency); `out_valid = in_valid` delayed one
    cycle. Synthesizable, `clk`/`rst`-driven, fully commented; VCD dump.
- `analytics_engine_tb.v` — drives the smoothed values directly (no full-pipeline
  chain needed) through the **story arc**: healthy → slow dry-spell → weed (sharp
  drop, normal temp) → heat. Uses timestamp ranges to classify phases and 8
  self-checks: healthy stays quiet; `dry` fires in the dry-spell while **`weed` does
  NOT** (the key false-trigger guard); `weed` + a WEED_DETECTED(3) event fire on the
  sharp normal-temp drop; `hot` + a HEAT_STRESS(5) event fire in the heat phase; and
  an **identical sharp drop while hot does NOT trigger `weed`** (proves temperature
  compensation). Also checks `event_timestamp` matches the causing sample. Dumps
  `dump.vcd`.
- **Phase 2 — `smoothing_stage.v`** (mandatory feature #2, wiring): instantiates the
  EXISTING `moving_avg.v` **three times** — one per channel (moisture/nutrient/temp),
  params `DATA_WIDTH=12`, `LOG2_N=3` (8-sample window) — fed by `sensor_collector`'s
  aligned outputs. Produces `avg_moisture`, `avg_nutrient`, `avg_temp` + one shared
  `avg_valid`. `moving_avg` itself was NOT modified (pure reuse/wiring).
  - **⚠️ Alignment fix implemented:** `moving_avg` registers its output, so the
    smoothed value lands one cycle after the raw input. A single `timestamp` delay
    register (`timestamp_out <= timestamp_in`) re-aligns the "when" so it exits on
    the same cycle as the smoothed set and `avg_valid`. All 3 channels share timing,
    so one `avg_valid` represents the set.
  - Synthesizable, `clk`/`rst`-driven, fully commented; VCD dump.
- `smoothing_stage_tb.v` — testbench wiring the realistic mini-pipeline
  `testbench → sensor_collector → smoothing_stage`. Feeds 24 deliberately noisy sets
  (moisture drifting down, nutrient steady, temp creeping up) and self-checks: (1)
  **noise removal** — steady nutrient RAW swing = 33 counts vs SMOOTHED swing = 4;
  (2) **timestamp alignment** — on every `avg_valid` cycle, `timestamp_out` matches
  the timestamp of the raw sample that produced that average. Includes a deliberate
  one-cycle sensor gap (ts 13 skipped) proving `avg_valid` drops while the timestamp
  stays aligned. Dumps `dump.vcd`.
- **Phase 1 — `sensor_collector.v`** (mandatory feature #1): the 3-channel sensor
  front-end. A free-running 32-bit timestamp counter ticks every clock; on
  `sensors_valid` it latches all 3 raw channels (moisture/nutrient/temp) together
  and tags them with the current timestamp, emitting them aligned via
  `sample_valid`. Parallel interface exactly per `INTERFACES.md` §2. Synthesizable,
  `clk`/`rst`-driven, fully commented.
- `sensor_collector_tb.v` — testbench: fakes the 3 field sensors with changing
  readings; self-checks that each 3-channel set appears aligned on the outputs and
  that timestamps are strictly increasing. Deliberately drops `sensors_valid` for
  one cycle to prove the counter keeps ticking while `sample_valid` goes low. Dumps
  `dump.vcd` for gtkwave.
- `docs/BUILD_PLAN.md` — phase-by-phase build plan (Phases 1–9), structured for
  **multi-agent handoff**: onboarding read-order + per-phase goal/build/test/done.
- `docs/memory.md` — added a "NEW AGENT? ONBOARD HERE" section (doc read-order) so a
  fresh agent can run any phase cold.

### Changed
- **Reconciled `sensor_collector` to a PARALLEL interface** (outputs moisture/nutrient/
  temp side-by-side + shared timestamp), replacing the earlier muxed `channel_id`/
  `sample` design — keeps the pipeline aligned and consistent with the `D` stream line.

### Decided
- **Dashboard is REAL-TIME via a live stream, not a saved CSV.** The sim `$display`s
  result lines to stdout; piped into Python (`vvp simulation.vvp | python3
  dashboard.py`). Two line types: `D` (continuous data) and `E,<timestamp>,<event>`
  (discrete events → timestamped event log).
- Corrected a doc contradiction: the **cloud-sync bonus = on-chip UART egress + local
  real-time dashboard** (only the cloud *service* is out of scope; the egress
  interface is in scope).
- Added `docs/INTERFACES.md` — the Phase 0 interface contract (constants, module
  boundary signals, live-stream format, event ids, thresholds) for the whole team.
- Reorganized: all documentation moved under `edge_analytics/docs/`.

- **Application locked in: Smart Agriculture — Precision Crop Monitor.** Channels:
  soil moisture, nutrient (NPK), temperature. Closed-loop auto-irrigation
  (`pump_on`) plus nutrient/weed alerts. Weed detection via resource-depletion
  anomaly (no camera / no computer vision). Supersedes the earlier
  machine-health-monitor concept.

### Verified
- **Phase 5.5 CSV egress** — recompiled the full chip and ran the story trace
  (`iverilog -o simulation.vvp edge_analytics_top.v output_analytics.v
  analytics_engine.v smoothing_stage.v moving_avg.v sensor_collector.v
  edge_analytics_tb.v && vvp simulation.vvp`). **RESULT: PASS (0 errors)** — the
  alignment self-check still passes after the testbench-only egress change.
  - Output = one header line + **56 rows, every row exactly 17 comma-separated
    fields**; moisture/nutrient/crop_health all within 0–100, temp within 0–50,
    status ∈ {0,1,2}. Range scan found no out-of-range values.
  - Story samples read correctly in display units: ts=24 dry-spell
    (`moisture_avg=39`, `pump_on=1`, status WARNING); ts=28 recovery
    (`moisture_avg=86`, `pump_on=0`, status SAFE, health 100); ts=38 nutrient-low
    (`dose_nutrient=1`, `alert_nutrient=1`); ts=50 heat (`temp_avg=42`,
    `alert_heat=1`). Warm-up ts=0 shows the expected transient CRITICAL.
  - **Dashboard parser sanity-check:** ran the dashboard's own `parse_sample()` on
    the header + several rows — the header is skipped (returns `None`) and every row
    parsed into a `Sample` with `status` mapped to SAFE/WARNING/CRITICAL. The
    dashboard ingests our stream unchanged.
- Compiled and simulated the FULL integrated chip successfully
  (`iverilog -o simulation.vvp edge_analytics_top.v output_analytics.v
  analytics_engine.v smoothing_stage.v moving_avg.v sensor_collector.v
  edge_analytics_tb.v && vvp simulation.vvp`). **RESULT: PASS (0 errors)** — every
  one of the 56 `D` lines passed the reference-model alignment self-check.
  - **Alignment proof, one known sample (`ts=24`):** the D line was
    `D,24,133,300,250,196,300,250,1,1,195`. Raw moisture **133** (exactly what was
    fed at ts=24, delayed +3), its 8-sample average **196** (= (259+241+223+205+187+
    169+151+133)>>3, delayed +2), and the resulting decision **pump_on=1** (196<200 ⇒
    dry ⇒ pump, +0) ALL appear on that SAME line — proving the delay lines re-aligned
    raw, avg and decision to one original sample.
  - **Story events fired correctly** with aligned timestamps: `PUMP_OFF` at ts=7
    (warm-up settles wet, pump off), `PUMP_ON` at ts=24 (soil dried below 200),
    `PUMP_OFF` at ts=28 (irrigation recovered the soil past 350), `NUTRIENT_LOW` at
    ts=38 (avg_nutrient < 250), `HEAT_STRESS` at ts=50 (avg_temp > 400). The gentle
    dry-spell did NOT false-trigger `weed`.
  - **Note (honest):** ts=0–6 show a moving-average WARM-UP RAMP (each filter's
    8-sample buffer starts at 0, so averages climb from 0 over the first ~8 samples).
    This produces a transient `FROST_RISK`/`CRITICAL` at ts=0 and a warm-up pump
    on→off before the window fills. It is inherent to `moving_avg` (not a wiring
    issue); the healthy baseline is kept wet (400) so the pump settles cleanly OFF by
    ts=7 and the FIRST genuine `PUMP_ON` is the real dry-spell at ts=24.
- Compiled and simulated `output_analytics` successfully
  (`iverilog -o simulation.vvp output_analytics.v output_analytics_tb.v && vvp
  simulation.vvp`). **RESULT: PASS (0 errors).** The trace confirmed pump hysteresis
  end-to-end: `pump_on` fired at avgM=180 (PUMP_ON, ev_ts=100), HELD ON across
  avgM=260 and 340 (in the 200–350 band, no chatter), turned OFF at avgM=360
  (PUMP_OFF, ev_ts=130), stayed OFF at avgM=210 (not dry), and RE-ARMED at avgM=190
  (PUMP_ON, ev_ts=150). Event priority verified: a WEED engine event on the same
  cycle the pump turned off surfaced as `event_id=3` (engine wins) while `pump_on`
  still went to 0. All `alert_*` lines + `dose_nutrient` mapped correctly, and
  `out_valid` dropped with `in_valid`.
- Compiled and simulated `analytics_engine` successfully
  (`iverilog -o simulation.vvp analytics_engine.v analytics_engine_tb.v && vvp
  simulation.vvp`). All 8 story-arc self-checks reported **PASS** (0 errors):
  healthy phase quiet (status SAFE, health 255); `dry` fired at avgM=192 during the
  slow dry-spell while `weed` stayed low; `weed` + WEED_DETECTED(3) fired at ts=2600
  on the sharp normal-temp drop (event_timestamp=2600); `hot` + HEAT_STRESS(5) fired
  in the heat phase; and an identical sharp drop **while hot did NOT trigger `weed`**,
  proving the temperature compensation. STATUS_CRITICAL(8) correctly fired at ts=3700
  when dry+hot pushed `active≥2`.

### Planned
- Phase 6 — full demo on the VERIFIED canonical story-trace (from the data role):
  swap the short trace for the real one, capture waveforms + the full stream, and
  fire the synthesis/dashboard handoffs.
- (Optional) prime/warm the moving-average window before streaming, or gate output
  until the filter is full, to suppress the ts=0–6 warm-up ramp for a cleaner demo.
- Install `gtkwave` for visual waveform inspection.

## [0.1.0] - 2026-07-09

### Added
- Installed Icarus Verilog toolchain (`iverilog`, `vvp`) via Homebrew.
- `PROBLEM_STATEMENT.md` — standalone copy of official problem #5 (Edge Analytics IP).
- `memory.md` — project memory: goal, constraints, architecture, decisions.
- `moving_avg.v` — sliding-window Moving Average Filter (mandatory feature #2).
  Uses a running accumulator + right-shift divide; window size configurable via
  the `LOG2_N` parameter. Fully synthesizable, `clk`/`rst`-driven, commented.
- `moving_avg_tb.v` — testbench: fake sensor streams a noisy baseline + a spike;
  dumps `dump.vcd` for gtkwave.

### Verified
- Compiled and simulated `sensor_collector` successfully
  (`iverilog -o simulation.vvp sensor_collector.v sensor_collector_tb.v && vvp
  simulation.vvp`). All 6 fake sensor sets passed through aligned; timestamps
  increased strictly (`ts` skipped 3→5 across the deliberate valid-drop cycle,
  confirming the counter free-runs while `sample_valid` correctly drops).
  Self-check reported **PASS** (0 errors).
- Compiled and simulated `moving_avg` successfully. Confirmed correct behavior:
  smooths steady jitter to a stable value, and dilutes a 900 spike to 200 over an
  8-sample window before recovering to baseline.

### Decided
- Deliverable is **simulation + test results only** — no physical hardware required.
- (Initial app idea was a machine health monitor; later changed to Smart
  Agriculture — see [Unreleased].)
