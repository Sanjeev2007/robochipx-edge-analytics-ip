# Changelog — Edge Analytics IP

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
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

### Planned
- `analytics_engine` — thresholds → status + depletion-rate anomaly (mandatory #3).
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
