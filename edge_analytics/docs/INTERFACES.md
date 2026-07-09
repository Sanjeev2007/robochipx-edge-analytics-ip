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

## 3. Live stream format (chip → dashboard)  — REAL-TIME, no file

The top-level testbench `$display`s these lines to stdout. Run:
```
vvp simulation.vvp | python3 dashboard.py
```
Python reads each line live and updates the real-time dashboard.

**Two line types**, tagged by the first field:

**`D` — data line (printed every valid cycle → charts + gauges):**
```
D,<timestamp>,<moisture>,<nutrient>,<temp>,<avg_moisture>,<avg_nutrient>,<avg_temp>,<pump_on>,<status>,<crop_health>
```
Example: `D,65000,180,300,410,300,305,408,1,1,120`

**`E` — event line (printed only when an event fires → timestamped event log):**
```
E,<timestamp>,<EVENT_NAME>
```
Examples: `E,65000,PUMP_ON`  `E,120000,WEED_DETECTED`  `E,150000,NUTRIENT_LOW`

### Field glossary
**D line fields:**
| Field | Range | Source | Meaning |
|---|---|---|---|
| `D` | literal | testbench | tag = data line → dashboard charts |
| `timestamp` | 0..~4e9 (32-bit) | `sensor_collector` | clock-cycle counter since reset (= "when") |
| `moisture` | 0–4095 | moisture sensor (ch0) | RAW soil water reading (noisy) |
| `nutrient` | 0–4095 | NPK sensor (ch1) | RAW nutrient level (noisy) |
| `temp` | 0–4095 | temp sensor (ch2) | RAW temperature (noisy) |
| `avg_m` | 0–4095 | `moving_avg` ch0 | SMOOTHED moisture — decisions use THIS |
| `avg_n` | 0–4095 | `moving_avg` ch1 | SMOOTHED nutrient |
| `avg_t` | 0–4095 | `moving_avg` ch2 | SMOOTHED temperature |
| `pump` | 0/1 | `output_analytics` | pump 1=ON, 0=OFF |
| `status` | 0/1/2 | `analytics_engine` | 0=SAFE, 1=WARNING, 2=CRITICAL |
| `health` | 0–255 | `analytics_engine` | fused crop-health score (higher=healthier) |

**E line fields:** `E` (tag = event line), `timestamp` (when it fired), `EVENT_NAME` (one of the 8 in §4).

**Notes:**
- Values are RAW digital counts (0–4095), not physical units. The dashboard scales
  them for display (e.g. moisture 0–4095 → 0–100%, temp 0–4095 → 0–50°C).
- Both RAW and SMOOTHED are streamed so the dashboard can plot them together —
  the jagged-vs-smooth comparison visually proves the moving-average filter works.
- Fully decoded example — `D,65000,175,300,380,180,305,378,1,1,150` + `E,65000,PUMP_ON`:
  at cycle 65000, smoothed moisture 180 is below the 200 dry threshold, so the pump
  just turned ON; status WARNING, health 150/255.

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
