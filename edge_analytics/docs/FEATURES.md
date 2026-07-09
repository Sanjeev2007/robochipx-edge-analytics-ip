# Features — Smart Agriculture Edge Analytics IP

## The core principle: **detect → decide → act, autonomously, on-device**

This is what makes it *edge* analytics, not just monitoring. A cloud system would
sense a problem, send the data to a server, wait for a decision, and send a command
back — seconds of delay, dependent on network, power, and privacy. Our chip does the
full loop **locally, in microseconds, with no cloud**:

```
   SENSE  ──►  SMOOTH  ──►  DECIDE  ──►  ACT
 (sensors)  (moving avg) (analytics)  (drive actuators / alerts)
```

Every feature below is a closed loop: the chip senses a condition, confirms it is
real (not sensor noise), and **automatically fires a control signal** to fix it or
raise an alert — all on-chip.

---

## Feature showcase — what it detects and how it auto-responds

| # | Condition detected | How it's detected (on-chip) | Automatic response | Output signal | Why edge matters here |
|---|---|---|---|---|---|
| 1 | **Dry soil** | Smoothed moisture drops below threshold | **Turns on the irrigation pump**, waters until moisture recovers, then shuts off | `pump_on` | Instant watering; no missed window waiting on a server |
| 2 | **Weed / resource theft** | Moisture/nutrient depleting *faster than the learned baseline* **while temperature is normal** (temp-compensated so a hot day isn't mistaken for a weed) | Raises weed alert; flags the zone for removal; can stop over-watering that feeds the weed | `alert_weed` | Catches a competitor early, before it starves the crop |
| 3 | **Low nutrients** | Smoothed nutrient (NPK) level below threshold | Triggers the fertilizer doser (if fitted), else alerts the farmer | `dose_nutrient` / `alert_nutrient` | Feeds the crop the moment it's hungry |
| 4 | **Heat stress** | Smoothed temperature above high threshold | Increases irrigation for evaporative cooling / activates mist/shade | `alert_heat` (+ can boost `pump_on`) | Protects the crop during a heat spike in real time |
| 5 | **Frost risk** | Smoothed temperature below low threshold | Raises frost alert / activates heater or cover | `alert_frost` | Frost damage happens fast — local reaction beats cloud latency |
| 6 | **Sensor fault / abnormal reading** | Adaptive anomaly detector: value beyond `mean ± k·deviation`, or a stuck/flatlined sensor | Flags the bad sensor and ignores it, falling back safely | `alert_anomaly` | Prevents acting on garbage data (e.g. a broken sensor) |
| 7 | **Overall poor plant health** | Fusion of moisture + nutrient + temperature into a single crop-health score | Sets an overall status; if CRITICAL, recommends relocating the plant | `status[1:0]`, `crop_health`, `relocate_recommend` | One clear verdict instead of raw numbers |

---

## Per-feature detail

### 1. Auto-irrigation (the flagship closed loop)
- **Detect:** the moving-average filter smooths the jittery soil sensor; if the
  *smoothed* value crosses the dry threshold, it's a real dry-out, not noise.
- **Act:** assert `pump_on`. Uses **hysteresis** — water until moisture reaches a
  comfortable upper level, then stop — so the pump doesn't rapidly flick on/off.
- **Edge value:** the plant is watered the instant it needs it, even if the network
  is down.

### 2. Weed detection & response
- **Detect:** a weed is an *extra consumer* — so resources drop faster than the
  learned normal rate. Temperature-compensated so evaporation on a hot day isn't a
  false alarm (`fast depletion + normal temp = weed`; `+ high temp = evaporation`).
- **Act:** raise `alert_weed`; flag the zone. In a fuller system this can dispatch a
  robotic weeder / targeted micro-dose, or throttle irrigation so the weed doesn't
  get fed. (The chip's job is to *detect and signal*; the physical removal is the
  actuator it drives.)
- **Edge value:** on-device rate analysis catches theft early, before yield is lost.

### 3. Nutrient management
- **Detect:** smoothed NPK level below threshold.
- **Act:** open the fertilizer dosing valve (`dose_nutrient`) if present, else
  `alert_nutrient` for a manual top-up.

### 4 & 5. Climate protection (heat / frost)
- **Detect:** smoothed temperature crosses the high or low threshold.
- **Act:** heat → more irrigation / mist / shade (`alert_heat`); frost →
  heater/cover (`alert_frost`).
- **Edge value:** temperature emergencies unfold in minutes; local reaction wins.

### 6. Self-checking (adaptive anomaly detection = "AI at the edge")
- **Detect:** the chip *learns* each sensor's normal mean and variability and flags
  anything outside `mean ± k·deviation`, plus stuck/flatlined or impossible values.
- **Act:** mark the sensor bad, ignore it, keep running on the others (`alert_anomaly`).
- **Edge value:** the system stays trustworthy even when a sensor breaks.

### 7. Crop-health fusion & relocation advice
- **Detect:** combine all channels into one crop-health score.
- **Act:** publish `status` (SAFE / WARNING / CRITICAL); if consistently CRITICAL
  despite watering and feeding, recommend the plant be relocated
  (`relocate_recommend`) — the environment itself may be unsuitable.

---

## Signal summary

**Sensor inputs**
- `moisture` — soil water content
- `nutrient` — NPK level
- `temperature` — soil/air temperature
- *(optional extra channels: humidity, light, a gap-moisture sensor for cleaner weed detection)*

**Automatic outputs (the "fixes")**
- `pump_on` — irrigation valve/pump
- `dose_nutrient` — fertilizer doser
- `alert_weed` — resource-theft / weed
- `alert_heat`, `alert_frost` — climate protection
- `alert_nutrient` — low nutrients (manual path)
- `alert_anomaly` — sensor fault / abnormal
- `status[1:0]` — SAFE / WARNING / CRITICAL
- `crop_health` — fused health score
- `relocate_recommend` — suggest moving the plant

---

## Autonomy & safety notes
- **Hysteresis** on the pump (and any actuator) prevents rapid on/off oscillation.
- **Smoothing before acting:** the chip only acts on a *confirmed trend* from the
  moving-average filter, never on a single noisy spike — no false triggering.
- **Fail-safe:** a flagged/faulty sensor is ignored, not obeyed.
- **Manual override / alert path** always exists alongside the automatic action.

---

## Feature → requirement mapping
| Feature | Requirement satisfied |
|---|---|
| Sensor inputs + timestamps | Mandatory #1 (Sensor Data Collection) |
| Smoothing every channel | Mandatory #2 (Moving Average Filter) |
| Threshold + rate + fusion decisions | Mandatory #3 (Real-Time Data Processing) |
| pump_on / alerts / status outputs | Mandatory #4 (Output Analytics System) |
| Weed rate-anomaly + adaptive detector | Bonus: AI-driven anomaly detection |
| Crop-health fusion, temp-compensation | Bonus: Multi-sensor fusion |
| (UART packet stream to a dashboard) | Bonus: Cloud sync (hybrid edge-cloud) |

---

## One-line pitch
> *"Our chip doesn't just watch the crop — it waters it when it's dry, feeds it when
> it's hungry, shields it from heat and frost, spots resource-stealing weeds, and
> ignores broken sensors — all decided and acted on right in the field, in
> microseconds, with no cloud."*
