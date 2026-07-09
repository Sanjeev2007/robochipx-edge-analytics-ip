# Research Paper Summaries — individual

> Individual summaries of every downloaded paper in this folder, each tied to our
> project features (Smart Agriculture Edge Analytics IP, synthesizable Verilog RTL).
> For the differentiation index/story see [`PAPERS.md`](PAPERS.md); for the cross-paper
> synthesis + "what to change" see [`AGGREGATE_SUMMARY.md`](AGGREGATE_SUMMARY.md).

Grouping mirrors `PAPERS.md`: **Group 1** = common IoT baseline (differentiate against),
**Group 2** = edge-computing surveys (why edge), **Group 3** = differentiator evidence ⭐.

---

## GROUP 1 — Common IoT-smart-agri baseline (differentiate AGAINST)

### `IJCRT1033090.pdf` — IoT-Based Smart Agriculture Monitoring System
**Full citation.** Bharati, "IoT-Based Smart Agriculture Monitoring System: Enhancing Precision Farming with Real-Time Data and Automated Irrigation," *Int. J. Creative Research Thoughts (IJCRT)*, Vol. 4, Issue 1, Feb 2016, pp. 590–597. ISSN 2320-2882.

**What it is.** A classic hardware-integration smart-farm project. An Arduino Uno reads a soil-moisture sensor and rain sensor, drives a relay/water-pump for automatic irrigation, adds an electrified fence + buzzer for animal-intrusion alerts, shows status on a 16×2 LCD, and pushes all raw sensor data to the Adafruit IO cloud via ESP8266 Wi-Fi, with GSM/SMS for manual remote pump control.

**Key methods / numbers.** Pump ON when soil moisture < 30%, OFF at 70% (fixed comparators); rain sensor forces pump OFF; intrusion detection reported 95% success; all data continuously logged to Adafruit IO; GSM enables SMS on/off. Stated limits: cloud dependence = network-failure risk; sensors need calibration.

**Supports our features.** Our irrigation loop (moisture threshold → `pump_on`) and water-conservation logic. Their "future work" (predictive analytics, event alerts to farmer) is essentially our Tier-2 concept.

**How we go beyond / what to change.** This IS the baseline we differentiate against — raw sensors → Arduino → periodic cloud upload → dashboard, intelligence off-chip or absent. Contrast points: on-chip analytics in RTL vs continuous raw streaming; event-triggered Tier-2 vs always-on cloud logging (which they admit is a network-failure liability — strong talking point); multi-sensor fusion + NPK dosing vs a single moisture threshold; on-chip anomaly + prediction vs fixed 30/70 comparators. Honest gap: we lack their farm-security/intrusion feature (note as out-of-scope, not a weakness).

---

### `IRJET-V9I6372.pdf` — Smart Agriculture System Using IoT
**Full citation.** Goon, Debbarma, Debbarma, Deb, Baul, Debbarma, "A Research Paper on Smart Agriculture System Using IoT," *Int. Research J. of Engineering and Technology (IRJET)*, Vol. 9, Issue 6, June 2022, pp. 2088–2093. e-ISSN 2395-0056.

**What it is.** A student prototype Wi-Fi smart-farm kit. Three sensors (soil moisture, DHT11 temp/humidity, HC-SR04 water-level) feed an ESP8266 NodeMCU that streams raw readings to the Blynk cloud app; the farmer views data and manually toggles two relay-driven pumps from their phone.

**Key methods / numbers.** Pure sensor→cloud→dashboard telemetry, no on-device analytics. DHT11: 0–50 °C (±2 °C), 20–90% RH (±5%), 1 Hz. Ultrasonic threshold 16 cm. NodeMCU Xtensa LX106, 80–160 MHz. Pump ~120 L/hr at 3–6 V. Actuation is **manual** from the app — decisions happen in the human's head, not in silicon.

**Supports our features.** Baseline overlap: soil-moisture + temperature sensing and pump actuation. Canonical "sensors→cloud→dashboard" architecture we position against.

**How we go beyond / what to change.** We move analytics on-chip (smoothing, fusion, anomaly, prediction — none exist here). Our Tier-1 actuation is *automatic in hardware* vs their manual app toggle; Tier-2 event-triggered alert replaces always-on streaming. Worth stealing: their DHT11 tolerances (±2 °C, ±5% RH) are a realistic testbench noise model that *justifies* our smoothing filter; their NPK/fertility reference validates our NPK doser. Their manual-control weakness is our headline.

