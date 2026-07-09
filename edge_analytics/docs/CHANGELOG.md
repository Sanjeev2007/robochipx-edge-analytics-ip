# Changelog — Edge Analytics IP

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### 📌 AS-BUILT SNAPSHOT (latest — read this first)
- **Demo:** `demo/mission_control.html` — 223-sample story, **6 caretaker packets ≈ ~97% fewer
  transmissions** (6 of 223). Tier-2 visual is a **Radio Transmitter** (silent-by-design, shows the
  64-bit alert packet) — this **REPLACED the earlier "Caretaker's Phone"** wording used in older
  entries below. 8 always-visible feature tiles + ACTIVE-ALERT banner + 5 charts; UI scaled +25%.
- **Silicon:** Yosys synth = **~1,245 LUT / 1,163 FF / 3 DSP ≈ ~6% of Artix-7** (`synthesis/`).
  **No Fmax/power** (Yosys ≠ P&R). Slide content in `docs/SLIDE_CONTENT.md` reflects all of the above.
- Older entries in this file are the chronological build log; where they say "phone" / "66 samples"
  / "98%", the AS-BUILT numbers above supersede them.

### Added — Phase 8G (part 1): synthesis + schematics via Yosys on macOS ("it's real silicon")
- **Synthesized the full chip with Yosys 0.66 locally** (no Vivado/Windows needed). New `synthesis/`:
  - **`SYNTHESIS_REPORT.md`** — write-up + reproducible commands + an honesty note.
  - **`schematic_top_block.png/svg`** — whole chip as a netlist: all 6 module blocks wired
    (sensor_collector → smoothing_stage → adaptive_anomaly + analytics_engine → output_analytics
    → comms_tx) with the pipeline delay registers. The "real circuit, not a script" artifact.
  - **`schematic_moving_avg.png/svg`** — one module up close (8-tap shift register + running
    accumulator), coarse RTL cells so it's legible.
  - **`fpga_utilization.txt`** — raw `synth_xilinx` log.
- **FPGA utilization (Artix-7 xc7a35t / Basys-3):** **~1,245 LUTs / 1,163 FFs / 3 DSP48E1** →
  **~6 %** of the chip (generic synth = ~7,471 cells). The **3 DSP blocks = the TEDA anomaly
  multipliers** (one per channel); 200 CARRY4 = analytics adders; 1,163 FFs = the pipeline.
- ⚠️ **Honesty guardrail:** Yosys does synthesis, NOT place-and-route → **no Fmax/power figure**
  (would be fabricated). Fixed the stale "150 MHz / 40 mW" placeholders in `PRESENTATION_TASKS.md`
  + `SYNTHESIS_TASKS.md` to the real utilization + this caveat. **Waveforms (8G part 2) still TODO.**

### Changed — Canonical story-trace expanded 66 → 223 samples (richer multi-incident demo)
- **Modified ONLY `edge_analytics_tb.v`** (every RTL `.v` module stays frozen/untouched) and
  **regenerated `demo/mission_control_data.txt`**. The trace now runs **223 samples** (~210 target)
  through a 16-phase narrative that exercises EVERY feature, spread out so the dashboard stays lively
  end-to-end:
  A warm-up+healthy · B dry-spell→PUMP→recover (hysteresis) · C healthy · **D WEED #1** · E healthy ·
  **F HEAT wave + fast drop (weed SUPPRESSED = evaporation)** · G healthy · **H COLD snap / FROST** ·
  I healthy · **J NUTRIENT low** · K healthy · **L COMBINED stress (joint fusion)** · M healthy ·
  **N SENSOR anomaly (TEDA catch, nutrient rail)** · **O WEED #2** · P healthy tail.
