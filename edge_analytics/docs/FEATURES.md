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

## Beyond automation: the two-tier response model  (the differentiator)

> **Why this section exists:** evaluation feedback said the design reads as "just
> automation." The answer is that the chip responds on **two distinct tiers**, and the
> second one is what a pure automation project lacks.

**Tier 1 — local actuation (machine → machine).** For routine problems the chip fixes
itself, on-device, with no human and no network: soil dry → `pump_on`; nutrient low →
`dose_nutrient`. This is the automation loop.

**Tier 2 — remote communication (machine → human).** For *exceptions a machine should
not resolve alone*, the chip sends a compact **alert packet to the caretaker** over a
low-power radio (LoRa/GSM) — with a **recommended action**, not just a number:
- weed detected → *"INSPECT_WEED: check zone"* (a pump can't pull a weed)
- sensor fault → *"CHECK_SENSOR"* (automation must not act on garbage data)
- persistently CRITICAL despite watering+feeding → *"RELOCATE_OR_REVIEW"*
- dry-out predicted soon → *"PRE_IRRIGATE: check water supply"*

**Why Tier 2 is also the edge-power story (not a nicety):** the whole point of edge
analytics is that raw data is processed *on-chip* and only a **decision** leaves the
chip. Tier 2 transmits ~K sparse alerts instead of streaming N raw samples to the cloud
— quantified in Phase 8D as an X% cut in data sent and radio-on time. So the caretaker
comms channel and the "why edge?" justification are the **same feature**.

```
                 ┌────────── Tier 1: LOCAL ACTUATION (routine) ──────────┐
   SENSE → SMOOTH → DECIDE ─┤                                            │→ pump_on, dose_nutrient
                            └────────── Tier 2: REMOTE COMMS (exceptions) ┘→ alert_packet → caretaker
                                        event-triggered, sparse, over-the-air
```

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
| 7 | **Overall poor plant health** | Fusion of moisture + nutrient + temperature (+ optional humidity) into a single crop-health score | Sets an overall status; if CRITICAL, recommends relocating the plant | `status[1:0]`, `crop_health`, `relocate_recommend` | One clear verdict instead of raw numbers |
| 8 | **Dry-out coming soon** *(Phase 8B)* | Extrapolates the smoothed-moisture depletion slope `LEAD` samples ahead (divider-free) | Early warning *before* the soil is dry → pre-irrigate / warn caretaker | `predict_dry`, event `PREDICT_DRY` | Predictive, not reactive — acts ahead of crop stress |
| 9 | **Exception needing a human** *(Phase 8A ⭐)* | Any human-needed event (weed, sensor fault, persistent CRITICAL, frost, predicted dry) | Transmits a compact **alert packet with a recommended action** to the caretaker's phone over low-power radio | `msg_valid`, `alert_packet`, `msg_count` | Sparse over-the-air alerts (K packets, not N raw samples) = the edge power/bandwidth win |

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
- **Strengthen (Phase 8C):** add a 4th channel (humidity) — the pipeline is
  channel-parameterized, so it's cheap — or make the score an explicit *weighted sum*.
  Makes "multi-sensor fusion" a headline feature rather than an implicit one.

### 8. Predictive watering (Phase 8B — *predict, don't just react*)
- **Detect:** the chip already knows how fast moisture is falling (`dropped`, the same
  primitive the weed detector uses). The predictor extrapolates that slope `LEAD`
  samples ahead — **divider-free** (`projected = avg_moisture - (dropped*LEAD>>LOG2_HIST)`).
- **Act:** if `projected` crosses below the dry threshold while the soil is *not yet
  dry*, fire `predict_dry` / event `PREDICT_DRY` — a lead-time warning so the pump can
  pre-empt, or the caretaker can confirm water supply, before the crop is stressed.
- **Edge value:** reactive control waits for damage; prediction acts ahead of it.

### 9. Caretaker communication (Phase 8A ⭐ — the flagship differentiator)
- **Detect:** any **human-needed** event (weed, sensor fault, low nutrient with no
  doser, persistent CRITICAL, frost, predicted dry) — as opposed to machine-handled
  events (pump on/off) which need no human.
- **Act:** build a compact `alert_packet` = {severity, event_code, **action_code**,
  crop_health, timestamp} and transmit it (radio/LoRa/GSM → caretaker's phone). The
  `action_code` tells the human *what to do* (INSPECT_WEED, CHECK_SENSOR, PROTECT_FROST,
  …), not just a raw reading. Repeats are rate-limited (`MSG_GAP`) so it never spams.
- **Edge value (the number that wins the debate):** the chip processes every sample
  on-device and transmits only the sparse alerts — K packets, not N raw samples.
  Phase 8D prints the resulting cut in data sent + radio-on time. This is simultaneously
  the "message the caretaker" feature AND the quantified justification for doing
  analytics at the edge at all.

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
| Crop-health fusion (+ humidity/weighted, Phase 8C) | Bonus: Multi-sensor fusion |
| (UART packet stream to a dashboard) | Bonus: Cloud sync (hybrid edge-cloud) |
| Predictive watering (`predictor`, Phase 8B) | Bonus: predictive / trend analytics |
| Caretaker comms (`comms_tx` alert packets, Phase 8A) | **Differentiator: two-tier response — remote human notification, not just automation** |
| Edge-win quantification (Phase 8D) | Proof of the edge value: X% less data / radio-on time vs cloud streaming |

---

## One-line pitch
> *"Our chip doesn't just watch the crop — it waters it when it's dry, feeds it when
> it's hungry, shields it from heat and frost, spots resource-stealing weeds, and
> ignores broken sensors — all decided and acted on right in the field, in
> microseconds, with no cloud. And when a problem needs a human — a weed to pull, a
> sensor to replace, a dry-out coming — it doesn't just log it: it texts the caretaker
> the exact action to take, sending a few tiny alerts instead of streaming raw data,
> which is the whole reason it runs at the edge."*