---

## GROUP 2 — Edge-computing surveys (justify "why edge")

### `09153160.pdf` — Overview of Edge Computing in the Agricultural IoT
**Full citation.** X. Zhang, Z. Cao, W. Dong, "Overview of Edge Computing in the Agricultural Internet of Things: Key Technologies, Applications, Challenges," *IEEE Access*, vol. 8, pp. 141748–141761, 2020. DOI 10.1109/ACCESS.2020.3013005.

**What it is.** A survey arguing why agri-IoT should move computation from cloud to the network edge; reviews edge + AI/blockchain/VR-AR in farming and four open challenges (data processing, task assignment, privacy/security, service stability).

**Key methods / vocabulary.** Motivation: sensor data is "usually stable or rarely changed," so uploading everything wastes network/cloud and hurts real-time response — filter/analyze nearby. ECC 4-domain hierarchy (equipment / network / data / application). 5-layer agri-IoT stack (sensing→access→network→data-sharing→application) with named comms tech: Wi-Fi, GPRS, ZigBee, Bluetooth, and **NB-IoT + LoRa** for low-power wide-area. Edge intelligence inference modes (edge/device/edge-device/edge-cloud). "Local edge nodes provide services independently when disconnected from the cloud."

**Supports our features.** Justifies the whole thesis — local decision-making, filtering/smoothing before transmit, reduced latency. NB-IoT/LoRa backs Tier-2; "independent when disconnected" maps to Tier-1 local actuation.

**How we go beyond / what to change.** All its "edge" is Linux-class edge servers/gateways running CNN offloading — never RTL/silicon. We push one layer deeper: fusion/anomaly/prediction as synthesizable Verilog on the sensor node itself ("equipment domain" done in RTL). Cite for "why edge + LoRa event-triggered comms." Do **not** claim AI/CNN parity — theirs is deep learning; ours is deterministic fixed-point logic, sold as low-power and disconnection-proof.

---

### `1-s2.0-S2589721719300339-main.pdf` — Edge computing: a tractable model for smart agriculture?
**Full citation.** M.J. O'Grady, D. Langton, G.M.P. O'Hare, "Edge computing: A tractable model for smart agriculture?," *Artificial Intelligence in Agriculture*, 3, 42–51, 2019. Elsevier/KeAi (CC BY-NC-ND). DOI 10.1016/j.aiia.2019.12.001.

**What it is.** A survey of Edge/Fog in agriculture, framed against food security and the UN SDGs 2030. Screened 135 papers, analyzed 46; catalogs edge techniques by domain.

**Key numbers / SDG framing.** >820M people hungry (~1 in 9); food demand +25–70% by 2050; smart-ag market $6.34B (2017)→$13.50B (2023). Rural digital divide: 39% of rural US and >50% of rural EU lack broadband → motivates on-device analytics. Edge benefits with hard numbers: data traffic −43.5% (Zhou), 95% streaming reduction (metagenomics), up to 99% localization accuracy (Bhargava). All surveyed systems are prototypes at TRL 4–5 on off-the-shelf hardware (Raspberry Pi).

**Supports our features.** Lavanya et al. (§4.6) do colorimetric N-P-K sensing with **fuzzy rule-based logic on an edge device** computing fertilizer needs — direct precedent for our fusion + Tier-1 doser. Krintz et al. use "calibration smoothing + linear regression" on-edge to predict temperature — validates our smoothing + prediction. Paper explicitly endorses delay-tolerant, alert-only transmission ("only a calculated risk-index need be transmitted"; LoRa alerts) — exactly Tier-2.

**How we go beyond / what to change.** Every surveyed system runs software on general-purpose SBCs at TRL 4–5. Our synthesizable RTL IP is the "purpose-built, industrial-strength" platform the paper says is *missing* — lead with this. Frame our doser as a hardware realization of Lavanya's fuzzy NPK logic; frame our alert as an implementation of their delay-tolerant thesis (novelty = on-chip RTL + two-tier autonomy, not the concept). **Add:** quantify our egress reduction (bytes/event vs continuous streaming) as a headline number mirroring their 43.5%/95%.

