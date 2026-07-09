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
- `python3` 3.14.6 (Homebrew) + `python-tk@3.14` — INSTALLED. ✅ Needed to run the
  dashboard GUI (`edge_agri_dashboard.py`, tkinter). `import tkinter` OK (Tk 9.0).

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
| 5 | `edge_analytics_top` | Wire the blocks + latency-alignment delay lines (raw/ts +3, avg +2); aligned output bundle. **INTEGRATION done:** now also instantiates `adaptive_anomaly` (parallel, t=3), merges anomaly into `output_analytics`, and hangs `comms_tx` off the event bus with a TEDA-only-anomaly injection path; new top ports `out_msg_valid`/`out_alert_packet[63:0]`/`out_msg_count[15:0]`/`out_anom_ch[2:0]` | ✅ built + simulated (incl. 8A+8F integration) |
| 5.5 | `edge_analytics_tb` egress | Testbench-only: emit the dashboard's 17-field CSV (header once + row/cycle) with count→display-unit scaling; RTL untouched | ✅ done + simulated |
| 8A | `comms_tx` ⭐ | **Differentiator:** event-triggered alert packet (severity+action_code) to the remote caretaker; rate-limited; `msg_count`. The "beyond automation" answer | ✅ built + simulated |
| 8B | `predictor` | Divider-free moisture-slope extrapolation → `predict_dry`/PREDICT_DRY early warning; reuses the weed `dropped` primitive | ⬜ planned |
| 8C | JOINT fusion | Upgrade `analytics_engine` fusion from OR-of-thresholds → correlated/interaction-aware `crop_health`+`status` (NO humidity channel — keeps 3-ch dashboard contract) | ✅ built + simulated |
| 8D | edge-win metric | Testbench-only: samples-processed vs packets-transmitted → % data / radio-on saved | ⬜ planned |
| 8F | `adaptive_anomaly` ⭐ | TEDA self-tuning anomaly: running μ+σ² per channel, Chebyshev eccentricity, divider-free (cross-mult). Replaces fixed rail-check. The researcher-impressive block | ✅ built + simulated |
| 8G | visualization | 3 artifacts: gtkwave/EPWave waveforms + block diagram + **Vivado/Yosys synthesized schematic** ("show the chip") | ⬜ planned |

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
- **✅ TWO INTEGRATION FOLLOW-UPS (found + FIXED while verifying Phase 5.5):**
  1. **tkinter** — installed `python-tk@3.14` via Homebrew (matches Python 3.14.6);
     `import tkinter` OK (Tk 9.0). The dashboard GUI can now launch on the Mac.
  2. **Banner hygiene** — the testbench's `RESULT`/separator lines are now `#`-prefixed
     so the dashboard's `parse_sample` skips them. Re-verified with the REAL dashboard
     module: **56 valid samples, 0 junk**; `ts=24` → moisture_avg 39, pump ON, WARNING,
     health 76. Stream is clean pure-CSV (the auto `VCD info:` line is harmlessly skipped).
- **END-TO-END READY:** `vvp simulation.vvp | python3 robochipx_dashboard_handoff/edge_agri_dashboard.py`
  should now drive the real dashboard GUI on the Mac. (GUI window can't be launched in a
  headless agent shell — the human runs it; everything up to the GUI is verified.)
