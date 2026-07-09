# Reference Papers — index, relevance & how we differentiate

> Purpose: back the project in the literature (the judge said "too common, no unique
> factor" and pushed for a caretaker-communication system). Each paper below is tagged
> with **which project feature it supports** and **how we go beyond it**. Grill-ready.

Two buckets: **(A) the common IoT-smart-agri baseline** we differentiate *against*, and
**(B) the edge / hardware / event-triggered-comms literature** that grounds our
differentiators (Phase 8 — see `../docs/BUILD_PLAN.md` and `../docs/INTERFACES.md §6`).

---

## The one-paragraph differentiation story (say this to the judge)
Most smart-agriculture papers (below, group 1) are **system-level IoT**: sensors → a
microcontroller/Raspberry Pi → the **cloud** → a dashboard, with periodic transmission
and automated irrigation. We build the layer *underneath* that: a **synthesizable
Verilog Edge Analytics IP** that does the smoothing, fusion, anomaly and prediction
**on-chip**, and — the differentiator — a **two-tier response**: Tier 1 local actuation
(pump/doser) + Tier 2 an **event-triggered alert to the caretaker**, transmitting only
when a human is needed. That event-triggered transmission is not a nicety: Lozoya et al.
(group 3) show it cuts messages **>85%** and power **~20%** vs periodic sampling — which
IS the reason to compute at the edge. So our "communication system" and our "why edge"
are the same contribution, and it's realised in hardware, not another cloud dashboard.

---

## GROUP 1 — the common baseline (what "everyone" does — we differentiate against it)
Use these to show we know the field AND to contrast. Low novelty on their own.

| File | Paper | What it is | We go beyond it by… |
|---|---|---|---|
| `IJCRT1033090.pdf` | *IoT-Based Smart Agriculture Monitoring System* (IJCRT) | Sensors → cloud → dashboard + automated irrigation + wireless monitoring | doing analytics **on-chip in RTL**, not on a cloud server; adding **event-triggered** (not periodic) comms |
| `IRJET-V9I6372.pdf` | *Smart Agriculture System using IoT* (IRJET 2022) | Basic IoT smart-farm build | same as above; plus **predictive** watering + **sensor-fault** self-check |

## GROUP 2 — edge-computing-in-agriculture surveys (justify "why edge"; strong citations)
These are your background/related-work and SDG framing. All review/survey papers.

| File | Paper | Supports |
|---|---|---|
| `09153160.pdf` | Zhang et al., *Overview of Edge Computing in the Agricultural IoT* (IEEE Access 2020) | "why edge," edge architecture, comms tech (LoRa) → backs Tier-2 |
| `1-s2.0-S2589721719300339-main.pdf` | O'Grady et al., *Edge computing: a tractable model for smart agriculture?* (Elsevier 2019) | edge vs cloud + **UN SDG 2030** framing (matches our ROADMAP) |
| `sensors-21-05922-v3.pdf` | Kalyani & Collier, *Cloud, Fog & Edge Computing Combination in Smart Agriculture* (MDPI Sensors 2021) | **what-to-compute-where** → directly backs our two-tier model |
| `agriculture-11-00475.pdf` | Akhtar et al., *Smart Sensing with Edge Computing... Soil Assessment* (MDPI Agriculture 2021) | edge + **soil** sensing (our moisture/NPK front-end) |
| `Smart_Farming_Technologies_...pdf` | Chicaiza et al., *Smart Farming Technologies: Methodological Overview* (IEEE Access 2024) | recent landscape / state-of-the-art slide |

## GROUP 3 — THE DIFFERENTIATOR EVIDENCE (added to fill the two gaps) ⭐
These are the papers that turn our unique features from "an idea" into "literature-backed."

| File | Paper | Backs which Phase-8 feature |
|---|---|---|
| **[LINK — download]** ⬇ | **Lozoya et al., *Energy-Efficient Wireless Communication Strategy for Precision Agriculture Irrigation Control*, MDPI Sensors 2021, 21(16):5541, doi:10.3390/s21165541** | ⭐ **8A comms_tx + 8D edge-win.** Self-/event-triggered transmission (send only when moisture dynamics warrant) → **>85% fewer messages, ~20% less power** vs 10-min periodic sampling, same irrigation performance. THIS is the quantified proof of our Tier-2 design. |
| `arXiv2003.03837_TEDA_FPGA_StreamingAnomaly_Hardware.pdf` | *Hardware Architecture Proposal for TEDA algorithm to Data Streaming Anomaly Detection* (arXiv 2003.03837) | **8E adaptive_anomaly + our RTL story.** Streaming anomaly detection **in FPGA hardware**, small resource footprint, short latency — proves on-chip anomaly detection is a real *hardware* contribution (our missing VLSI citation). |
| `arXiv2107.13353_EdgeGreenhouse_FastAnomaly_SensorFusion.pdf` | *Fast wireless sensor for anomaly detection based on data stream in an edge-computing-enabled smart greenhouse* (arXiv 2107.13353 / ScienceDirect) | **8C fusion + on-edge anomaly.** Fuses soil/humidity/temp on the edge, beats single-sensor baselines with negligible latency → backs our multi-sensor `crop_health` fusion. |
| `arXiv2305.05495_RogueSoilMoistureSensor_AnomalyDetection.pdf` | *Self-Supervised Anomaly Detection of Rogue Soil Moisture Sensors* (arXiv 2305.05495) | **`alert_anomaly` / sensor-fault self-check.** Detecting faulty soil-moisture sensors — exactly our rail-stuck / anomaly feature. |

### ⬇ Direct link for the one that wouldn't script-download (open access, click in a browser)
- **Lozoya et al. 2021, Sensors 21(16):5541** — https://www.mdpi.com/1424-8220/21/16/5541
  (PDF button top-right; or PMC mirror: https://pmc.ncbi.nlm.nih.gov/articles/PMC8402102/ ).
  Save it here as `Sensors2021_5541_EventTriggered_Irrigation.pdf`. **Highest-priority read** —
  its 85%/20% numbers are the headline of our edge-win slide.

---

## Are more needed? — assessment
- **Enough for the pitch/grill: yes.** Groups 2+3 cover "why edge," the two-tier comms
  differentiator (with hard numbers), on-edge fusion, hardware anomaly detection, and
  sensor-fault detection — every Phase-8 claim now has a citation.
- **Optional strengtheners** (only if you want more VLSI depth):
  - a pure **FPGA/ASIC agriculture** accelerator paper (search: *"FPGA precision
    agriculture edge accelerator"* on IEEE Xplore) — closest hardware-in-farming fit.
  - `fSEAD: Composable FPGA Streaming Ensemble Anomaly Detection` (ACM TRETS 2022) — more
    FPGA anomaly-detection depth if a judge drills the hardware.
  - a **TinyML edge irrigation** paper (arXiv 2601.13054 / 2603.15085) if you lean into
    the "AI at the edge" bonus.

## Reading priority (limited time)
1. **Lozoya 2021, Sensors 5541** (comms/edge-win numbers — memorise 85% / 20%).
2. `sensors-21-05922` (cloud/fog/edge split — the two-tier justification).
3. `arXiv2003.03837` (FPGA anomaly hardware — your VLSI credibility).
4. Skim `09153160` (Zhang) for edge-architecture vocabulary and one contrast vs Group 1.