---

### `sensors-21-05922-v3.pdf` — Cloud, Fog & Edge Combination in Smart Agriculture
**Full citation.** Y. Kalyani, R. Collier, "A Systematic Survey on the Role of Cloud, Fog, and Edge Computing Combination in Smart Agriculture," *Sensors* (MDPI), 2021, 21(17), 5922. DOI 10.3390/s21175922.

**What it is.** A systematic review (2788 studies → 55 primary, 2015–2021) of Cloud/Fog/Edge combinations in smart agriculture. Classifies six domains (animal, crop, greenhouse, irrigation, soil, weather) and proposes a 3-layer Cloud–Fog–Edge reference architecture.

**What-to-compute-where.** **Edge** = end devices/sensors/actuators, collection + local transfer; **Fog** = local farm nodes doing real-time analytics + decisions; **Cloud** = large-scale storage + heavy analytics. Core finding: pure Cloud fails on latency, bandwidth, real-time processing, and poor rural connectivity — processing must move edgeward. MQTT flagged as the safest messaging protocol.

**Supports our features.** Directly backs our two-tier model: Edge-collection / Fog-real-time-decision maps onto Tier-1 (on-chip actuation), "upload processed/event data" maps onto Tier-2 (event-triggered alert). Sensor set (moisture, NPK, temp) matches their soil/crop/irrigation domains.

**How we go beyond / what to change.** They stop at *software* Fog nodes; no surveyed work does analytics in synthesizable RTL on-chip — our genuine novelty. They *propose* an architecture but don't implement it, so frame ours as a concrete RTL realization. Be precise that our on-chip "prediction" is lightweight (threshold/trend/smoothing), not ML. Cite **MQTT** as the intended Tier-2 uplink protocol.

---

### `agriculture-11-00475.pdf` — Smart Sensing with Edge Computing for Soil Assessment
**Full citation.** M.N. Akhtar, A.J. Shaikh, A. Khan, H. Awais, E.A. Bakar, A.R. Othman, "Smart Sensing with Edge Computing in Precision Agriculture for Soil Assessment and Heavy Metal Monitoring: A Review," *Agriculture* (MDPI) 2021, 11(6), 475. DOI 10.3390/agriculture11060475.

**What it is.** A review of IoT sensors, wireless nodes, and edge/fog computing for precision agriculture in developing nations, emphasizing soil assessment + heavy-metal (As, Cd, Pb, Hg) monitoring. Proposes a conceptual HPC-on-edge offloading model.

**Key numbers.** Agriculture uses ~70% of freshwater, ~1/3 of GHG emissions. Table of wireless motes (BTnode, EPIC, IMote 2.0, TelosB, MICA2), MCUs 8 MHz→400 MHz over ZigBee/802.15.4/BT. NPK relevance: Lavanya et al. — colorimetric NPK sensing (LDR+LED) with a fuzzy rule classifier on a Raspberry Pi edge node. Nearly all surveyed "edge" work is really offloading/gateway preprocessing — still cloud-tethered.

**Supports our features.** Backs our soil-moisture + NPK front-end and fusion: NPK-deficiency inference at the edge = our Tier-1 doser logic; the fuzzy rule classifier precedes our on-chip threshold/anomaly rules. WSN-gateway "real-time alarm" mirrors Tier-2.

**How we go beyond / what to change.** Their "edge" is a Raspberry Pi/gateway CPU running software — no dedicated RTL/silicon. We move from a ~400 MHz Linux SBC to a deterministic hardware datapath (lower power/latency, no OS). Cite Lavanya as the software baseline our RTL replaces; adopt colorimetric NPK sensing as our documented front-end assumption. Note: this paper gives no hardware/power/latency benchmarks — it supports our *motivation*, not our *numbers* (those come from our simulation).

---

### `Smart_Farming_Technologies_..._Overview_and_Analysis.pdf` — Smart Farming Technologies: Methodological Overview
**Full citation.** K. Chicaiza, R.X. Paredes, I.M. Sarzosa, S.G. Yoo, N. Zang, "Smart Farming Technologies: A Methodological Overview and Analysis," *IEEE Access*, vol. 12, pp. 164922–164938, 2024. DOI 10.1109/ACCESS.2024.3487497.