- **✅ Phase 8A DONE (the flagship differentiator — `comms_tx`):** built `comms_tx.v` as a
  NEW standalone module (no existing `.v` touched). It watches `output_analytics`'s merged
  event bus and, on a qualifying event edge, transmits ONE 64-bit `alert_packet`
  (`{severity[4], event_code[4], action_code[4], crop_health[8], reserved[12],
  event_timestamp[32]}`, MSB→LSB per §6) carrying a recommended caretaker action.
  - **Two-tier split enforced:** human-needed events (WEED→INSPECT_WEED, SENSOR_ANOMALY→
    CHECK_SENSOR, NUTRIENT_LOW→MANUAL_FERTILIZE, FROST_RISK→PROTECT_FROST, STATUS_CRITICAL→
    RELOCATE_OR_REVIEW, PREDICT_DRY→PRE_IRRIGATE) build a packet; machine-handled
    PUMP_ON/PUMP_OFF (and HEAT_STRESS, which has no caretaker action in §6) send NOTHING.
  - **Severity** derived from event_id base AND status (escalates to CRITICAL if status==2).
  - **Rate-limit** (`MSG_GAP`=8, §7 param): a down-counter blocks a REPEAT of the SAME event
    for MSG_GAP valid cycles; a DIFFERENT event bypasses it. `msg_count[15:0]` tallies TX'd
    packets (feeds Phase 8D). All constants are named `parameter`s/`localparam`s — no literals.
  - **`comms_tx_tb.v`** drives WEED, PUMP_ON (no pkt), NUTRIENT_LOW, NUTRIENT_LOW rapid-repeat
    (suppressed), FROST_RISK, PREDICT_DRY, HEAT_STRESS (no pkt). Self-check: exactly **4
    packets**, each with correct sev/event/action/health/reserved/ts, and `msg_count==4`.
    **Compiled + ran: RESULT PASS (0 errors)** (`iverilog -o simulation.vvp comms_tx.v
    comms_tx_tb.v && vvp simulation.vvp`). VCD dumped. Outputs registered (1-cycle latency),
    synthesizable, fully commented, clk/rst — per CLAUDE.md.
  - **NOT yet wired into `edge_analytics_top`** — `comms_tx` is a standalone module + its own
    tb for now. Top-level integration (tap `output_analytics`'s `event_id/event_timestamp/
    status/crop_health` into `comms_tx`) is a later step, bundled with the Phase 6 re-capture.
- **✅ Phase 8F DONE (the researcher-impressive TEDA block — `adaptive_anomaly`):** built
  `adaptive_anomaly.v` as a NEW standalone module (no existing `.v` touched). Per-channel
  learns its own μ (mean) + V (variance) as EMA state regs, updated by SHIFT (`>>>TEDA_ALPHA`,
  weight 1/8), never a divide. The TEDA eccentricity test reduces to the divider-free
  Chebyshev form **`(x−μ)² > m²·V`** — ONE multiplier (`diff²`) + adders + a shift-and-add
  `bound = 9·V = (V<<3)+V` (m=3) + comparator per channel. Test uses the PRE-update μ,V.
  - **Guards:** warm-up counter suppresses flags until `warm_cnt >= TEDA_WARMUP`(8); the first
    valid sample PRIMES μ=x, V=0 (baseline starts at the real signal, not a 0-ramp that would
    inflate V for ~40 samples and mask the spike). Fixed **rail-stuck** check (`x==0||x==4095`)
    OR'd in as an always-on fast path so a dead sensor still trips instantly. Outputs
    `anomaly` (any channel) + `anom_ch[2:0]` (per-channel) are REGISTERED (1-cycle latency).
    All widths named params; fixed-point; wide (32-bit signed) sq/V/bound → no overflow.
  - **`adaptive_anomaly_tb.v`** feeds moisture at ~600±12 then a **660 spike (NOT a rail)**,
    nutrient/temp steady. Self-check: **RESULT PASS (0 errors)** — TEDA flags the spike on
    channel 0 ONLY (`anom_ch=001`) while the OLD fixed rail-check MISSES it; NO false flags in
    warm-up or on normal jitter; quiet again after the spike. Compiled+ran (`iverilog -o
    simulation.vvp adaptive_anomaly.v adaptive_anomaly_tb.v && vvp simulation.vvp`), VCD dumped.
  - **NOT yet wired into `analytics_engine`** — standalone module + its own tb for now.
    Replacing the engine's fixed rail check with this `anomaly`/`anom_ch` is a later
    integration step (bundled with 8C + the Phase-6 re-capture).
- **✅ Phase 8C DONE (JOINT / correlated fusion — `analytics_engine` upgraded in place):**
  modified `analytics_engine.v` ONLY; **port list UNCHANGED** (top still wires, 3 channels,
  NO humidity, frozen 17-field contract intact). Fusion upgraded from OR-of-thresholds →
  CORRELATED judgment:
  - New correlated conditions (feed `status`/`crop_health`, no new ports/events):
    `combined_dry_heat = dry_warn && hot_warn` (marginally dry AND marginally hot at once —
    each channel alone is sub-threshold/"fine", so an OR-of-thresholds engine MISSES it);
    `real_heat_stress = hot && moisture_falling` (heat WITH active drying → CRITICAL);
    `nutrient_crisis = low_nutrient && crop_health<HEALTH_CRISIS` (→ CRITICAL).
  - `crop_health` is now an **interaction-aware weighted score**: single penalties PLUS
    extra co-occurrence penalties (`PEN_DRY_HOT`=40, `PEN_DRY_NUT`=25, `PEN_COMBINED`=30) so
    combined stress costs MORE than the sum (e.g. dry+hot now 255−60−50−40=105, was 145).
    All weights + bands (`DRY_WARN`=260, `HOT_WARN`=360, `FALL_THRESH`=40, `HEALTH_CRISIS`=120)
    are named params, documented in `INTERFACES.md §5`. Still 0–255, clamped ≥0.
  - **Base single-channel outputs (`dry/low_nutrient/hot/cold/weed/anomaly`) + all event
    ids/priorities are UNCHANGED** — only their fusion into `crop_health`/`status` got smarter.
  - **REGRESSION PASSES:** re-ran the EXISTING `analytics_engine_tb.v` — all 8 original
    self-checks green (temp-compensated weed, dry-spell not-weed, heat, etc. unchanged).
    **ADDED a JOINT/FUSION phase** (ts 4300–5000: moisture 240 / temp 380 / nutrient 300):
    every base condition reads 0 (each channel individually "fine") yet `status`=WARNING(1)
    and `crop_health`=225 — the combination is flagged that independent thresholds would miss.
    **Compiled + ran: RESULT PASS (0 errors)** (`iverilog -o simulation.vvp analytics_engine.v
    analytics_engine_tb.v && vvp simulation.vvp`). Full-chip re-compile (top + `edge_analytics_tb.v`)
    also PASSES (0 alignment errors, valid 17-field CSV) — confirming the top still wires.
- **✅ INTEGRATION DONE (8A + 8F wired into the top):** modified **ONLY** `edge_analytics_top.v`
  + `edge_analytics_tb.v` (all RTL sub-modules frozen/untouched). `adaptive_anomaly` now runs in
  PARALLEL with `analytics_engine` (same smoothed set + `sm_valid`, lands t=3); `anomaly_merged =
  ae_anomaly | ta_anomaly` feeds `output_analytics.anomaly()` so `alert_anomaly` reflects BOTH
  detectors; `comms_tx` is a side channel on the t=4 event bus with a **TEDA-only-anomaly
  injection path** (`comms_event_id = oa_event_id!=NONE ? oa_event_id : ta_anomaly_rising ?
  SENSOR_ANOMALY(7) : NONE`, engine event always wins). New top ports: `out_msg_valid`,
  `out_alert_packet[63:0]`, `out_msg_count[15:0]`, `out_anom_ch[2:0]`. TB adds a `#`-prefixed
  caretaker-radio decoder + an INTEGRATION SUMMARY (D-line 17 fields / 0 align errs; ≥1 packet;
  msg_count ≪ samples), and a **Phase F nutrient-stuck-HIGH fault** (NS 56→66) that the engine's
  moisture-only rail check misses but TEDA catches → injected CHECK_SENSOR alert.
  **VERIFIED RESULT: PASS (0 errors)** — 66 samples, exactly **3 sparse caretaker packets**
  (FROST_RISK@0 warm-up, NUTRIENT_LOW@38 standard, ⭐ SENSOR_ANOMALY@56 via injection);
  the rail's 2nd edge @63 was rate-limit-suppressed. 17-field CSV stream stays clean.
- **NEXT ACTIONS (RESUME POINT):** Phases 1–5.5 + **8A + 8F + 8C + INTEGRATION** done. Continue
  Phase 8, still **do NOT do Phase 6 yet** (final capture is the LAST step, run ONCE on the
  feature-complete chip). Remaining build order:
  1. ✅ **8F TEDA** (`adaptive_anomaly.v`) — DONE, verified in isolation.
  2. ✅ **8C joint fusion** (`analytics_engine` `crop_health`+`status`) — DONE, regression + new fusion case pass.
  3. ✅ **INTEGRATION** — `adaptive_anomaly` + `comms_tx` wired into `edge_analytics_top` — DONE, verified.
  4. **← NEXT: 8D edge-win number** (now `msg_count` is REAL over the story trace: 3 packets /
     66 samples on-chip) — print-only in the tb, compute % data / radio-on saved vs streaming.
  5. **Regenerate schematic (8G)** — now shows the full feature-complete chip.
  6. **Phase 6** final capture on the canonical story-trace.

## 11. 🟣 EVALUATION FEEDBACK → DIFFERENTIATOR PIVOT (Phase 8 tier)
_A judge reviewed the project and said it's **"too common — just automation, no unique
factor,"** noting he'd worked on the same paper and there are other research papers to
draw from (user will supply them). He pushed hard on adding a **communication system to
a human caretaker** (a message telling them what to do), not only a dashboard. The user
initially countered "that's what the pump/fertilizer signals are for" — but those are
Tier-1 *actuation*, a different thing from Tier-2 *human notification*._

**Decision (agreed with user):** add a **DIFFERENTIATOR BONUS TIER** = `BUILD_PLAN.md`
Phase 8 (8A–8D), `INTERFACES.md` §6/§7, `FEATURES.md` "two-tier response" section:
- **8A `comms_tx` ⭐ (flagship):** event-triggered alert packet → remote caretaker with a
  **recommended action** (INSPECT_WEED / CHECK_SENSOR / …), rate-limited. THIS is the
  judge's point. Fires only for human-needed events; PUMP_ON/OFF stay local (Tier 1).
- **8B `predictor`:** divider-free slope extrapolation → PREDICT_DRY early warning
  (reuses the weed `dropped` primitive — cheap).
- **8C fusion strengthen:** fusion ALREADY exists (`crop_health` + temp-compensated weed);
  add humidity channel or weighted sum to make it a headline.
- **8D edge-win metric:** samples-processed vs packets-transmitted → % data/radio-on
  saved. Ties comms + "why edge" into ONE story: transmit K alerts, not N raw samples.

**Key framing to defend in the grill:** the chip has **two output tiers** — Tier 1 local
actuation (automation) + Tier 2 sparse remote comms (the exception-handling + the reason
edge analytics saves power). Real new RTL = just 2 modules (`comms_tx`, `predictor`);
8C is ~80% done, 8D is print-only.

**Pending:** (a) user wants a **grill session** on this plan (not yet run); (b) judge's
**reference papers** will land and may retune thresholds/packet layout — all such
constants are named `parameter`s flagged "TUNE" in `INTERFACES.md` §5/§7. Do NOT write
Phase 8 RTL until the grill + papers are in unless the user says go.

### Grill-session decisions (locked in — session of the pivot)
1. **Differentiator = triage + quantified sparseness**, NOT "it sends a message." Pitch the
   on-chip decision of *whether a human is needed* + the ~85–93% fewer transmissions.
   Demote "sends a message" to a delivery detail.
2. **Two physically distinct links.** Local telemetry (dashboard §3, cheap/wired/on-site,
   streams every sample = fine) vs long-range caretaker radio (`comms_tx` §6, battery,
   sparse). **The 85% edge-win applies ONLY to the caretaker link** — always label it so;
   pre-empts "but your dashboard streams everything" attack. (Slide saved in PRESENTATION.)
3. **Unique IMPLEMENTATION** (judge's real bar) = two layers: (a) framing — analytics as
   dedicated silicon, which NO surveyed paper does (all software on Pi/ESP32/cloud); (b)
   substance — deepen the RTL beyond comparators so it survives inspection: **joint/
   correlated fusion (8C)** + **TEDA self-tuning anomaly (8F)**. "It's in Verilog" alone
   is NOT enough — a judge who opens `if(x<200)` says "trivial."
4. **TEDA = the method that implements self-tuning anomaly** (not an extra feature). One
   small block. Fallback-if-time item (most math-y), but 15h left → comfortable.
5. **Visualization gap (Phase 8G):** must SHOW the chip like rival teams — waveforms
   (have) + block diagram + **synthesized schematic** (Vivado RTL schematic OR local Yosys
   `brew install yosys`). Schematic = biggest missing artifact; highest "it's real silicon" impact.
   - ✅ **DONE (baseline):** Yosys+graphviz installed; generated `docs/schematic/
     chip_block_diagram.{svg,png,dot}` for the CURRENT chip (Phases 1–5) — shows the 4
     sub-blocks (sensor_collector → smoothing_stage → analytics_engine → output_analytics)
     wired as a pipeline with the latency-alignment delay registers.
   - ✅ **Baseline synth numbers** (Yosys generic, pre-Phase-8): **1601 cells, ~867
     flip-flops, ~727 logic gates, 857 wires.** On Artix-7 xc7a35t (~41.6k FFs) that's
     ~2% of FFs → the "tiny, lightweight edge IP" story is real. NOTE: these are Yosys
     generic-synth counts, NOT Vivado LUT-mapped — Vivado gives exact LUT/Fmax/power.
   - **Judge said "FPGA"** → FPGA synthesis (schematic + utilization/timing/power) is
     ELEVATED from bonus to expected. Regenerate schematic after Phase 8 modules land.
   - **RESOLVED: NO physical FPGA board on the team → Level 1 only** (FPGA *synthesis*
     reports + schematic; NO live-board/LED demo). This FULLY satisfies the judge's "FPGA"
     ask — simulation + FPGA synthesis (Vivado/Quartus utilization/timing/power + schematic)
     is a complete hardware story without any board. Do NOT chase a board demo. FPGA
     deliverable = (a) Yosys schematic ✅ done on Mac, (b) Vivado/Quartus reports from the
     synthesis teammate on Windows (exact LUT/Fmax/power + Vivado's own schematic).
6. **NO humidity channel** — would break the frozen 17-field dashboard contract; make
   fusion smarter, not wider.
7. **Acres-of-land scale — RESOLVED (option a):** FRAME it, don't build a multi-node net.
   - *Level 1 (why silicon):* at 1000s of nodes, cost+power/node dominate — a Pi (watts,
     $35) can't scale; a µW/cents custom IP is the only option. This is the real "why hardware."
   - *Level 2 (TEDA is a scale enabler):* can't hand-tune thresholds for 1000s of nodes over
     varied soil/sun/slope → each node MUST self-calibrate → TEDA (8F) is necessity, not bonus.
   - *Level 3 (the "new" idea, future-work slide only):* SPATIAL/cross-node anomaly ("this
     zone depletes faster than its neighbours" → weed patch / line leak / disease front) +
     cluster-head aggregation (avoid a radio storm when many nodes alarm at once). Present
     as future architecture; do NOT build the network. (Optional cheap hook we declined:
     a `field_avg` deviation comparator in one node.)
8. **Anomaly detection HOW (asked explicitly):** TEDA reduces to `(x−μ)² > m²·V`, divider-
   free; μ,V are EMA-updated state registers (shift, not divide); 1 multiplier + adders +
   comparator per channel. Full datapath in BUILD_PLAN 8F. Team is "VLSI Veriyans" — this
   block is the drawable-as-a-real-circuit centrepiece (feedback state + multiplier), unlike
   a bare comparator threshold. Deliverable is a real chip; Phase 8 is all RTL + 8G schematic.

**Papers gathered → `edge_analytics/papers/PAPERS.md`** (catalogued + tagged to features).
User pasted 7 (mostly edge/IoT-agri surveys + 2 common-baseline IoT builds). Gap was: NO
hardware/VLSI papers and none on event-triggered comms. Filled via web search — added 3
open-access PDFs (TEDA FPGA streaming-anomaly hardware; edge-greenhouse fusion anomaly;
rogue-soil-moisture-sensor detection) and the ⭐ key citation **Lozoya et al. 2021, MDPI
Sensors 21(16):5541** (event-triggered irrigation comms: **>85% fewer messages, ~20% less
power** — the quantified proof of our Tier-2/edge-win story; user must download it manually,
MDPI blocks scripts). See PAPERS.md for the differentiation narrative + reading priority.
