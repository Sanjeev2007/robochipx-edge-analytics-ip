# Changelog — Edge Analytics IP

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

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

### Added
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
- `output_analytics` — registered outputs: `pump_on`, `alert_nutrient`, `alert_weed`, status (mandatory #4).
- `edge_analytics_top` — top-level integration of all blocks.
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