**What it is.** A systematic survey of 80 smart-farming papers (2018–2023) classifying real-world IoT farming solutions to guide component selection — a landscape, not a novel system.

**Key taxonomy.** Eight component categories: sensors, actuators, gateways/edge devices, power, networking, storage, processing, delivery. **Data processing** splits into three tiers: AI/ML (most prevalent), **threshold-based** (second), manual/human (third). Delivery dominated by web (26%) and mobile (22%) apps; SMS only 9%. Soil moisture is the single most-cited sensor; **soil NPK appears in only ONE paper [58]**. Water pump is the top actuator.

**Supports our features.** Our sensors are all catalogued; threshold anomaly maps to their 2nd processing tier, prediction to their AI/ML tier, caretaker alerts to their SMS channel.

**How we go beyond / what to change.** Confirms our differentiation is real: every surveyed solution runs processing on MCUs/gateways/cloud — **none in dedicated RTL/silicon**; delivery is overwhelmingly always-on dashboards, not event-triggered. Actions: (1) frame our IP as a fourth data-processing tier — "on-chip hardware analytics" — absent from their taxonomy; (2) **lean into NPK fusion** since NPK is nearly unexplored (only [58]); (3) position Tier-2 event-triggered alerts against their always-on model as a power/bandwidth win.

---

## GROUP 3 — Differentiator evidence ⭐

### `arXiv2003.03837_TEDA_FPGA_StreamingAnomaly_Hardware.pdf` — TEDA in FPGA hardware ⭐ (our VLSI citation)
**Full citation.** L.M.D. da Silva, M.G.F. Coutinho, C.E.B. Santos, M.R. Santos, L.A. Guedes, M.D. Ruiz, M.A.C. Fernandes, "Hardware Architecture Proposal for TEDA algorithm to Data Streaming Anomaly Detection," arXiv:2003.03837v1 [cs.DC], 8 Mar 2020.

**What it is.** The first FPGA/RTL implementation of TEDA (Typicality and Eccentricity Data Analytics) — a recursive, parameter-free streaming anomaly detector. Flags a sample as an outlier when normalized *eccentricity* exceeds a Chebyshev-derived threshold; learns online with no prior model, no distribution assumptions, no training set.

**HARD NUMBERS** (Xilinx Virtex-6, floating-point). Resource: **27 multipliers (3%), 414 registers (<1%), 11,567 LUTs (7%)**. **Critical path 138 ns**; 4-stage pipeline (MEAN→VARIANCE→ECCENTRICITY→OUTLIER); initial latency 414 ns then one classification every 138 ns. **Throughput 7.2 MSPS.** Speedup vs Python: 3,000,000× (CPU), 280,000× (Tesla K80). Threshold ζk > (m²+1)/(2k), m=3. Validated on DAMADICS industrial fault dataset.

**Supports our features.** Underwrites our on-chip anomaly block and the core differentiator (analytics IN RTL). This is our missing VLSI citation: proves streaming, parameter-free anomaly detection is a legitimate synthesizable hardware contribution with a small, real resource budget. Operates on multi-element input vectors → aligns with our multi-sensor fusion.

**What to ADOPT.** Adopt TEDA-style **recursive eccentricity** as our anomaly primitive — needs only running mean + variance + a Chebyshev threshold: cheap, self-tuning, no stored history, beginner-friendly synthesizable block. Cite their 138 ns / 7.2 MSPS / <7% LUT to anchor our latency/footprint claims. Implement a **fixed-point** version (they used floating-point) to shrink further. We go beyond via fusion + two-tier response — TEDA only outputs a binary flag and stops at detection; our IP closes the loop to actuation + prediction.

---

### `arXiv2107.13353_EdgeGreenhouse_FastAnomaly_SensorFusion.pdf` — Fast edge anomaly detection, smart greenhouse ⭐ (fusion evidence)
**Full citation.** Y. Yang, S. Ding, Y. Liu, S. Meng, X. Chi, R. Ma, C. Yan, "Fast Wireless Sensor Anomaly Detection based on Data Stream in Edge Computing Enabled Smart Greenhouse," arXiv:2107.13353 [cs.LG], 28 Jul 2021.

