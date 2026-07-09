# Interface Contract (Phase 0) — FREEZE THIS

> This is the shared contract every teammate builds against. **Change it rarely
> and announce loudly** — B synthesizes against it, C's dashboard parses the stream
> format, D diagrams it. Status: **DRAFT — pending team lead approval.**

---

## 1. Global constants (same everywhere)
| Name | Value | Meaning |
|---|---|---|
| `DATA_WIDTH` | 12 | bits per sensor sample (range 0–4095) |
| `NUM_CH` | 3 | number of sensor channels |
| `CH_WIDTH` | 2 | bits for channel id (fits up to 4 channels) |
| `LOG2_N` | 3 | moving-average window = 2^3 = 8 samples |
| `TS_WIDTH` | 32 | timestamp = free-running clock-cycle counter |
| `STATUS_WIDTH` | 2 | 0=SAFE, 1=WARNING, 2=CRITICAL |
| `HEALTH_WIDTH` | 8 | crop-health score 0–255 |

**Channel ids:** `0 = moisture`, `1 = nutrient (NPK)`, `2 = temperature`.

---

## 2. Module boundary signals

### `sensor_collector` (produces the aligned, timestamped sample set)
Design choice: **parallel** channels (all 3 emitted together each cycle), so the
whole pipeline stays aligned and the `D` stream line can carry all 3 at once.
| Dir | Signal | Width | Meaning |
|---|---|---|---|
| in | `clk`, `rst` | 1 | clock, sync active-high reset |
| in | `moisture_in`, `nutrient_in`, `temp_in` | 12 | the 3 raw sensor readings |
| in | `sensors_valid` | 1 | 1 = new readings this cycle |
| out | `moisture`, `nutrient`, `temp` | 12 | registered, aligned raw readings |
| out | `timestamp` | 32 | cycle count when this set was captured |
| out | `sample_valid` | 1 | 1 = outputs valid this cycle |

### `moving_avg` (one instance per channel — ALREADY BUILT)
| Dir | Signal | Width |
|---|---|---|
| in | `clk`, `rst`, `sample_valid` | 1 |
| in | `sample_in` | 12 |
| out | `avg_out` | 12 |
| out | `avg_valid` | 1 |

### `analytics_engine` (decisions + event timestamps)
| Dir | Signal | Width | Meaning |
|---|---|---|---|
| in | `clk`, `rst` | 1 | |
| in | `avg_moisture`, `avg_nutrient`, `avg_temp` | 12 | smoothed channels |
| in | `timestamp` | 32 | current time |
| in | `in_valid` | 1 | inputs valid |
| out | `dry`, `low_nutrient`, `hot`, `cold`, `weed`, `anomaly` | 1 | detected conditions |
| out | `status` | 2 | overall SAFE/WARNING/CRITICAL |
| out | `crop_health` | 8 | fused health score |
| out | `event_id` | 4 | which event fired (0=none, see §4) |
| out | `event_timestamp` | 32 | time the event fired |
| out | `out_valid` | 1 | outputs valid |

### `output_analytics` (registered actuator/alert bus)
| Dir | Signal | Width | Meaning |
|---|---|---|---|
| in | `clk`, `rst`, `in_valid` | 1 | clock, reset, = analytics_engine `out_valid` |
| in | (all analytics_engine decision outputs) | | `dry`,`low_nutrient`,`hot`,`cold`,`weed`,`anomaly`,`status_in`,`crop_health_in`,`event_id_in`,`event_timestamp_in` |
| in | `avg_moisture` | 12 | **(Phase 4 add)** smoothed moisture — needed to test `> PUMP_OFF_THRESH` for hysteresis |
| in | `timestamp` | 32 | **(Phase 4 add)** current time — needed to stamp generated PUMP_ON/PUMP_OFF events |
| out | `pump_on` | 1 | irrigation (with hysteresis) |
| out | `dose_nutrient` | 1 | fertilizer doser |
| out | `alert_weed`, `alert_heat`, `alert_frost`, `alert_nutrient`, `alert_anomaly` | 1 | alerts |
| out | `status` | 2 | overall status |
| out | `crop_health` | 8 | health score |
| out | `event_id` | 4 | current event |
| out | `event_timestamp` | 32 | its timestamp |
| out | `out_valid` | 1 | |

