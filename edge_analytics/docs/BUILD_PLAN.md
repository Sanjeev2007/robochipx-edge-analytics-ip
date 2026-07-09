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
- Follow the `CLAUDE.md` code rules (synthesizable, commented, `clk`/`rst`, one small
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

## Phase 3 — `analytics_engine`   (mandatory #3 + bonuses)   Status: ✅ built + simulated
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

## Phase 4 — `output_analytics`   (mandatory #4)   Status: ✅ built + simulated
- **Owner:** RTL lead. **Depends on:** Phase 3.
- **Goal:** clean, registered actuator/alert outputs.
- **Build (`output_analytics.v`):** register all outputs; implement **pump hysteresis**
  (`pump_on` = 1 when `dry`, stays on until `avg_moisture > 350`, then 0 — no chatter);
  map conditions to `alert_*`; pass through `status`, `crop_health`, `event_id`, `event_timestamp`.
- **Test:** verify pump doesn't oscillate; outputs stable and match decisions.
- **Done when:** actuator/alert bus is clean and correct.

## Phase 5 — `edge_analytics_top` (integration + live egress)   (mandatory + cloud-sync egress)   Status: ✅ built + simulated
- **Owner:** RTL lead. **Depends on:** Phases 1–4.
- **Goal:** wire the whole chip together AND emit the live `D`/`E` stream. (The stream
  can't exist without the integrated, aligned pipeline — so integration + egress are
  one phase.)
- **Build (`edge_analytics_top.v`):** instantiate and chain the four blocks:
  `sensor_collector → smoothing_stage → analytics_engine → output_analytics`.
  Do NOT modify the sub-modules — pure wiring + alignment. Expose an aligned output
  bundle (all `D`-line fields + event) under one `out_valid`.
- **⚠️ LATENCY ALIGNMENT (the big gotcha — must handle in the top):** each `D`-line
  field is born at a different pipeline stage, so they must be re-aligned before printing:
  | field | born after | delay needed to reach the output_analytics stage |
  |---|---|---|
  | raw `moisture/nutrient/temp` | sensor_collector | **+3 cycles** |
  | `avg_moisture/nutrient/temp` | smoothing_stage | **+2 cycles** |
  | sample `timestamp` | sensor_collector | **+3 cycles** |
  | `pump/status/health/event_*` | output_analytics | 0 (already at this stage) |
  Add plain shift-register delay lines in the top (raw & timestamp ×3, avg ×2) so every
  field on a given output cycle belongs to the SAME original sample. Also delay the
  `avg_moisture`/`timestamp` that `output_analytics` itself needs (+1/+2) to line up with
  its `in_valid` — verify against the Phase 4 interface (§2 output_analytics inputs).
- **Build (`edge_analytics_tb.v`):** feed a short trace through the top; `$display` a `D`
  line every `out_valid` cycle and an `E` line whenever `event_id != 0`, EXACTLY per
  `INTERFACES.md` §3. (Stretch: `uart_tx.v` to serialize into real bytes.)
- **Test:** confirm that for one known sample, its raw + avg + decision all appear on the
  SAME `D` line (alignment proof), and `D`/`E` lines are well-formed and pipeable.
- **Done when:** `vvp simulation.vvp` prints a correct, aligned `D`/`E` stream ready to
  pipe into Python.

## Phase 5.5 — Egress reconciliation to the dashboard's CSV format   Status: ✅ done + simulated
- **Owner:** RTL lead. **Depends on:** Phase 5.
- **Why:** the dashboard teammate built to a different contract (see `memory.md §10`).
  We adopt THEIR format so their finished UI works unchanged. **Testbench-only change —
  do NOT modify any `.v` module.** Their contract:
  `edge_analytics/robochipx_dashboard_handoff/VERILOG_DASHBOARD_CONTRACT.md`.
- **Change `edge_analytics_tb.v`:** replace the `D`/`E` `$display` with the dashboard's
  **17-field CSV**. Print the header ONCE, then one row per `out_valid` cycle:
  ```
  timestamp,moisture_raw,nutrient_raw,temp_raw,moisture_avg,nutrient_avg,temp_avg,pump_on,dose_nutrient,alert_nutrient,alert_weed,alert_heat,alert_frost,alert_anomaly,status,crop_health,relocate_recommend
  ```
  from the top's aligned bundle, **with scaling** (raw counts → display units). Use an
  `integer`/wide temp for the multiplies to avoid truncation; `$fflush` after each row.
- **Scaling (tunable defaults — data person's calibration can refine later):**
  - `moisture_raw/avg`  = count / 5      (clamp 0–100)   → dry@200 ≈ 40%, pump-off@350 ≈ 70%
  - `nutrient_raw/avg`  = count / 5      (clamp 0–100)
  - `temp_raw/avg`      = count / 10                      → hot@400 ≈ 40°C, cold@100 ≈ 10°C
  - `crop_health`       = health * 100 / 255             (0–255 → 0–100)
  - `status`            = leave numeric 0/1/2 (dashboard maps to SAFE/WARNING/CRITICAL)
  - `pump_on, dose_nutrient, alert_*` = pass through 0/1 from the bundle
  - `relocate_recommend` = 1 when `status==2 && scaled_health < 35`, else 0
- **Update `INTERFACES.md §3`** to this 17-field CSV format (the dashboard now owns the
  egress contract); keep a short note that raw counts are scaled to display units.
- **Verify:** `vvp simulation.vvp | head -5` → a header line then rows of exactly 17
  comma-separated fields; moisture/nutrient/health in 0–100, temp ~0–50, status in {0,1,2}.
  Bonus: sanity-check the dashboard's `parse_sample()` accepts a row.
- **Done when:** the sim emits valid 17-field CSV the dashboard parser ingests. (Live
  integration `vvp simulation.vvp | python3 edge_agri_dashboard.py` happens at Phase 6.)

## Phase 6 — full demo + handoffs   (all mandatory, integrated)   Status: ⬜
- **Owner:** RTL lead. **Depends on:** Phase 5 + the VERIFIED canonical story-trace
  (from the data role, validated by the lead against the real RTL).
- **Goal:** the end-to-end demo on the real story data.
- **Build:** swap the short trace for the canonical story-trace; run end-to-end and
  confirm every feature demonstrates with correct events/timestamps (healthy → dry→pump
  → recovery → weed → heat → nutrient-low). Capture waveforms + the full stream.
- **Done when:** the full narrative runs and every mandatory + bonus feature is visible.
- **⚠️ DASHBOARD INTEGRATION (do not forget):** on the Mac, get the dashboard owner's
  `dashboard.py`, `pip install` its deps, then swap the stub for the real sim — no
  dashboard code change (same `INTERFACES.md §3` format):
  `vvp simulation.vvp | python3 dashboard.py`. (See memory.md §8 checkpoint.)
- **Handoffs fire here:** synthesis owner synthesizes the full top for reports; dashboard
  owner hands over `dashboard.py` for the live integration above.

## Phase 7 — real-time dashboard   (Teammate C, parallel from Phase 0)   Status: ⬜
- **Owner:** Teammate C. **Depends on:** the `INTERFACES.md` §3 stream format only.
- **Goal:** live dashboard + timestamped event log.
- **Build (`dashboard/dashboard.py`):** read stdin lines live; `D` → update charts
  (raw vs smoothed) + pump/status/health gauges; `E` → append to the event log with timestamp.
- **Parallel start:** build against a stub that prints fake `D`/`E` lines until Phase 6 is ready.
- **Done when:** dashboard updates live and the event log shows timestamps.

## Phase 8 — DIFFERENTIATOR BONUS TIER (the "beyond automation" answer)   Status: ⬜
> **Why this tier exists (evaluation feedback):** a judge said the project reads as
> "just automation — nothing unique," and pushed hard on adding a **communication
> system to a human caretaker** (not only a dashboard). This tier is the direct answer.
> The unifying idea: the chip has **TWO output tiers** — Tier 1 = *local actuation*
> (pump/doser, machine-to-machine, routine); Tier 2 = a **sparse, event-triggered
> comms channel** to the remote caretaker (machine-to-human, exceptions only). Tier 2
> is BOTH the caretaker-alert the judge wanted AND the reason edge analytics saves
> power/bandwidth (transmit K alerts, not N raw samples). Build 8A + 8B first (the two
> real new modules); 8C/8D are strengthen-and-measure and are near-free.
>
> ⚠️ **Design still settling:** thresholds, packet layout, and the predictor margin are
> flagged "TUNE" below. They may change after (a) the planned grill session and (b) the
> judge's research papers land. Build the structure; leave the constants as named params.

### Phase 8A — `comms_tx` (event-triggered caretaker communication)  ⭐ FLAGSHIP   Status: ⬜
- **Owner:** RTL lead. **Depends on:** Phase 4 (`output_analytics` events). **Interface:** `INTERFACES.md` §6.
- **Goal:** the REMOTE notification channel — distinct from the continuous dashboard
  telemetry (§3). On an event edge it latches a **compact alert packet** and "transmits"
  it (to a LoRa/GSM gateway → caretaker's phone). It fires ONLY when a human is actually
  needed, and rate-limits repeats — this sparseness IS the edge power/bandwidth win.
- **Build (`comms_tx.v`):**
  - Inputs: `clk`, `rst`, `in_valid`, `event_id[3:0]`, `event_timestamp[31:0]`,
    `status[1:0]`, `crop_health[7:0]` (from `output_analytics`).
  - Map each `event_id` → **{notify_caretaker?, severity, action_code}**. Automation
    handles some events locally (PUMP_ON/OFF → no message); human-needed events
    (WEED_DETECTED, SENSOR_ANOMALY, NUTRIENT_LOW if no doser, STATUS_CRITICAL, FROST_RISK)
    → build a packet. `action_code` = recommended caretaker action (INSPECT_WEED,
    CHECK_SENSOR, MANUAL_FERTILIZE, RELOCATE/PROTECT, REFILL_TANK). See `INTERFACES.md` §6.
  - On a qualifying event: assert `msg_valid` for one cycle with a parallel
    `alert_packet` bus = {severity, event_code, action_code, event_timestamp, crop_health}.
  - **Rate-limit (TUNE `MSG_GAP`):** a down-counter blocks a repeat of the SAME event
    until `MSG_GAP` valid cycles pass — no alert spam.
  - Keep a `msg_count[15:0]` (transmitted-packet tally) for the Phase 8D edge-win math.
  - **Stretch realism:** serialize `alert_packet` to bytes with a tiny UART TX FSM
    (`uart_tx.v`, `tx_byte`/`tx_strobe`) so it "goes on a real wire." Keep the parallel
    bus as the primary; UART is optional polish.
- **Testbench (`comms_tx_tb.v`):** drive a sequence of `event_id`s including two
  human-needed events, one machine-handled event (expect NO packet), and a rapid repeat
  (expect rate-limit to suppress it). Self-check: `msg_valid` fires only for
  human-needed events, `action_code`/`severity` correct, `msg_count` matches.
- **Done when:** the sim prints an alert-packet line for exactly the human-needed events
  (not the machine-handled ones), rate-limiting works, and `msg_count` is correct.

### Phase 8B — `predictor` (predictive watering — act *before* the crop stresses)   Status: ⬜
- **Owner:** RTL lead. **Depends on:** Phase 3 (smoothed moisture + depletion primitive).
- **Goal:** move from *reactive* (`avg_moisture < DRY_THRESH`) to *predictive* — estimate
  the moisture trend and raise `predict_dry` (event `PREDICT_DRY`) BEFORE the soil is dry,
  so the pump/caretaker gets a lead-time warning.
- **Reuse:** `analytics_engine` already computes `dropped` = moisture fall over `HIST_DEPTH`
  valid samples (the weed primitive). The predictor reuses that slope — no new history.
- **Build (`predictor.v`) — NO DIVIDER (beginner + synthesis friendly):**
  - Extrapolate `LEAD` samples ahead with a shift-multiply, not a divide:
    `projected = avg_moisture - (dropped * LEAD >> LOG2_HIST)` (guard underflow → 0).
    (`dropped>>LOG2_HIST` ≈ per-sample slope; ×`LEAD` projects ahead.)
  - `predict_dry = (avg_moisture >= DRY_THRESH) && (projected < DRY_THRESH)` — i.e. NOT
    dry yet but heading below within `LEAD` samples. Register the output (1-cycle).
  - Fire event `PREDICT_DRY` (new id, `INTERFACES.md` §4) on the 0→1 edge of `predict_dry`.
  - Optional: expose `cycles_to_dry_est` for the dashboard (still divider-free — a small
    LUT or leave it out for v1). **TUNE `LEAD`.**
- **Testbench (`predictor_tb.v`):** feed a gentle decline that will cross `DRY_THRESH`;
  confirm `predict_dry` + `PREDICT_DRY` fire a few samples EARLY, and do NOT fire on a
  flat/rising trace or an already-dry trace.
- **Done when:** the early-warning fires ahead of the actual dry threshold on a declining
  trace, and stays quiet otherwise.

### Phase 8C — JOINT / CORRELATED fusion (make the RTL non-trivial)   Status: ⬜
- **Owner:** RTL lead. **Depends on:** Phase 3.  **Decision (grill):** the unique-
  implementation claim ("analytics in silicon, not software") only survives if the RTL
  is more than independent comparators. So upgrade fusion from **OR-of-thresholds** to a
  **correlated judgment** — the chip reasons about *combinations*, not each sensor alone.
- **⚠️ Do NOT add a humidity channel.** That would push `NUM_CH` 3→4 and break the FROZEN
  17-field dashboard contract (`INTERFACES.md §3`). Keep 3 channels; make the *fusion
  logic* smarter, not wider.
- **Build (extend `analytics_engine.v` fusion):**
  - Generalize the temp-compensated weed idea to the WHOLE verdict: decisions depend on
    channel *combinations*, e.g. `real_heat_stress = hot && (avg_moisture falling)`;
    `real_dry = dry && !(recent pump recovery)`; `nutrient_crisis = low_nutrient && low
    crop_health`. Correlated conditions, not 3 lone thresholds.
  - Make `crop_health` an explicit **weighted, interaction-aware score** (named weights in
    `INTERFACES.md §5`) rather than fixed independent penalties — so combined stress
    (e.g. dry AND hot together) costs MORE than the sum of the two alone.
- **Testbench:** prove it's genuine fusion — a case where each channel alone looks "fine"
  but their *combination* is a problem (only a joint detector catches it), and the
  temp-compensated weed case (fast drop + normal temp) still holds.
- **Done when:** a combination-only stress is detected that independent thresholds miss,
  and single-channel behaviour is unchanged.

### Phase 8F — `adaptive_anomaly` (TEDA self-tuning anomaly detector)  ⭐ Status: ⬜
- **Owner:** RTL lead. **Depends on:** Phase 3.  **Interface:** `INTERFACES.md` §7.
  **Backed by:** `papers/` TEDA-FPGA (138 ns, 7.2 MSPS, <7% LUTs) — cite the numbers.
- **Goal:** replace the fixed rail-stuck `if (avg==0||avg==4095)` with a block that
  **learns each sensor's own normal and flags statistical outliers** — parameter-free,
  self-calibrating. This is the "AI at the edge" bonus made real and the most
  researcher-impressive block; a judge can point at it and say "that's a real algorithm."
- **Build (`adaptive_anomaly.v`) — TEDA reduced to a divider-free datapath:**
  The TEDA eccentricity outlier test algebraically reduces to a clean Chebyshev form:
  **anomaly ⇔ `(x − μ)² > m²·V`** (m = `TEDA_SIGMA_M`, V = variance). NO division in the test.
  Per channel keep two state registers **μ (mean)** and **V (variance)**, updated every
  valid sample by an **exponential moving average (shift, not divide)** — this is the
  hardware-friendly recursive form AND it tracks slow drift:
  ```
  diff  = x - μ                    // subtractor
  μ'    = μ + (diff >>> α)         // EMA mean update  (α = TEDA_ALPHA, arithmetic shift)
  sq    = diff * diff              // THE one multiplier: (x-μ)²
  V'    = V + ((sq - V) >>> α)     // EMA variance update
  bound = m²·V                     // m=3 → 9·V = (V<<3)+V  (shift+add, no multiplier)
  anomaly = (sq > bound)           // comparator ; use pre-update μ,V for the test
  ```
  - Cost per channel: **1 multiplier** (diff²) + ~3 add/sub + fixed shifts (free wiring) +
    1 comparator + μ/V registers + warm-up counter. Time-share the multiplier across the
    3 channels if area-tight. Use a wide reg for `sq`/`bound` to avoid overflow. Fixed-point.
  - Output `anomaly` (+ optional per-channel `anom_ch`) into `analytics_engine`; keep the
    fixed **rail-stuck** check (`x==0||x==4095`) OR'd in as a fast path for a dead sensor.
  - **Warm-up guard:** suppress flags until `n >= TEDA_WARMUP` samples (μ/V not trustworthy yet).
  - **This block is drawable as a schematic** (feedback registers + multiplier + comparator)
    → use it for the Phase-8G "show the chip" datapath visual (VLSI credibility).
- **Testbench (`adaptive_anomaly_tb.v`):** feed a channel that sits at ~600±20 then
  spikes to 660 (NOT a rail) → confirm TEDA flags it while a fixed rail-check would miss
  it. Confirm no false flags during warm-up or on normal jitter.
- **Done when:** the self-tuning detector catches an off-baseline outlier a fixed
  threshold misses, with no false alarms on normal noise. (**Fallback:** if time slips,
  this is the one to defer — frame it via the TEDA-FPGA paper and build if able.)

### Phase 8D — quantify the edge win (the number that wins the argument)   Status: ⬜
- **Owner:** RTL lead + slides (Teammate D). **Depends on:** Phase 8A (`msg_count`).
- **Goal:** turn "edge saves power/bandwidth" into a HARD number for the pitch.
- **Build (in `edge_analytics_tb.v`, print-only — no `.v` change):**
  - `samples_processed` = count of `out_valid` cycles (all analytics done on-chip).
  - `packets_transmitted` = `comms_tx.msg_count` (what actually left the chip).
  - Cloud-baseline bytes = `samples_processed * RAW_PKT_BYTES`; edge bytes =
    `packets_transmitted * ALERT_PKT_BYTES`. Reduction % = `100*(1 - edge/cloud)`.
  - Radio-power proxy: radio-on cycles avoided = samples not transmitted.
  - `$display` a summary block at end of sim (feeds one slide).
- **Done when:** the sim prints a credible "N samples processed on-chip, only K packets
  transmitted → X% less data / radio-on time vs streaming to the cloud."

### Phase 8E — remaining bonuses (as time allows)   Status: ⬜
- Teammate B synthesis reports; Teammate D slides/story. (`adaptive_anomaly` is now its
  own Phase 8F; joint fusion is 8C; `uart_tx.v` realism lives in 8A.)

### Phase 8G — visualization artifacts ("show the chip") — presentation-critical   Status: ⬜
- **Owner:** RTL lead + synthesis (B) + presentation (D). **Why:** judges (and rival
  teams) expect to SEE the chip. Produce THREE distinct artifacts (each answers a
  different question):
  1. **Waveforms (behaviour)** — already dumped to `dump.vcd`; open in `gtkwave`. For a
     shareable online copy, paste RTL+tb into **EDA Playground** → EPWave. Capture the
     money shot: raw (jagged) vs smoothed (clean) + `pump_on`/alerts firing.
  2. **Block/architecture diagram (story)** — clean redraw of the datapath: sensors →
     `sensor_collector` → `smoothing_stage` → `analytics_engine` (joint fusion + TEDA
     anomaly) → `output_analytics` → **{Tier-1 actuators | Tier-2 `comms_tx`}**. Deck asset.
  3. **Synthesized schematic (proof it's real silicon)** ⭐ — generate FROM the RTL:
     Vivado *RTL Analysis → Schematic* (+ utilization/timing/power), OR locally on the
     Mac via **Yosys** (`brew install yosys` → `read_verilog; synth; show`). This is the
     highest-impact "it's a real circuit" visual — currently our biggest missing artifact.
- **Done when:** all three exist and are in the deck / repo.

## Phase 9 — integrate, rehearse, submit   Status: ⬜
- Full run-through, capture waveforms + a dashboard recording, finalize the deck.

---

## Timestamp thread (across phases)
`sensor_collector` **makes** it (P1) → `analytics_engine` **captures** it per event (P3)
→ `output_analytics` **exposes** `event_timestamp` (P4) → stream `E` line **carries** it
(P5) → dashboard **displays** it in the event log (P7).