**What it is.** An edge-deployed anomaly detector for multi-sensor greenhouse streams. Proposes **DLSHiForest** (LSH + isolation forest + sliding window + periodic update) to handle streaming's three hard properties: infiniteness, cross-sensor correlation, concept drift.

**HARD NUMBERS.** Fuses **6 attributes as one m-dimensional point**: indoor temp, humidity, light, CO2, soil temp, soil moisture. The LSH hash operates on all dimensions at once → explicitly captures cross-sensor correlation (e.g., humidity falling as temp rises) that a single-dimension detector cannot. Anomaly threshold 0.65. On a real greenhouse dataset DLSHiForest beats RRCF/Hyper_grid/Cluster on AUC and F1 (≈ AUC 0.85–0.90, F1 ≈ 0.70 at subset b=10000). **Time cost ≈ 0.003–0.005 s per point** ("negligible latency"), roughly flat as volume grows; ~4–5× faster than clustering/grid methods. Best params: window w=128, trees t=60.

**Supports our features.** Directly backs our multi-sensor fusion `crop_health` and anomaly blocks — hard evidence that fusing correlated soil/temp/humidity beats single-sensor thresholds, and that edge detection is low-latency (core of our "analytics on-chip" story).

**What to ADOPT.** (1) Their multi-dimension correlation insight — fuse sensors *jointly*, not per-sensor thresholds; (2) a **sliding window** for concept drift, mirrored cheaply in RTL as a running baseline that adapts over time; (3) cite their AUC/F1 and ~ms latency as third-party validation. Their "edge" is still Python on a Lenovo PC — we push the same logic into RTL and add closed-loop Tier-1 actuation + Tier-2 alerts, which the paper lacks. Full LSH-forest is too heavy for our RTL budget → implement a lightweight fixed-point analog of the fused-score idea.

---

### `arXiv2305.05495_RogueSoilMoistureSensor_AnomalyDetection.pdf` — Rogue soil-moisture sensor detection ⭐ (sensor-fault evidence)
**Full citation.** B. Deforce, B. Baesens, J. Diels, E. Serral Asensio, "Self-Supervised Anomaly Detection of Rogue Soil Moisture Sensors," arXiv:2305.05495v1, 9 May 2023 (KU Leuven; Univ. of Southampton).

**What it is.** A fully self-supervised method for detecting "rogue" soil-moisture sensors (sensors giving wrong readings over time) without labels. Learns discriminative embeddings of each sensor's time-series with a triplet-loss network, then clusters embeddings with DBSCAN to flag deviating sensors.

**HARD NUMBERS.** Triplet network over an exponentially-dilated causal CNN encoder → R² embedding → DBSCAN (minPts=4). Novelty: DTW-distance negative sampling (picks K furthest series as negatives). Data: 63 Watermark sensors, 884 observations each, 30 cm depth, 2 Belgian pear fields, 4-hour cadence. **Adjusted Rand index = 0.89 vs expert labels.** Rogue behaviors: **T1 = hits a threshold and never recovers (stuck rail); T2 = hits then recovers slowly; T3 = hits then recovers fast**; plus Normal.

**Supports our features.** Directly validates our sensor-fault self-check / rail-stuck detection and the `alert_anomaly` path. T1 "hits threshold and stays" = rail-stuck / faulty-sensor detection; T2/T3 = transient anomalies feeding Tier-2 alerts.

**What to ADOPT.** Their approach is heavy (offline, batch, DTW+CNN+DBSCAN, needs many co-located sensors + expert validation) — not on-chip. **Adopt their taxonomy** of rogue behaviors as our fault-classification targets (stuck-at rail, slow/fast recovery) and their threshold-crossing + "stays there" heuristic — trivially an RTL stuck-counter comparator — while skipping the ML pipeline. Framing: they prove the problem matters and define the fault classes; we make detection cheap enough to run on the chip itself, real-time, single-sensor.

---

*Not yet in this folder:* **Lozoya et al. 2021, Sensors 21(16):5541** (event-triggered irrigation, >85% fewer messages / ~20% less power) — link-only in `PAPERS.md`, highest-priority download. It is the quantified proof of the Tier-2 design and is treated as the headline number in the aggregate below.