- **Caretaker packets: 6** (target 5–8), sparse and on-message — `M,223,6,98` → **98% fewer
  transmissions**:
  `WEED@62` (INSPECT_WEED) · `STATUS_CRITICAL@96` (RELOCATE_REV — the heat+drought critical) ·
  `FROST_RISK@129` (PROTECT_FROST) · `NUTRIENT_LOW@152` (MANUAL_FERT) · `SENSOR_ANOMALY@197`
  (CHECK_SENSOR — TEDA catches the nutrient rail the engine's moisture-only rail check misses) ·
  `WEED@214` (INSPECT_WEED).
- **TEDA-aware trace shaping:** the self-tuning anomaly block has near-zero learned variance on a
  quiet channel, so any FIRST abrupt excursion reads as an outlier. Every transition that must NOT be
  a "sensor anomaly" (dry-spell, irrigation recovery, heat ramp, cold descent, nutrient decline,
  combined-stress easing) is kept GENTLE (≤~12 counts/sample) so the running mean tracks it; only the
  weed crashes, the heat-driven fast drop, and the intended nutrient rail are abrupt. Result: the
  **only** `alert_anomaly` in the whole run is the intended sensor fault (ts 197–199) — no spurious
  pages. Small deterministic ±5 `jit(k)` on steady segments makes the RAW columns wiggle like real
  sensors (the moving average smooths it; the reference `avg8` model reads the same arrays so
  alignment stays exact).
- **New FEATURE self-checks** (in addition to the existing alignment / warm-up / sparseness checks):
  the tb now asserts, per story-phase window, that weed fired in both weed phases, did NOT fire in the
  slow dry-spell, was SUPPRESSED under heat; and that heat / frost / nutrient / combined-stress /
  anomaly each fired in their window. All green.
- **VERIFIED: RESULT PASS, 0 errors** — `iverilog -o sim_top.vvp edge_analytics_top.v sensor_collector.v
  smoothing_stage.v moving_avg.v analytics_engine.v output_analytics.v adaptive_anomaly.v comms_tx.v
  edge_analytics_tb.v && vvp sim_top.vvp` (223 aligned 17-field D-rows, 6 sparse packets, 98% saved).
- ✅ **`demo/mission_control.html` refreshed to the new stream.** Re-embedded the 223-sample
  D/C/M data (inline, parsed offline — still no fetch), retargeted the counts (223 samples / 6 packets,
  scrubber 0–222), added the `RELOCATE_REV` action label (the STATUS_CRITICAL@96 heat-crisis page) and
  narration for the new WEED/FROST incidents, retuned the battery-drain constant for 223 samples, and
  aligned the "% saved" to the tb's integer M-line (98%). **Verified in gstack /browse: 0 console
  errors, N=223, 6 packets, phone buzzes at all 6 events (incl. FROST@129), fusion badge fires at
  ts≈187, counter ends 223 vs 6 → 98%.**

### Changed — ⭐ Mission Control redesign (R2): radio transmitter, feature tiles, more graphs
- **Reworked `demo/mission_control.html`** on user feedback so every feature is prominent, not just the
  3 sensor charts. Same self-contained offline file (inline CSS/JS, embedded 223-sample stream).
- **Caretaker's Phone → Tier-2 Radio Transmitter.** The phone mockup is gone; the panel now shows the
  actual hardware story: the chip emits a **64-bit `alert_packet`** and modulates it onto the radio.
  On each transmission an antenna bursts radio-wave rings and the packet is shown as **labeled,
  color-coded bit groups** (severity[4] · event[4] · action[4] · crop_health[8] · reserved[12] ·
  timestamp[32]) — reconstructed exactly per `INTERFACES.md §6` (verified against the sim's packet hex),
  plus the decoded fields (severity / event / action / health).
- **Edge-win folded into the radio panel** (user's call): "radio transmissions — dumb node 223 vs our
  chip 6 → 97% fewer", with a proportional bar. Dropped the separate battery-bars panel.
- **Every feature is now an always-visible tile that flashes on fire** (8 tiles: pump, doser, weed,
  heat, frost, nutrient, joint-fusion, TEDA), each with a live status (monitoring→DETECTED,
  clear→COMBINED STRESS, learning→FLAGGED, …) and a colored glow + "● FIRED" spark when active.
- **Big active-alert banner** across the top names the current situation prominently (e.g. "CRITICAL ·
  WEED DETECTED", "HEAT STRESS", "SENSOR ANOMALY", "ALL SYSTEMS NOMINAL") with the recommended action.
- **More graphs:** added a **crop-health trend** line and a **moisture depletion-rate** chart (drop over
  4 samples with the RATE_THRESH weed line drawn in) alongside the 3 raw-vs-smoothed sensor charts (5 total).
- **Fusion semantics fixed:** the joint-fusion classification now requires the pump to be OFF, so a plain
  dry-spell (which raises status with the pump running) reads "IRRIGATING", and only the genuine
  sub-threshold dry+hot case reads "COMBINED STRESS".
- **Fixed the janky horizontal scroll:** the page never scrolls horizontally (`overflow-x:hidden`, grid
  columns use `minmax(0,…)`, wide content like the bit strip / log scrolls smoothly inside its own box).
  Verified: `document.body.scrollWidth == clientWidth` at 1440px.
- **VERIFIED in gstack /browse (0 console errors)** across all key moments: warm-up (silent radio),
  dry-spell→IRRIGATING, WEED (tile + radio TX), HEAT (heat tile lit while weed tile stays "monitoring" =
  suppression made visible), FROST, NUTRIENT LOW, COMBINED STRESS (pump off), SENSOR ANOMALY (radio TX +
  64-bit packet), ending 223 vs 6 → 98%.
- **Polish pass (user feedback):** (1) whole UI scaled **+25%** for the projector via `zoom:1.25` on
  `.app` with width/height compensated (`calc(100vw/1.25)`), so it still fits exactly one screen with no
  horizontal scroll; (2) the **3 sensor graphs now `flex:1` to fill their panel** (moisture / nutrient /
  temp share the full panel height, no dead space) while the derived Analytics charts (crop-health,
  depletion-rate) stay fixed; column still scrolls if it overflows; (3) each Live-Features tile gained a
  small **ⓘ info icon** with a hover tooltip explaining that parameter (rendered outside the zoom layer
  so it never clips); (4) the timeline **progress bar is now smooth** — replaced the stepped native range
  with a custom fill+knob that transitions linearly over each step interval during playback (instant when
  scrubbing/paused). Verified: 0 console errors, app renders exactly 1440×900, `scrollWidth==innerWidth`.
- **Clarified for the record (not a code change):** the stream carries **17 D-line fields but only 3 are
  physical sensors** (moisture / nutrient / temp, each drawn raw+smoothed = 6 fields); the other 11 are
  timestamp + the chip's computed decisions (pump, doser, 5 alerts, status, crop_health, relocate) — all
  17 are already on the dashboard (sensors→graphs, decisions→tiles/gauge/badge). Three sensors is the
  deliberate frozen count (`NUM_CH=3`; "fusion smarter, not wider" — no humidity channel).

### Added — ⭐ WEB Mission Control (6a) — the hero demo (`demo/mission_control.html`)
- **Built `demo/mission_control.html`** — ONE self-contained screen that REPLAYS the real captured
  sim stream (`demo/mission_control_data.txt`) as an animated story. Opens by double-click
  (`file://`); NO server, NO CDN, NO libraries — inline CSS + vanilla JS + inline SVG. The 66 D-rows
  + 2 C-packets + M-line are EMBEDDED in the file and parsed at load (no runtime fetch → works fully
  offline). Dark "mission control" theme, tuned for a projector.
- **Panels (all from `PRESENTATION_TASKS.md` map):** raw-vs-smoothed SVG line charts (moisture/
  nutrient/temp, faint raw + bold smoothed, progressive reveal, warm-up band shaded) · status badge +
  crop-health gauge · Tier-1 pump/doser with a "watering" pulse · **weed-vs-evaporation** callout
  (derived: `alert_weed`→WEED; `alert_heat`→"evaporation, weed suppressed"; else drawdown-normal) ·
  **⭐ COMBINED-STRESS fusion badge** (fires when `status>0` but every `alert_*`=0 — real at ts 24–25) ·
  **TEDA self-tuning anomaly** indicator (`alert_anomaly`) · **⭐ Caretaker's Phone** (silent, buzzes
  ONLY on a `C,` packet, shows severity + event + ACTION) · **⭐ Dumb-node vs Our-chip counter** (66 vs
  2, two battery bars, "97% fewer transmissions", labelled illustrative) · event/timeline log.
- **Playback:** auto-play (play/pause/restart), 0.5×/1×/2×/4× speed, a scrubber, keyboard
  (space/←/→/R), and a narration line naming the story phase (warm-up → dry spell → pump → nutrient →
  heat → anomaly). First 10 D-rows render in a dimmed "filters settling…" state (honest warm-up); a
  small line reads "replaying real Icarus Verilog sim output".
- **VERIFIED in a headless browser (gstack /browse):** 0 console errors; 66 rows parsed; the two
  caretaker packets fire the phone at ts=38 (WARNING NUTRIENT_LOW → TOP UP NUTRIENTS, pkt #1) and
  ts=56 (CRITICAL SENSOR_ANOMALY → CHECK/REPLACE SENSOR, pkt #2); combined-stress badge lights at
  ts 24–25; counter ends 66 vs 2 → 97%, battery bars 18% vs 98%. Screenshots captured at each beat.
- **Scope kept clean:** no `.v` file and no tkinter dashboard touched. NEXT = **6b tkinter upgrade**.

### Planning — Mission Control = two artifacts, separate agents, one at a time
- **Showcase splits into two builds** (lead builds neither; each is a separate agent, sequential):
  **(1) WEB Mission Control** (`demo/mission_control.html`) — hero demo, a self-contained page that
  replays the real captured sim stream (`demo/mission_control_data.txt`); **(2) tkinter upgrade** —
  add the panels to the teammate's `edge_agri_dashboard.py` on the live pipe (the "live proof").
  Web first, tkinter second. Panel map + data contract in `PRESENTATION_TASKS.md` / `memory.md §10`.
- **`demo/mission_control_data.txt` captured** — the exact D/E/C/M sim stream both artifacts render.

### Added — Warm-up gate (top) + Phase 8D edge-win number & machine-readable caretaker stream
- **Modified ONLY `edge_analytics_top.v` + `edge_analytics_tb.v`** — every RTL sub-module stays
  frozen IP, untouched. Two changes, in one pass:
- **(1) WARM-UP GATE (`edge_analytics_top.v`).** The ts=0 caretaker packet was a FALSE alarm — a
  moving-average fill transient: while the 8-sample window fills from zero, `avg_temp` reads
  artificially COLD and fires a spurious `FROST_RISK` → a fake caretaker packet at ts=0. Fix: a
  `warm_cnt` counts valid output cycles (`oa_valid`); `warm_done = (warm_cnt >= WARMUP_N)` with
  `WARMUP_N = (1<<LOG2_N)+2 = 10` (the 8-sample window + a 2-cycle pipeline margin). `comms_tx`'s
  `in_valid` is now gated `oa_valid & warm_done`, so the **Tier-2 caretaker radio stays SILENT
  until the filters settle**. The aligned **17-field D-line and EVERY Tier-1 actuator
  (pump/doser/alerts) are byte-for-byte UNCHANGED** — only the sparse Tier-2 radio is muted during
  warm-up. Result: the false ts=0 `FROST_RISK` packet is GONE; caretaker packets 3 → **2 real**
  (`NUTRIENT_LOW@38`, `SENSOR_ANOMALY@56`), both still transmit.
- **(2) PHASE 8D — edge-win metric + machine-readable caretaker stream (`edge_analytics_tb.v`).**
  The frozen 17-field `D,` row is kept EXACTLY; only new line types were ADDED:
  - For **each** caretaker packet, a machine-readable **`C,<ts>,<severity>,<event>,<action>,
    <crop_health>,<msg_count>`** line (reuses the existing sev/event/action decode; the human `#
    CARETAKER TX` comment is kept alongside). Feeds the dashboard's "Caretaker's Phone" panel.
  - The **EDGE-WIN**: a naive node streams every valid sample (`dumb = samples_processed`); our
    chip transmits only the sparse alerts (`our = msg_count`). `pct_saved = 100 - (100*our)/dumb`.
    Emitted as a machine line **`M,<samples>,<msg_count>,<pct_saved>`** plus a human summary. This
    run: **`M,66,2,97` → 97% fewer transmissions.**
  - **4 self-checks** (all `#`-prefixed, roll into `errors` → RESULT PASS/FAIL): (a) D-line still
    17 fields / 0 alignment errors; (b) **no caretaker packet at ts=0** (warm-up gate works);
    (c) at least **2 real packets** transmit; (d) `msg_count` ≪ `samples_processed` (sparseness).
- **VERIFIED — RESULT: PASS (0 errors):** `iverilog -o sim_top.vvp edge_analytics_top.v
  sensor_collector.v smoothing_stage.v moving_avg.v analytics_engine.v output_analytics.v
  adaptive_anomaly.v comms_tx.v edge_analytics_tb.v && vvp sim_top.vvp`. 66 samples processed
  on-chip, **exactly 2 sparse caretaker packets** (`C,38,WARNING,NUTRIENT_LOW,MANUAL_FERT,205,1`
  and `C,56,CRITICAL,SENSOR_ANOMALY,CHECK_SENSOR,205,2`), `M,66,2,97`, warm-up gate silent at
  ts=0, all 66 D rows unchanged (17 fields, 0 alignment errors).

### Planning — Strategy locked: stay agriculture + "Mission Control" showcase
- **Pivot REJECTED, agriculture stays.** Weighed re-skinning the same IP to a higher-drama
  domain (structural/bridge, disaster warning) or a general "edge-sentinel IP" reframe — both
  rejected (no real second-domain story, too much churn at <12h). **Win on execution + technical
  depth**, calibrated to a chip-engineer audience ("self-tuning anomaly in divider-free silicon"
  is the wow for *that* room). Lead the pitch with "no surveyed system does edge analytics in
  dedicated RTL." Full record: `memory.md §10` recent-decisions.
- **⭐ Showcase = "Mission Control" dashboard** — the core remaining work. One live screen where
  every feature lights up on the story trace; the two invisible differentiators become the stars:
  a **"Caretaker's Phone"** (silent, buzzes ~3× with an action) + a **"Dumb node vs Our chip"**
  transmission counter. Almost all panels derive from the existing 17-field `D,` line; only the
  caretaker packets need a new `C,` line (Phase 8D). Panel map in `PRESENTATION_TASKS.md`.
- **Revised phase order:** warm-up fix → 8D (edge-win number + `C,` caretaker stream) → Mission
  Control dashboard → schematic (8G, teammate, parallel) → `crop_profile.v` (optional) → Phase 6.

### Added — Crop + soil profile DATA (Task 4 deliverable)
- **`docs/CROP_PROFILE_DATA.md` created** — real, cited agronomic setpoints for 4 crops
  (tomato, wheat, rice, lettuce) × 3 soils (sandy, loam, clay). Contains: (1) real-units
  table with an inline citation per value, (2) the same values scaled to the chip's 0–4095
  range with every conversion shown, (3) a ready-to-paste **ROM-ready block** of the 5
  setpoints `{moisture_target, nutrient_target, temp_lo, temp_hi, depletion_baseline}` per
  `{crop_id, soil_id}`, (4) a References-slide source list.
- **Sources:** FAO-56 Table 12 (`Kc`) + Table 22 (depletion `p`, rooting depth); USDA NRCS
  AWC/FC/WP by soil texture; UC IPM / Tri-State / Missouri extension NPK soil-test guides;
  agronomy cardinal-temperature refs. `nutrient_target` index magnitude + depletion constant
  `C` are marked **ESTIMATED** (their `Kc`/`AWC`/soil-test components are cited; no fake cites).
- **`crop_profile.v` can now be built from this file** (RTL lead's Tier-1.6 task). ⚠️ Doc
  flags an **encoding-reconciliation** point: Task-4 uses the full 0–4095 range (`%×40.95`,
  `°C×81.9`), while the frozen §5 thresholds/story-trace use the compressed testbench band
  (`/5`, `/10`); an operational-band equivalent column is included so the RTL lead can pick
  one encoding project-wide.

### Planning — Crop/soil profiles + showcasing direction (post-integration)
- **Crop + soil profile — proposed feature** (replaces dropped predict-dry). `crop_profile.v`
  ROM makes thresholds configurable per `crop_id` + `soil_id`. **Data sources** documented:
  FAO-56 (Kc + depletion `p`), USDA NRCS (AWC by soil texture), extension NPK guides, agronomy
  cardinal temps; scaled to 0–4095. Added to `ROADMAP.md` (Tier 1.6), `PROBLEM_STATEMENT.md`,
  and a ChatGPT-ready data-gathering task (`DATA_TASKS.md` Task 4). Build AFTER 8D.
- **Showcasing = "virtual chip processing data" → DigitalJS Online**, NOT Wokwi/Tinkercad
  (those run Arduino/ESP C, cannot run our Verilog; using one as "our chip" = credibility risk
  at a chip event). DigitalJS shows our REAL synthesized netlist interactively. Added to
  `ROADMAP.md` Tier 3 + `PRESENTATION_TASKS.md`.
- **Integration follow-up flagged:** the ts=0 FROST caretaker packet is a moving-avg warm-up
  transient — gate `comms_tx` valid until the filter settles BEFORE Phase 8D counts packets.

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
- **INTEGRATION — wired `adaptive_anomaly` (8F) + `comms_tx` (8A) into `edge_analytics_top`**
  (modified **ONLY** `edge_analytics_top.v` + `edge_analytics_tb.v`; every RTL sub-module —
  `analytics_engine`, `output_analytics`, `comms_tx`, `adaptive_anomaly`, `sensor_collector`,
  `smoothing_stage`, `moving_avg` — was treated as **frozen IP and left untouched**). The two
  stand-alone bonus blocks (built + verified in isolation in 8A/8F) are now folded into the
  live pipeline; the chip's full **two-tier output** (Tier-1 aligned D-line + Tier-2 sparse
  caretaker radio) runs end-to-end.
  - **(A) TEDA anomaly in PARALLEL with the engine.** `adaptive_anomaly` is fed the SAME
    smoothed set (`sm_avg_moisture/nutrient/temp`) + `sm_valid` the engine gets (born t=2);
    like the engine it registers its outputs, so `ta_anomaly`/`ta_anom_ch` land at **t=3** —
    the same cycle as the engine's decisions, no extra alignment needed.
  - **Anomaly merge:** `anomaly_merged = ae_anomaly | ta_anomaly` (both t=3) is what now feeds
    `output_analytics.anomaly()` (instead of the raw engine `ae_anomaly`), so `alert_anomaly`
    reflects BOTH the always-on rail-stuck check AND the learned TEDA detector.
  - **(B) Caretaker event-injection path (the key new wiring).** `output_analytics` emits its
    event bus at t=4; `ta_anomaly` (t=3) is delayed +1 to line up at t=4 and its 0→1 rising
    edge is detected there. The comms feed is:
    `comms_event_id = (oa_event_id != NONE) ? oa_event_id : (ta_anomaly_rising ? SENSOR_ANOMALY(7) : NONE)`
    with a matching timestamp (real event's stamp, or the sample's own `ts_d3` for an
    injection). **The engine/output event ALWAYS wins; injection only fills in when the
    merged pipeline reported NONE** — i.e. a TEDA-only anomaly the engine's event path never
    raised (that path keys off the raw moisture rail check, not the merged flag).
  - **(C) `comms_tx` as a side channel:** `in_valid=oa_valid`, `event_id=comms_event_id`,
    `event_timestamp=`matching ts, `status=oa_status`, `crop_health=oa_crop_health`. Its
    outputs are **+1 vs the D-bundle (t=5)** — the async caretaker radio, deliberately NOT
    aligned into the 17-field row.
  - **New top-level output ports:** `out_msg_valid`, `out_alert_packet[63:0]`,
    `out_msg_count[15:0]`, and `out_anom_ch[2:0]` (per-channel TEDA flags, delayed +1 to sit on
    the t=4 alert-bus cycle — for waveforms/debug). All new wires/latencies are commented in
    plain English per `CLAUDE.md`.
  - **Testbench (`edge_analytics_tb.v`):** the 17-field CSV row + its alignment self-checks are
    kept EXACTLY (frozen contract, `INTERFACES.md §3`). Added a `#`-prefixed CARETAKER-RADIO
    monitor that decodes every `msg_valid` strobe (severity/event/action/health/reserved/ts per
    §6) and a final INTEGRATION SUMMARY with three self-checks: (a) D-line still 17 fields / 0
    alignment errors; (b) ≥1 caretaker packet transmitted; (c) `msg_count` ≪ sample count
    (the sparseness we pitch). Extended the story trace by a **Phase F — nutrient-sensor
    stuck-HIGH fault** (rail 4095, moisture wet, temp normal): the engine raises no event and
    its moisture-only rail check misses it, but TEDA flags the outlier → the top INJECTS
    SENSOR_ANOMALY → the caretaker is paged CHECK_SENSOR. NS 56 → 66.
  - **VERIFIED — RESULT: PASS (0 errors):**
    `iverilog -o sim_top.vvp edge_analytics_top.v sensor_collector.v smoothing_stage.v
    moving_avg.v analytics_engine.v output_analytics.v adaptive_anomaly.v comms_tx.v
    edge_analytics_tb.v && vvp sim_top.vvp`. **66 samples processed on-chip, exactly 3 sparse
    caretaker packets** transmitted (msg_count reg = 3, matches strobes counted):
    - `sev=CRITICAL event=FROST_RISK action=PROTECT_FROST health=70 ts=0` (warm-up transient),
    - `sev=WARNING event=NUTRIENT_LOW action=MANUAL_FERT health=205 ts=38` (standard path),
    - `sev=CRITICAL event=SENSOR_ANOMALY action=CHECK_SENSOR health=205 ts=56` (⭐ TEDA-only
      anomaly reaching the radio via the new INJECTION path). Packet bit-packing verified vs §6
      (e.g. `372cd00000000038` = sev3|ev7|ac2|health0xCD|resv0|ts0x38). The flapping rail's
      second edge (ts=63) was correctly **suppressed by the MSG_GAP rate-limit** — anti-spam in
      action. Stream remains clean 17-field CSV + `#` comment lines; every one of the 66 D rows
      has exactly 17 fields (0 alignment errors). Dashboard command unchanged conceptually.
- **Phase 8C — JOINT / CORRELATED fusion** (upgraded `analytics_engine.v` **in place** — the
  ONLY `.v` touched; **port list UNCHANGED** so the top still wires; **no humidity channel**,
  3 channels / frozen 17-field dashboard contract intact). Upgrades fusion from
  OR-of-thresholds → a **correlated judgment** so the chip reasons about channel
  *combinations*, not each sensor alone — the "analytics in silicon, not trivial comparators"
  answer to the judge. Built exactly to `BUILD_PLAN.md` Phase 8C + `INTERFACES.md §5`.
  - **New correlated conditions** (internal; drive `status`/`crop_health`, add NO new ports
    or event ids): `combined_dry_heat = dry_warn && hot_warn` — moisture in the "getting dry"
    band `[DRY_THRESH, DRY_WARN)` AND temp in the "getting warm" band `(HOT_WARN, HOT_THRESH]`
    at the SAME time. By construction each channel is sub-threshold ("fine" to an
    OR-of-thresholds engine), so only the JOINT view catches it (→ WARNING). Also
    `real_heat_stress = hot && moisture_falling` (heat WITH active drying → CRITICAL) and
    `nutrient_crisis = low_nutrient && crop_health<HEALTH_CRISIS` (→ CRITICAL).
  - **`crop_health` is now an interaction-aware WEIGHTED score:** single-channel penalties
    (`PEN_DRY`=60, `PEN_NUT`=50, `PEN_HOT`=50, `PEN_COLD`=50, `PEN_WEED`=80, `PEN_ANOM`=40)
    PLUS extra co-occurrence penalties (`PEN_DRY_HOT`=40, `PEN_DRY_NUT`=25, `PEN_COMBINED`=30)
    so combined stress costs MORE than the sum of its parts — e.g. `dry && hot` is now
    255−60−50−40 = **105** (was 145). Still 0–255, clamped ≥0. New bands/params
    (`DRY_WARN`=260, `HOT_WARN`=360, `FALL_THRESH`=40, `HEALTH_CRISIS`=120) and all weights
    are **named `parameter`s** (no literals), documented in `INTERFACES.md §5`.
  - **Base single-channel condition outputs (`dry/low_nutrient/hot/cold/weed/anomaly`) and the
    event id/priority logic are UNCHANGED** — only the fusion of them into `crop_health`/`status`
    got smarter. Synthesizable, `clk`/`rst`, fully commented — per `CLAUDE.md`.
  - **`analytics_engine_tb.v`:** the EXISTING regression (HEALTHY → dry-spell → weed → heat,
    8 self-checks) is kept and still PASSES; **added a JOINT/FUSION phase** (ts 4300–5000:
    moisture 240 / temp 380 / nutrient 300 held steady) with 3 new self-checks proving genuine
    fusion — every base condition stays 0 (each channel "fine") yet the combination is flagged
    (`status`≠SAFE) and `crop_health` is penalised (< 255). NUM_SAMPLES 42 → 50.
- **Phase 8F — `adaptive_anomaly.v`** (⭐ the researcher-impressive TEDA self-tuning anomaly
  detector) — a **NEW standalone module; no existing `.v` was modified.** Replaces the fixed
  rail-stuck anomaly check with a block that **learns each sensor's own normal on-chip and
  flags statistical outliers**, parameter-free per field. Built exactly to `BUILD_PLAN.md`
  Phase 8F + `INTERFACES.md` §7.
  - **Inputs:** `clk`, `rst`, `in_valid`, `avg_moisture[11:0]`, `avg_nutrient[11:0]`,
    `avg_temp[11:0]`. **Outputs:** `anomaly` (1 = any channel flagged) + `anom_ch[2:0]`
    (per-channel flags). Both **registered** (1-cycle latency, matches the pipeline).
  - **TEDA reduced to a divider-free datapath.** Per channel keeps two EMA state registers
    **μ (mean)** and **V (variance)**, updated by SHIFT, never divide:
    `diff = x−μ`; `μ' = μ + (diff>>>TEDA_ALPHA)`; `sq = diff*diff` (the ONE multiplier);
    `V' = V + ((sq−V)>>>TEDA_ALPHA)`. The eccentricity test becomes the Chebyshev form
    **`(x−μ)² > m²·V`** with `bound = 9·V = (V<<3)+V` for m=`TEDA_SIGMA_M`=3 (shift+add, no
    extra multiplier). The test uses the **PRE-update** μ,V. Cost/channel = 1 multiplier +
    a few adders + fixed shifts + comparator + μ/V regs + warm-up counter — the
    drawable-as-a-real-circuit datapath for Phase-8G (backed by the TEDA-FPGA paper).
  - **Guards:** warm-up counter suppresses flags until `warm_cnt >= TEDA_WARMUP`(8); the first
    valid sample PRIMES μ=x, V=0 so the baseline starts at the real signal (not a slow 0-ramp
    that would inflate V and mask a later spike). The fixed **rail-stuck** check
    (`x==0||x==4095`) is OR'd in as an always-on fast path so a truly dead sensor trips
    instantly. Wide (32-bit signed) `sq`/`V`/`bound` → no overflow; fixed-point; all constants
    are named `parameter`s (`TEDA_SIGMA_M`, `TEDA_ALPHA`, `TEDA_WARMUP`) — no literals.
  - Synthesizable, `clk`/`rst`-driven, fully commented — per `CLAUDE.md`.
  - **NOT yet wired into `analytics_engine`** — standalone module + its own tb for now;
    replacing the engine's fixed rail check with this output is a later integration step.
- **Phase 8A — `comms_tx.v`** (⭐ the flagship differentiator — event-triggered caretaker
  comms) — a **NEW standalone module; no existing `.v` was modified.** This is the chip's
  **second output tier**: a sparse, machine-to-human alert channel (LoRa/GSM → caretaker's
  phone), distinct from the continuous dashboard telemetry (§3). Built exactly to
  `BUILD_PLAN.md` Phase 8A + `INTERFACES.md` §6.
  - **Inputs** (from `output_analytics`): `clk`, `rst`, `in_valid`, `event_id[3:0]`,
    `event_timestamp[31:0]`, `status[1:0]`, `crop_health[7:0]`.
  - **Two-tier triage** — each `event_id` maps to `{notify?, severity, action_code}`:
    human-needed events build a packet — WEED_DETECTED→INSPECT_WEED, SENSOR_ANOMALY→
    CHECK_SENSOR, NUTRIENT_LOW→MANUAL_FERTILIZE, FROST_RISK→PROTECT_FROST, STATUS_CRITICAL→
    RELOCATE_OR_REVIEW, PREDICT_DRY→PRE_IRRIGATE (codes per §6). Machine-handled PUMP_ON/
    PUMP_OFF send NOTHING (the pump already acted); HEAT_STRESS has no caretaker action in
    §6 so it also stays local. *This split is the concrete answer to "it's just automation":
    automation acts, comms escalates only when a human is genuinely needed.*
  - **`severity`** derived from BOTH `event_id` (per-event base: WEED/ANOMALY/FROST/CRITICAL
    = CRITICAL, NUTRIENT_LOW = WARNING, PREDICT_DRY = INFO) AND `status` (escalates to
    CRITICAL when `status==2`).
  - On a qualifying **event edge**, asserts `msg_valid` for one cycle with the 64-bit
    `alert_packet` packed MSB→LSB per §6: `{severity[4], event_code[4], action_code[4],
    crop_health[8], reserved[12], event_timestamp[32]}`.
  - **Rate limit** (`MSG_GAP`=8 valid cycles, §7 param): a down-counter blocks a REPEAT of
    the SAME event until the gap elapses; a DIFFERENT event bypasses it — no alert spam.
  - **`msg_count[15:0]`** running tally of transmitted packets (feeds the Phase 8D edge-win
    math). All constants are named `parameter`s/`localparam`s — **no hard-coded literals.**
  - All outputs **registered** (1-cycle latency, matches the pipeline); synthesizable,
    `clk`/`rst`-driven, fully commented — per `CLAUDE.md`.
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
- **Phase 8C JOINT fusion** — recompiled + ran `analytics_engine` with the upgraded fusion and
  the extended testbench (`iverilog -o simulation.vvp analytics_engine.v analytics_engine_tb.v
  && vvp simulation.vvp`). **RESULT: PASS (0 errors).**
  - **REGRESSION intact:** all 8 ORIGINAL self-checks green — HEALTHY clean (status SAFE,
    health 255); `dry` fires in the slow dry-spell while `weed` does NOT; `weed` +
    WEED_DETECTED(3) fire on the sharp normal-temp drop (ts 2600); `hot` + HEAT_STRESS(5) fire
    in the heat phase; and the hot fast-drop does NOT read as `weed` (temperature compensation).
    Base condition/event behaviour is byte-for-byte unchanged.
  - **New fusion behaviour visible in the trace:** at ts 3600 `real_heat_stress` (hot + moisture
    falling) escalated status to CRITICAL; at ts 3700+ the `dry && hot` interaction dropped
    `crop_health` to **105** (255−60−50−`PEN_DRY_HOT`40) vs the old 145 — combined stress now
    costs more than the sum.
  - **New JOINT/FUSION self-checks (the genuine-fusion proof):** in the joint phase (ts
    4300–5000, moisture 240 / temp 380 / nutrient 300) every base condition read 0 (each channel
    individually "fine" — an OR-of-thresholds engine calls this SAFE/health 255), yet the chip
    flagged `status`=WARNING(1) and `crop_health`=225 (`PEN_COMBINED`). All 3 new checks PASS:
    (a) no single-channel threshold fired, (b) the combination WAS flagged, (c) crop_health was
    penalised by the interaction. VCD (`dump.vcd`) dumped.
  - **Top still wires:** re-compiled the FULL chip (`edge_analytics_top.v` + all sub-modules +
    `edge_analytics_tb.v`) with the modified engine — **RESULT PASS (0 alignment errors)**, output
    still valid 17-field CSV. The port list was unchanged, so integration is untouched.
- **Phase 8F `adaptive_anomaly`** — compiled + ran the standalone module and its testbench
  (`iverilog -o simulation.vvp adaptive_anomaly.v adaptive_anomaly_tb.v && vvp
  simulation.vvp`). **RESULT: PASS (0 errors).** The testbench feeds moisture at **~600±12**
  then a single **660 spike (NOT a rail)**, with nutrient (300) and temp (250) held steady:
  - The learned TEDA detector **flagged the spike** — `anomaly=1`, `anom_ch=001` (moisture
    channel ONLY) — while the OLD fixed rail-check (`x==0||x==4095`) returned **no** on the
    same sample. The tb prints the head-to-head: *TEDA=YES, fixed=no ⇒ TEDA caught an
    off-baseline outlier the fixed check would miss.*
  - **No false flags** during the 8-sample warm-up (early noisy statistics suppressed) or on
    the ordinary ±12 jitter after warm-up; the steady nutrient/temp channels never flagged;
    and the detector returned quiet on the samples after the spike (no lingering flag).
  - VCD (`dump.vcd`) dumped. Confirms the self-calibrating detector catches a wrong-but-in-
    range outlier a fixed threshold misses, with zero false alarms on normal noise.
- **Phase 8A `comms_tx`** — compiled + ran the standalone module and its testbench
  (`iverilog -o simulation.vvp comms_tx.v comms_tx_tb.v && vvp simulation.vvp`).
  **RESULT: PASS (0 errors).** The story (WEED → PUMP_ON → NUTRIENT_LOW → NUTRIENT_LOW
  rapid-repeat → FROST_RISK → PREDICT_DRY → HEAT_STRESS) produced **exactly 4 packets**:
  - `sev=3 event=3 action=1 health=30 ts=100` (WEED → INSPECT_WEED, CRITICAL),
  - `sev=2 event=4 action=3 health=60 ts=120` (NUTRIENT_LOW → MANUAL_FERTILIZE, WARNING),
  - `sev=3 event=6 action=4 health=45 ts=140` (FROST_RISK → PROTECT_FROST, CRITICAL),
  - `sev=1 event=9 action=6 health=80 ts=160` (PREDICT_DRY → PRE_IRRIGATE, INFO).
  PUMP_ON and HEAT_STRESS transmitted **nothing** (Tier-1 / no caretaker action), and the
  rapid NUTRIENT_LOW repeat was **suppressed by the MSG_GAP rate-limit**. `msg_count`
  register = 4, matching the packets seen on the wire. Reserved field = 0; bit-packing
  verified against §6 (e.g. `3311e00000000064` = sev3|ev3|ac1|health0x1E|resv0|ts0x64).
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