### `predictor` (Phase 8B — predictive watering, divider-free)   ⬜ planned
| Dir | Signal | Width | Meaning |
|---|---|---|---|
| in | `clk`, `rst`, `in_valid` | 1 | |
| in | `avg_moisture` | 12 | smoothed moisture (same source as analytics_engine) |
| in | `dropped` | 12 | moisture fall over `HIST_DEPTH` samples (the weed primitive, reused) |
| in | `timestamp` | 32 | current time (to stamp the PREDICT_DRY event) |
| out | `predict_dry` | 1 | 1 = heading below `DRY_THRESH` within `LEAD` samples |
| out | `event_id` | 4 | `PREDICT_DRY`(9) on the 0→1 edge of `predict_dry`, else 0 |
| out | `event_timestamp` | 32 | time the prediction fired |
| out | `out_valid` | 1 | |

> Extrapolation is **divider-free**: `projected = avg_moisture - (dropped*LEAD >> LOG2_HIST)`;
> `predict_dry = (avg_moisture >= DRY_THRESH) && (projected < DRY_THRESH)`. `LEAD` = TUNE.

### `comms_tx` (Phase 8A — event-triggered caretaker communication)   ⭐ ⬜ planned
The chip's **second output tier**: a sparse, event-triggered alert channel to a REMOTE
caretaker (radio/LoRa/GSM gateway), separate from the continuous dashboard telemetry (§3).
| Dir | Signal | Width | Meaning |
|---|---|---|---|
| in | `clk`, `rst`, `in_valid` | 1 | |
| in | `event_id` | 4 | current event from `output_analytics` (0=none) |
| in | `event_timestamp` | 32 | its timestamp |
| in | `status` | 2 | overall status (for severity) |
| in | `crop_health` | 8 | fused health score (rides in the packet) |
| out | `msg_valid` | 1 | 1-cycle strobe: a packet is being transmitted THIS cycle |
| out | `alert_packet` | 64 | packed {severity, event_code, action_code, event_timestamp, crop_health} — see §6 |
| out | `msg_count` | 16 | running tally of transmitted packets (feeds the Phase 8D edge-win math) |
| out | (opt) `tx_byte`,`tx_strobe` | 8,1 | stretch: UART-serialized bytes of `alert_packet` |

> Fires ONLY for **human-needed** events (WEED_DETECTED, SENSOR_ANOMALY, NUTRIENT_LOW
> w/o doser, STATUS_CRITICAL, FROST_RISK, PREDICT_DRY). Machine-handled events
> (PUMP_ON/OFF) do NOT transmit. A `MSG_GAP` (TUNE) rate-limit blocks same-event spam.

### `edge_analytics_top` — Phase-8 caretaker/anomaly outputs (INTEGRATION)   ✅ wired
The top level now instantiates `adaptive_anomaly` (8F) in parallel with the engine and
`comms_tx` (8A) as a side channel. These outputs are IN ADDITION to the aligned D-line
bundle; they are **NOT** part of the frozen 17-field CSV row (§3) — that contract is
unchanged. See `edge_analytics_top.v` header for the full latency map.
| Dir | Signal | Width | Meaning |
|---|---|---|---|
| out | `out_anom_ch` | 3 | per-channel TEDA flags (bit c = channel c); delayed +1 so it sits on the t=4 alert-bus cycle — for waveforms/debug |
| out | `out_msg_valid` | 1 | 1-cycle strobe: a caretaker packet is being transmitted (Tier-2 radio) |
| out | `out_alert_packet` | 64 | the 64-bit caretaker alert packet (layout §6) |
| out | `out_msg_count` | 16 | running tally of transmitted caretaker packets (feeds Phase 8D) |

