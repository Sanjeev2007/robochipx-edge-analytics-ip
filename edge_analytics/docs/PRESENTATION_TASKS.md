# Presentation & Docs — Task Sheet

**Branch:** `presentation`  ·  Owns: the pitch deck, demo script, and doc polish.
Presentation is a big share of the hackathon score — this is a full-time role.

---

## Goal
A slide deck + a rehearsed demo that tells the story clearly, backed by our real
results (waveforms, synthesis numbers, live dashboard).

## ⭐⭐ SHOWCASING WHAT WE BUILT — "if it's not on a slide, it doesn't exist"
> The tech is done and it's strong; the deck is now where the project is WON or LOST. The
> deep blocks (TEDA, joint fusion, sparse triage comms) are exactly what separates us from
> the pack of "we automated a pump" projects — but ONLY if the judge sees them. Every asset
> below MUST land on a visible slide moment or a spoken line. Nothing hidden.

**The differentiator inventory — the 4 things rival teams almost certainly do NOT have.**
Each needs a concrete on-slide artifact (not just a bullet claiming it):
1. **TEDA self-tuning anomaly** (`adaptive_anomaly.v`) — *"our chip calibrates its own
   normal per node; no hand-tuned thresholds → deployable across thousands of fields."*
   Artifact: a waveform where TEDA catches an anomaly a fixed rail-check misses + one line
   of the math (`(x−μ)² > m²·V`, divider-free). Frame as "AI anomaly, in silicon."
2. **Joint / correlated fusion** (`analytics_engine`, 8C) — *"we reason about channel
   COMBINATIONS, not each sensor alone."* Artifact: the sim row where every channel reads
   "fine" alone yet the combination is flagged (status leaves SAFE). One killer example.
3. **Two-tier triage + ~85–93% sparse caretaker comms** (`comms_tx`, 8A) — the answer to
   "it's just automation." Artifact: the DIFFERENTIATOR SLIDE table below + the real
   `msg_count` vs sample-count number from our own sim (Phase 8D).
4. **It's real silicon** — the synthesized schematic + utilization/timing/power numbers
   (Phase 8G / synthesis owner). Artifact: the schematic screenshot. **Biggest missing
   asset — get it early.** Without it we're "a script"; with it we're "a chip."

**Bonus coverage — a one-line flex slide:** 4/4 mandatory + **3/3 bonus, each EXCEEDED**
(adaptive vs fixed anomaly · correlated vs independent fusion · event-triggered vs always-on
cloud sync). Table + wording ready in `PROBLEM_STATEMENT.md` → "Bonus" section. Say it out loud.

**Judge-responsive feature — crop + soil profiles.** If we build the proposed `crop_profile`
(a judge suggested per-plant data): dedicate ONE line to *"you asked for per-crop data — here
it is: the chip carries agronomy setpoints per crop AND soil type, and TEDA self-tunes around
them."* Implementing a judge's own suggestion is a huge credibility signal — make sure it's
visibly attributed to their feedback. (Status: proposed — see `PROBLEM_STATEMENT.md`.)

**✅ THE OFFICIAL 10-SLIDE MAPPING** (from `RCX PPT TEMPLATE_...pptx`). This is a FIXED
submission format — our job is to pack our story into these exact boxes. **Slides 3 & 4 are
where we win — concentrate every differentiator there.** The "Suggested deck flow" further
down is superseded by THIS mapping.

