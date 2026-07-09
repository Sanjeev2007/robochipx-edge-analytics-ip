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
| anomaly | — | rail-stuck: `avg_moisture == 0 \|\| avg_moisture == 4095` (adaptive version = Phase 8) |

**crop_health penalties** (start 255, subtract, clamp ≥0): dry −60, low_nutrient −50,
hot −50, cold −50, weed −80, anomaly −40.

**status:** CRITICAL(2) if `weed | anomaly | cold | (dry+low_nutrient+hot+cold)>=2`;
else WARNING(1) if exactly one mild condition; else SAFE(0).