> **Timing:** `comms_tx` is the **async caretaker radio** — its outputs land **+1 vs the
> aligned D-bundle** (t=5, vs the D row at t=4). This is intentional; the packet is a
> sparse Tier-2 alert, deliberately NOT aligned into the 17-field telemetry row.
> **Anomaly merge:** `output_analytics.anomaly` is now fed `ae_anomaly | ta_anomaly`
> (engine rail check OR the TEDA detector). **Injection:** a TEDA-only anomaly (one the
> engine's moisture-only rail check misses) is surfaced to the radio as `SENSOR_ANOMALY`
> only when the merged pipeline reports NONE — the engine/output event always wins.

---

## 3. Live stream format (chip → dashboard)  — 17-field CSV, REAL-TIME, no file

> **Phase 5.5 reconciliation:** we adopted the dashboard teammate's contract
> (`robochipx_dashboard_handoff/VERILOG_DASHBOARD_CONTRACT.md`) so their finished UI
> works unchanged. The old two-line `D`/`E` format is REPLACED by **one 17-field CSV
> row per valid output cycle**, with a header line printed once. **This is a
> TESTBENCH-ONLY change — no `.v` module was modified.** Raw sensor COUNTS (0–4095)
> are SCALED to display units in `edge_analytics_tb.v` before printing.

The top-level testbench `$display`s a header once, then one row per `out_valid`
cycle. Run:
```
vvp simulation.vvp | python3 edge_agri_dashboard.py
```

**Header (printed once):**
```
timestamp,moisture_raw,nutrient_raw,temp_raw,moisture_avg,nutrient_avg,temp_avg,pump_on,dose_nutrient,alert_nutrient,alert_weed,alert_heat,alert_frost,alert_anomaly,status,crop_health,relocate_recommend
```

**Row (one per valid cycle):**
```
<timestamp>,<moisture_raw>,<nutrient_raw>,<temp_raw>,<moisture_avg>,<nutrient_avg>,<temp_avg>,<pump_on>,<dose_nutrient>,<alert_nutrient>,<alert_weed>,<alert_heat>,<alert_frost>,<alert_anomaly>,<status>,<crop_health>,<relocate_recommend>
```
Example: `24,26,60,25,39,60,25,1,0,0,0,0,0,0,1,76,0`

### Field glossary (17 fields, in order)
| # | Field | Range | Source (RTL count → display) | Meaning |
|---|---|---|---|---|
| 1 | `timestamp` | 0..~4e9 (32-bit) | `sensor_collector` (pass-through) | clock-cycle counter since reset (= "when") |
| 2 | `moisture_raw` | 0–100 | moisture ch0, count/5 clamp 0–100 | RAW soil water (noisy), scaled |
| 3 | `nutrient_raw` | 0–100 | NPK ch1, count/5 clamp 0–100 | RAW nutrient (noisy), scaled |
| 4 | `temp_raw` | ~0–50 | temp ch2, count/10 | RAW temperature °C-ish, scaled |
| 5 | `moisture_avg` | 0–100 | `moving_avg` ch0, count/5 clamp 0–100 | SMOOTHED moisture — decisions use THIS |
| 6 | `nutrient_avg` | 0–100 | `moving_avg` ch1, count/5 clamp 0–100 | SMOOTHED nutrient |
| 7 | `temp_avg` | ~0–50 | `moving_avg` ch2, count/10 | SMOOTHED temperature |
| 8 | `pump_on` | 0/1 | `output_analytics` (pass-through) | irrigation 1=ON, 0=OFF |
| 9 | `dose_nutrient` | 0/1 | `output_analytics` (pass-through) | fertilizer doser |
| 10 | `alert_nutrient` | 0/1 | `output_analytics` (pass-through) | low NPK warning |
| 11 | `alert_weed` | 0/1 | `output_analytics` (pass-through) | resource-theft / weed anomaly |
| 12 | `alert_heat` | 0/1 | `output_analytics` (pass-through) | heat-stress warning |
| 13 | `alert_frost` | 0/1 | `output_analytics` (pass-through) | frost-risk warning |
| 14 | `alert_anomaly` | 0/1 | `output_analytics` (pass-through) | sensor fault / stuck reading |
| 15 | `status` | 0/1/2 | `analytics_engine` (numeric) | 0=SAFE, 1=WARNING, 2=CRITICAL (dashboard maps to names) |
| 16 | `crop_health` | 0–100 | `analytics_engine`, health*100/255 | fused crop-health score (higher=healthier) |
| 17 | `relocate_recommend` | 0/1 | testbench derive | 1 when `status==2 && crop_health<35` (still critical despite action) |

### Scaling formulas (applied in `edge_analytics_tb.v` — tunable defaults)
- `moisture_raw/avg`, `nutrient_raw/avg` = `count / 5`, clamped 0–100
  (dry@200 ≈ 40, pump-off@350 ≈ 70).
- `temp_raw/avg` = `count / 10` (hot@400 ≈ 40°C, cold@100 ≈ 10°C).
- `crop_health` = `health * 100 / 255` (wide `integer` multiply first, no truncation).
- `status` stays numeric 0/1/2; `pump_on`/`dose_nutrient`/`alert_*` pass through 0/1.
- `relocate_recommend` = `1` when `status==2 && crop_health_scaled < 35`, else `0`.
- The data teammate's calibration can later refine these divisors.

**Notes:**
- The RTL still computes in raw digital counts (0–4095); scaling to display units
  happens ONLY in the testbench print. The chip is unchanged.
- Both RAW and SMOOTHED columns are streamed so the dashboard plots them together —
  the jagged-vs-smooth comparison visually proves the moving-average filter works.
- Event ids/names (§4) are still generated inside the RTL (`event_id`/`event_timestamp`);
  the dashboard derives its event log from the alert/pump columns in each row, so a
  separate `E` line is no longer streamed.
- The dashboard parser skips the header, accepts numeric CSV (or key=value debug
  tokens), and maps `status` 0/1/2 → SAFE/WARNING/CRITICAL.
- **UNCHANGED by the Phase-8 INTEGRATION:** wiring `adaptive_anomaly` + `comms_tx` into the
  top added NEW top-level ports (§2 `edge_analytics_top` table) but did **NOT** alter this
  17-field row — same field order/count. The caretaker radio prints only on `#`-prefixed
  monitor lines (which the parser skips), so the piped stream stays pure 17-field CSV.

---

## 4. Event ids / names (shared by RTL `event_id` and stream `E` lines)
| id | name | meaning |
|---|---|---|
| 0 | NONE | no event |
| 1 | PUMP_ON | irrigation started |
| 2 | PUMP_OFF | irrigation stopped |
| 3 | WEED_DETECTED | abnormal depletion, normal temp |
| 4 | NUTRIENT_LOW | nutrient below threshold |
| 5 | HEAT_STRESS | temperature too high |
| 6 | FROST_RISK | temperature too low |
| 7 | SENSOR_ANOMALY | faulty/abnormal sensor |
| 8 | STATUS_CRITICAL | overall crop health critical |
| 9 | PREDICT_DRY | predicted dry-out ahead of time (Phase 8B early warning) |

---

## 5. Thresholds & analytics params (initial guesses — tune with the story trace)
| Name | Value | Rule / meaning |
|---|---|---|
| `DRY_THRESH` | 200 | dry = `avg_moisture < 200` |
| `PUMP_OFF_THRESH` | 350 | pump hysteresis: stays on until `avg_moisture > 350` |
| `NUT_THRESH` | 250 | low_nutrient = `avg_nutrient < 250` |
| `HOT_THRESH` | 400 | hot = `avg_temp > 400` |
| `COLD_THRESH` | 100 | cold = `avg_temp < 100` |
| `HIST_DEPTH` | 4 | how many valid-samples back the weed detector compares moisture |
| `RATE_THRESH` | 100 | weed = moisture dropped > 100 counts over `HIST_DEPTH` samples AND `not hot` |
| anomaly | — | v1 rail-stuck: `avg_moisture == 0 \|\| avg_moisture == 4095`. **Phase 8F replaces/augments this with a self-tuning TEDA detector** (running μ+σ², Chebyshev eccentricity, divider-free) — see §7 `TEDA_*` params |

**crop_health = INTERACTION-AWARE weighted score (Phase 8C).** Start 255, subtract the
single-channel penalties, THEN subtract extra penalties when stresses CO-OCCUR (so a
combined stress costs MORE than the sum of its parts), clamp ≥0. All weights are named
`analytics_engine` parameters:
| Weight | Value | Applies when |
|---|---|---|
| `PEN_DRY` | 60 | `dry` |
| `PEN_NUT` | 50 | `low_nutrient` |
| `PEN_HOT` | 50 | `hot` |
| `PEN_COLD` | 50 | `cold` |
| `PEN_WEED` | 80 | `weed` |
| `PEN_ANOM` | 40 | `anomaly` |
| `PEN_DRY_HOT` | 40 | `dry && hot` (drought + heat compound — extra on top of the two singles) |
| `PEN_DRY_NUT` | 25 | `dry && low_nutrient` (dry roots can't take up NPK) |
| `PEN_COMBINED` | 30 | `combined_dry_heat` (sub-threshold joint stress, below) |

**Phase 8C joint / correlated fusion params + conditions** (named `analytics_engine`
parameters; decisions depend on channel *combinations*, not each sensor alone):
| Name | Value | Rule / meaning |
|---|---|---|
| `DRY_WARN` | 260 | "getting dry" band: `DRY_THRESH ≤ avg_moisture < DRY_WARN` (implies `!dry`) |
| `HOT_WARN` | 360 | "getting warm" band: `HOT_WARN < avg_temp ≤ HOT_THRESH` (implies `!hot`) |
| `FALL_THRESH` | 40 | moisture "falling" if `dropped` over `HIST_DEPTH` > this (gentler than `RATE_THRESH`) |
| `HEALTH_CRISIS` | 120 | crop_health below this ⇒ plant already struggling |

- `combined_dry_heat = dry_warn && hot_warn` — marginally dry AND marginally hot at once.
  Each channel alone reads "fine" (no hard threshold crossed), so an OR-of-thresholds
  detector misses it; only the JOINT view flags it (→ at least WARNING, `PEN_COMBINED`).
- `real_heat_stress = hot && moisture_falling` — heat that arrives WITH active drying
  (genuine stress, not a lone warm reading) → escalates status to CRITICAL.
- `nutrient_crisis = low_nutrient && (crop_health < HEALTH_CRISIS)` — nutrient low while
  the crop is already struggling (fused with the health score) → escalates to CRITICAL.

**status (Phase 8C escalation):** CRITICAL(2) if `weed | anomaly | cold |
(dry+low_nutrient+hot+cold)>=2 | real_heat_stress | nutrient_crisis`; else WARNING(1) if
exactly one mild condition **or** `combined_dry_heat`; else SAFE(0). (Base ids/events and
the single-channel condition outputs `dry/low_nutrient/hot/cold/weed/anomaly` are
UNCHANGED — only the fusion of them into `crop_health`/`status` got smarter.)

---

## 6. Comms / caretaker-alert packet (Phase 8A `comms_tx`)  — the SECOND output tier

> **Two output tiers (the "beyond automation" story):**
> - **Tier 1 — local actuation** (`pump_on`, `dose_nutrient`): machine-to-machine,
>   handles routine problems on-chip, no message sent.
> - **Tier 2 — remote comms** (`alert_packet`): machine-to-human, event-triggered,
>   sent to the caretaker only for exceptions a machine shouldn't handle alone.
> Streaming continuous telemetry (§3) is for the LOCAL dashboard; the comms packet is
> the SPARSE, over-the-air alert. Transmitting K packets instead of N raw samples is the
> quantified edge power/bandwidth win (Phase 8D).

**`alert_packet` layout (64-bit, MSB→LSB):**
| Field | Width | Meaning |
|---|---|---|
| `severity` | 4 | 1=INFO, 2=WARNING, 3=CRITICAL (derived from `status`/`event_id`) |
| `event_code` | 4 | the triggering `event_id` (§4) |
| `action_code` | 4 | recommended caretaker action (table below) |
| `crop_health` | 8 | fused health score at time of alert |
| `reserved` | 12 | 0 for now (future: zone id / sensor id) |
| `event_timestamp` | 32 | when it fired |

**`action_code` — what the caretaker is told to DO** (this is the judge's point made concrete):
| code | name | fires for | caretaker action |
|---|---|---|---|
| 0 | NONE | — | (no message) |
| 1 | INSPECT_WEED | WEED_DETECTED | go check the zone / remove the weed |
| 2 | CHECK_SENSOR | SENSOR_ANOMALY | a sensor is faulty — inspect/replace |
| 3 | MANUAL_FERTILIZE | NUTRIENT_LOW (no doser fitted) | top up nutrients manually |
| 4 | PROTECT_FROST | FROST_RISK | deploy cover/heater |
| 5 | RELOCATE_OR_REVIEW | STATUS_CRITICAL (persists) | environment unsuitable — review/relocate |
| 6 | PRE_IRRIGATE | PREDICT_DRY | dry-out predicted soon — check pump/water supply |

> **Which events notify vs stay local:** PUMP_ON/PUMP_OFF are Tier-1 (handled by the
> pump, no packet). Everything in the `action_code` table is Tier-2 (packet sent). This
> split IS the answer to "it's just automation": automation acts; comms escalates.

---

## 7. New bonus-tier params (Phase 8 — all named, all TUNE-able)
| Name | Value (start) | Rule / meaning |
|---|---|---|
| `LEAD` | 4 | predictor projects moisture this many samples ahead (Phase 8B) |
| `LOG2_HIST` | 2 | `= log2(HIST_DEPTH)`; makes `dropped>>LOG2_HIST` ≈ per-sample slope |
| `MSG_GAP` | 8 | comms rate-limit: min valid-cycles before the SAME event re-transmits |
| `RAW_PKT_BYTES` | 12 | assumed bytes if we streamed each raw sample to cloud (edge-win math) |
| `ALERT_PKT_BYTES` | 8 | bytes per transmitted alert packet (edge-win math) |
| `TEDA_SIGMA_M` | 3 | Phase 8F: anomaly if `(x−μ)² > m²·V` (m = sigma multiplier; Chebyshev) |
| `TEDA_ALPHA` | 3 | Phase 8F: EMA shift for μ/V update (`>>α` ⇒ weight 1/2^α = 1/8); larger α = slower/steadier baseline |
| `TEDA_WARMUP` | 8 | Phase 8F: suppress anomaly flags until this many samples seen (μ/V warm-up) |

> **Phase 8C fusion:** stays at `NUM_CH=3` — we do NOT add a humidity channel (it would
> break the frozen 17-field dashboard contract §3). Fusion is made unique by making the
> *logic* correlated/joint (see BUILD_PLAN 8C), not by adding channels. `crop_health`
> becomes an interaction-aware weighted score (combined stress penalised more than the sum).

> These are **provisional** — expect tuning after the grill session and the judge's
> reference papers. Keep them as Verilog `parameter`s, never hard-coded literals.
