# Aggregated Summary — what the literature tells us to build & change

> Cross-paper synthesis of the 10 downloaded papers (+ the link-only Lozoya paper).
> Individual summaries: [`SUMMARIES.md`](SUMMARIES.md). Differentiation index/story:
> [`PAPERS.md`](PAPERS.md). Read this before the pitch/grill and before the next RTL phase.

---

## 1. The one-line takeaway
The literature **unanimously** says "move analytics to the edge" for latency, bandwidth,
power, and rural-connectivity reasons — **but every single surveyed system stops at
software on a Raspberry Pi / ESP32 / gateway / cloud. Not one does the analytics in
dedicated RTL/silicon.** That empty box in the taxonomy is exactly our contribution.
Two hardware papers (TEDA-FPGA, greenhouse fusion) prove it's *feasible and cheap* in
hardware; the rogue-sensor paper proves our fault-check matters; Lozoya provides the
quantified "why edge" headline.

## 2. What the three groups collectively establish
| Group | Papers | What they let us claim |
|---|---|---|
| **Baseline (differentiate against)** | IJCRT1033090, IRJET-V9I6372 | "Everyone does sensors→cloud→dashboard with fixed comparators and *manual* control. We automate + move it on-chip." Their admitted cloud-dependence/network-failure weakness is our talking point. |
| **Why-edge surveys** | Zhang 2020, O'Grady 2019, Kalyani 2021, Akhtar 2021, Chicaiza 2024 | Edge cuts latency/bandwidth/power; the Cloud–Fog–Edge split *is* our two-tier model; NPK-at-edge (Lavanya) precedes our doser; delay-tolerant alert-only transmit *is* Tier-2. Hard numbers to borrow: −43.5% traffic, 95% streaming reduction. |
| **Differentiator evidence ⭐** | TEDA-FPGA, Greenhouse fusion, Rogue-sensor (+ Lozoya link) | On-chip anomaly is real VLSI (138 ns, 7.2 MSPS, <7% LUTs). Multi-sensor fusion beats single-sensor (AUC ↑, ms latency). Sensor-fault taxonomy (stuck-rail T1 / slow T2 / fast T3). Event-triggered comms: **>85% fewer messages, ~20% less power**. |

## 3. Every project feature now has a citation
| Our feature | Backed by | Note |
|---|---|---|
| On-chip smoothing / filtering | O'Grady (calibration smoothing), noise model from IRJET DHT11 (±2 °C, ±5% RH) | smoothing is *justified* by real sensor noise specs |
| Multi-sensor fusion (`crop_health`) | Greenhouse fusion (fuse jointly!), Akhtar/O'Grady NPK | **fuse dimensions jointly, not per-sensor thresholds** |
| Anomaly detection (on-chip) | TEDA-FPGA (adopt recursive eccentricity), Greenhouse fusion | our headline VLSI citation |
| Adaptive anomaly / concept drift | Greenhouse fusion (sliding window) | mirror as a running adaptive baseline in RTL |
| Sensor-fault self-check (`alert_anomaly`) | Rogue-sensor (T1/T2/T3 taxonomy) | implement as a stuck-counter comparator |
| Tier-1 local actuation (`pump_on`, doser) | Kalyani (Fog decisions), O'Grady/Akhtar (Lavanya fuzzy NPK) | automatic in hardware vs their manual toggle |
| Tier-2 event-triggered alert | Lozoya (85%/20%), Zhang (LoRa/NB-IoT), O'Grady (delay-tolerant), Kalyani (MQTT) | **the quantified reason to compute at the edge** |
| Prediction | O'Grady (linear regression on-edge), Chicaiza (AI/ML tier) | keep it lightweight (threshold/trend), don't claim ML |

## 4. MAJOR FEATURES — how to frame each for judges
1. **On-chip Edge Analytics IP in synthesizable RTL** — the "fourth data-processing tier" (on-chip hardware analytics) that Chicaiza's taxonomy is missing. This is the whole novelty; lead with it.
2. **Multi-sensor fusion (soil moisture + NPK + temperature)** — greenhouse paper proves joint fusion beats single-sensor; NPK is nearly unexplored in the field (only 1 of 80 papers), so it's a genuine differentiator, not table stakes.
3. **On-chip anomaly detection** — TEDA-FPGA gives us the algorithm shape (recursive eccentricity) and the credibility numbers.
4. **Sensor-fault / rogue-sensor self-check** — adopt the T1/T2/T3 taxonomy; cheap RTL, real-world validated (RI 0.89).
5. **Two-tier response** (Tier-1 local pump/doser + Tier-2 event-triggered caretaker alert) — the Cloud–Fog–Edge literature *is* this split; Lozoya's 85%/20% is the payoff number.

## 5. THINGS WE NEED TO CHANGE / ADD to the project
Ordered by leverage.

1. **[Highest] Fuse sensors JOINTLY, not as independent per-sensor thresholds.** The greenhouse paper's core finding is that cross-sensor correlation (e.g., moisture ↓ while temp ↑) is what single-sensor thresholds miss. Check our current `crop_health`/fusion RTL — if it's ORing independent thresholds, add a combined/correlated score. This is the difference between "real fusion" and "three comparators."
2. **[Highest] Adopt TEDA-style recursive eccentricity for the anomaly block** — running mean + variance + Chebyshev threshold, fixed-point. Parameter-free, self-tuning, no stored history: ideal for a beginner-friendly synthesizable block, and it hands us a citation + concrete resource/latency numbers to quote.
3. **[High] Download the Lozoya paper and record 85% / 20% as a measured target.** It's the single most-quoted number in our story and still link-only. Then **quantify OUR OWN egress reduction** (bytes/event vs continuous streaming) from simulation — O'Grady shows "reduced data traffic" is the metric judges expect; we currently assert the benefit without our own number.
4. **[High] Implement the rogue-sensor T1/T2/T3 fault taxonomy** as an explicit stuck-counter/recovery-rate check feeding `alert_anomaly`. Cheap in RTL, and it turns a vague "sensor-fault self-check" into a validated, named feature.
5. **[Medium] Add a sliding-window / adaptive baseline** (concept drift) so thresholds track slow seasonal/soil change instead of being fixed — greenhouse paper flags drift as one of the three hard streaming properties.
6. **[Medium] Name the Tier-2 uplink protocol: MQTT (or LoRa/NB-IoT).** Kalyani flags MQTT as safest; Zhang backs LoRa/NB-IoT. Judges may ask "how does the alert actually leave the chip" — have the answer even if it's out-of-scope for RTL.
7. **[Medium] Use realistic sensor-noise stimulus in testbenches** (DHT11 ±2 °C/±5% RH from IRJET) to *demonstrate* the smoothing filter earning its keep, rather than clean synthetic data.
8. **[Low / framing] State scope honestly:** our prediction is lightweight threshold/trend, NOT ML — don't claim CNN/AI parity (Zhang/Kalyani "prediction" implies ML we can't fit). And note farm-security/intrusion (IJCRT) is deliberately out-of-scope.

## 6. Honesty guardrails for the grill
- Don't claim we invented edge analytics or two-tier comms — the concept is well-precedented (Kalyani, O'Grady). **Our novelty = the on-chip RTL implementation + closed-loop two-tier autonomy**, which no surveyed paper does.
- The surveys support our *motivation*, not our *numbers*. Every quantitative claim about OUR chip must come from OUR simulation (footprint, latency, egress reduction). Borrowed numbers (TEDA 138 ns, Lozoya 85%/20%) must be cited as theirs.
- NPK is our strongest under-exploited angle (1/80 papers) — press it.