| # | Template slide | What WE put on it |
|---|---|---|
| 1 | **TITLE** (Team ID / Track / Team name / Members) | Fill the fields. Add a one-line tagline: *"An Edge-Analytics IP for Precision Agriculture — analytics in silicon, not the cloud."* Track = Chip Design. |
| 2 | **PROBLEM STATEMENT** (core problem · significance · users · gaps) | IoT drowns in raw data; cloud = latency/bandwidth/privacy/**battery drain** (SDG 9 & 11). Users: farmers + a remote caretaker km away. **Gaps (set up our answers):** (a) dumb nodes stream every reading → drain the radio; (b) generic automation doesn't adapt per crop/soil/node; (c) hand-tuned thresholds can't scale to 1000s of fields. |
| 3 | **METHODOLOGY PROPOSED** (solution · how it resolves · **innovative/distinctive features**) ⭐ | THE DIFFERENTIATOR SLIDE. Solution = on-chip collect→smooth→analyze→act, two-tier response. Distinctive features = the 4: **① TEDA self-tuning anomaly** (adaptive, no hand-tuning → scales); **② joint/correlated fusion** (combinations, not single sensors); **③ two-tier triage → ~85–93% fewer transmissions** (same crop outcome); **④ it's real silicon**. (+ crop/soil profile line if built — "judge-suggested".) |
| 4 | **TECHNICAL APPROACH** (architecture · tools/algorithms · workflow · testing · metrics) | The **block diagram**: sensors → collector → smoothing (moving_avg×3) → analytics_engine (fusion + temp-comp weed) **+** adaptive_anomaly (TEDA) → output_analytics (**Tier-1** actuators/alerts) → comms_tx (**Tier-2** sparse radio). Algorithms: divider-free moving-avg, TEDA Chebyshev, hysteresis, latency-aligned pipeline. Workflow: Mac sim (iverilog/gtkwave) → GitHub → Windows synth (Vivado). Testing: per-module TBs + top-level story-arc, self-checking. **Metrics: 3 packets / 66 samples (8D), synth util/timing/power, 0 alignment errors.** |
| 5 | **TECH STACK** *(template mislabels this "Final Reflections" — its body asks for tools/hardware/platforms/languages, so treat as Tech Stack)* | Languages: Verilog + Python. Tools: Icarus Verilog, GTKWave, Yosys(+graphviz), Vivado/Quartus, Tkinter, Git/GitHub. Hardware target: FPGA/ASIC IP core (sim-proven, synthesizable); sensors = moisture/NPK/temp. Platform: local Mac + Windows synth — **no cloud (that's the point)**. |
| 6 | **EXPECTED DELIVERABLE — Prototype/Model** | The Edge Analytics IP (synthesizable Verilog) + **the synthesized schematic** ("real circuit, not a script") + utilization/timing/power. |
| 7 | **EXPECTED DELIVERABLE — Research paper/Docs** | The `docs/` suite (PROBLEM_STATEMENT, INTERFACES, BUILD_PLAN, FEATURES, CHANGELOG) + `papers/` research summaries + architecture writeup. |
| 8 | **EXPECTED DELIVERABLE — Working demo** | **`demo/edge_agri_dashboard_demo.mov`** (already recorded!) + live run (`vvp \| dashboard`) + gtkwave waveforms (raw vs smoothed, pump/alerts + caretaker packets firing on the story arc). |
| 9 | **REFERENCES** | Lozoya et al. 2021, *MDPI Sensors* 21:5541 (event-triggered irrigation, 85%/20%); TEDA (Angelov, Typicality & Eccentricity Data Analytics + the TEDA-FPGA paper); tool docs (Icarus, Yosys, Vivado); SDG 9 & 11. |
| 10 | **(closing)** | Thank-you / contact / repo link. |

---

## Where to pull material (already written)
- `FEATURES.md` — the detect→act showcase table + the one-line pitch (use verbatim).
- `PROBLEM_STATEMENT.md` — the official requirements + our feature→requirement mapping.
- `ROADMAP.md` / `BUILD_PLAN.md` — architecture + the block diagram to redraw cleanly.
- Synthesis owner → utilization/timing/power numbers + schematic screenshot.
- Dashboard owner → a screen recording of the live dashboard.

## Suggested deck flow
1. **Problem** — IoT drowns in raw data; cloud = latency, bandwidth, privacy (SDG 9 & 11).
2. **Our solution** — an on-chip Edge Analytics IP for Smart Agriculture (the pitch line).
2b. **⭐ Why edge / what's unique** — the two-tier response + the 85% number (see the
   DIFFERENTIATOR SLIDE section below). This is the answer to "it's too common."
3. **Architecture** — the pipeline: sensors → smoothing → analytics → auto-actions.
4. **Features** — the detect→act table (waters, feeds, spots weeds, ignores bad sensors).
5. **The edge advantage** — decides in microseconds, on-device, no cloud.
6. **Results** — waveforms (raw vs smoothed), the live dashboard + event log, synthesis
   numbers ("3% of chip, 150 MHz, 40 mW"). This is the proof section.
7. **Requirements coverage** — mandatory 1–4 all done + bonuses (anomaly, fusion, cloud egress).
8. **Scaling to acres + SDG + future** — the "real-world scale" slide (judge asked for it):
   - *Why silicon scales:* 1000s of nodes → per-node cost/power dominate; a Pi (watts, $35)
     can't; a µW/cents custom IP is the only viable option. **This is the real "why hardware."**
   - *Self-calibration is mandatory at scale:* can't hand-tune thresholds for 1000s of nodes
     across varied soil/sun/slope → our TEDA self-tuning anomaly block makes deployment possible.
   - *The novel direction (future work):* **spatial/cross-node anomaly** — "this zone depletes
     faster than its neighbours" catches weed patches / line leaks / a disease front that no
     single node sees; plus cluster-head **aggregation** so thousands of nodes don't cause a
     radio storm. Present as architecture + diagram — we FRAME it, we don't build the network.
   - Then SDG (9 & 11) + roadmap (multi-zone, predictive watering, real FPGA).

## ⭐ THE DIFFERENTIATOR SLIDE — "Why edge? The 85% number" (use this — judge feedback)
> A judge said the project is "too common, just automation, no unique factor." THIS slide
> is the answer. It reframes the chip from an *automation* project to a *power-optimization
> IP* — a real hardware value proposition. Put it right after "Our solution." Full context:
> `FEATURES.md` "Beyond automation: two-tier response" + `papers/PAPERS.md` (Lozoya 2021).

**The framing — two output tiers:**
- **Tier 1 — local actuation** (`pump_on`, `dose_nutrient`): the chip fixes routine
  problems itself, on-device. (This is the automation everyone has.)
- **Tier 2 — event-triggered comms**: the chip stays SILENT until an on-chip analysis
  decides a *human* is needed, then sends ONE tiny alert packet (with a recommended
  action) to the caretaker. **Being silent is the whole point** — the radio is the most
  power-hungry part of a battery field-node, so every transmission avoided = battery saved.

**The number (our own sim counters + literature):**

| | Dumb IoT node (stream every sample) | Our Edge Analytics IP (event-triggered) |
|---|---|---|
| Transmissions (per our 56-sample sim) | 56 (all raw samples) | ~4 (only real events) → **~93% fewer** |
| Literature (Lozoya et al. 2021, irrigation) | 4,032 messages | ~480 → **>85% fewer, ~20% less power** |
| Crop / irrigation outcome | fine | **identical** |

**⚠️ Pre-empt the obvious attack — "but your dashboard streams every sample!":**
The chip has **TWO physically different links**, and the 85% applies to ONLY one:
- **Local telemetry link** (the dashboard, `INTERFACES.md §3`) — short-range/wired
  (UART→gateway at the farmhouse, or on-site WiFi). Cheap, always-on → streaming every
  sample here is fine. This is for the on-site operator + the demo.
- **Long-range caretaker link** (`comms_tx`, §6) — LoRa/cellular to a phone that may be
  kilometres away, on battery. Expensive, power-critical → **this is the one that stays
  silent**, and the 85%/93% and Lozoya's numbers apply HERE ONLY.
So "the dashboard shows every reading" is NOT a contradiction — it's a different, cheap,
local channel. Always label the edge-win metric "over the long-range caretaker link."

**One-liner to say out loud:**
> *"A normal IoT node streams every reading to the cloud and drains its battery talking.
> Our chip does the analytics on-device and only speaks when a human is actually needed —
> 85–93% fewer transmissions for the same result. That silence is why it runs at the edge."*

**Talking points if the judge pushes:**
- Sensing and computing are cheap; **the radio dominates power** on a battery node. (WSN fact.)
- Triage is the novelty: the chip decides *whether a human is even needed* + *what action
  to take* (severity + action_code + rate-limit) — judgment, not a reflex SMS.
- Do NOT pitch it as "we added texting." Pitch triage + the power math. The message is
  just delivery.
- Backed by real work: our testbench prints `samples_processed` vs `msg_count` (Phase 8D),
  and Lozoya et al. 2021 (MDPI Sensors 21:5541) measured the same 85%/20% in the field.

## "Show the chip" — the 3 visual artifacts (rival teams have these; we need all 3)
Each answers a different judge question. Build plan: `BUILD_PLAN.md` Phase 8G.
1. **Waveforms (behaviour)** — from `dump.vcd` in `gtkwave`, or paste RTL+tb into
   **EDA Playground → EPWave** for a shareable online view. Money shot: raw (jagged) vs
   smoothed (clean) traces + `pump_on`/alerts firing on the story arc.
2. **Block/architecture diagram (the story)** — sensors → collector → smoothing →
   analytics (**joint fusion + TEDA anomaly**) → output → **{Tier-1 actuators | Tier-2
   comms_tx}**. Draw it clean; it anchors the Architecture slide.
3. **Synthesized schematic (it's REAL silicon)** ⭐ — from the synthesis owner: Vivado
   *RTL Analysis → Schematic* + utilization/timing/power numbers. (Or locally via Yosys.)
   This is the highest-impact "it's a real circuit, not a script" proof — put it on the
   Architecture and Results slides. **Currently our biggest missing artifact — get it early.**

## Demo script (the story arc)
Narrate the story trace live: healthy crop → soil dries → **pump auto-fires** → recovers
→ a **weed** is caught by abnormal depletion → a **heat** spike (and note the chip does
NOT mistake heat-evaporation for a weed). The event log timestamps each moment.

## Done when
Deck is complete, demo is rehearsed end-to-end, and every claim is backed by a shown result.
