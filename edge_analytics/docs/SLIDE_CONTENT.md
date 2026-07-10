# Slide Content — paste-ready for the 10-slide RCX template

> Fill each slide with the text below. **Real numbers only** (no fabricated Fmax/power).
> Images live in `synthesis/` and `demo/`. Speaker notes = what to SAY out loud.
> **Google Slides can't import SVG — insert the `.png` versions** (Insert → Image → Upload from computer).

---

## Slide 1 — TITLE
**Edge Analytics IP — a self-tuning sensor-analytics chip for Precision Agriculture**
- Team ID: `<fill>`   ·   Track: Chip Design   ·   Team name: `<fill>`
- Members: `<fill>`
- Tagline: *"Edge analytics in silicon, not the cloud."*

**Say:** "We built a chip-level IP core that does sensor analytics on-device — no cloud."

---

## Slide 2 — PROBLEM STATEMENT
- **The problem:** IoT sensor networks drown in raw data. Sending it all to the cloud costs latency, bandwidth, privacy, and — on a battery field-node — **the radio drains the battery**.
- **Who it hurts:** farmers running many field nodes, and a caretaker who may be kilometres away.
- **Gaps in what exists today:**
  - Dumb nodes **stream every reading** → the radio never sleeps → dead batteries.
  - Generic automation is **one-size-fits-all** — can't adapt per crop, soil, or node.
  - Hand-tuned thresholds **don't scale** to thousands of varied fields.
- SDG 9 (Industry & Infrastructure) · SDG 11 (Sustainable Communities)

**Say:** "The issue isn't sensing — it's that every node ships all its data to the cloud and burns its battery talking. And generic automation can't adapt or scale."

---

## Slide 3 — METHODOLOGY PROPOSED  ⭐ (the differentiator slide)
**An on-chip Edge Analytics IP with a two-tier response.** It collects → smooths → analyzes → acts, entirely on-device. What makes it different:
- **① TEDA self-tuning anomaly** — the chip *learns each field's own "normal"* (running mean+variance, Chebyshev bound, divider-free). No hand-tuned thresholds → it scales to thousands of nodes.
- **② Joint / correlated fusion** — reasons about sensor *combinations*, not one channel at a time; catches "combined stress" that single thresholds miss.
- **③ Two-tier triage** — Tier-1 acts locally (pump/doser); Tier-2 stays **silent** and transmits the caretaker **one tiny alert only when a human is truly needed** — **~97% fewer transmissions** (6 alerts vs 223 samples) for the same outcome.
- **④ It's real silicon** — synthesizable RTL, proven in simulation, maps to a real FPGA.

**Image:** a screenshot of `demo/mission_control.html` (the **Tier-2 Radio Transmitter** firing an alert packet + the "dumb node vs our chip" counter mid-race).

**Say:** "No surveyed system does edge analytics in dedicated silicon — they all run software on a Pi or the cloud. We put a self-tuning analytics brain into the chip, and it only speaks to a human when it has to."

---

## Slide 4 — TECHNICAL APPROACH
- **Architecture (image: `synthesis/architecture.png`):** sensors → `sensor_collector` → `smoothing_stage` (3× moving-average) → `analytics_engine` (fusion + temp-compensated weed) **+** `adaptive_anomaly` (TEDA) → `output_analytics` → **{Tier-1 actuators | Tier-2 `comms_tx` radio}**.
- **Algorithms:** divider-free moving average (power-of-2 window); TEDA eccentricity `(x−μ)² > m²·V`; pump hysteresis; latency-aligned pipeline.
- **State machine (image: `synthesis/fsm_pump.png`):** the pump is a 2-state Moore FSM with a **200…350 hysteresis band** — turns ON at avg_moisture<200, OFF only above 350, so it never chatters. *(Small inset — shows we designed real FSMs, not just combinational logic.)*
- **Tools & flow:** Verilog RTL · Icarus Verilog + GTKWave (sim) · Yosys (synthesis) · Python (dashboard) · Git/GitHub. Design on Mac → GitHub.
- **Testing:** a testbench per module + a top-level **223-sample story-trace** with self-checks (RESULT: PASS, 0 errors).
- **Metrics (real):** **~97% fewer caretaker transmissions** (6 packets vs 223 samples); **~1,245 LUTs / 1,163 FFs / 3 DSP blocks → ~6% of an Artix-7 FPGA**.

**Say:** "Every block has its own testbench, and a 223-sample story trace verifies the whole chip end-to-end. The pump is a proper hysteresis state machine so it never oscillates. It synthesizes to about 6% of a low-end FPGA — the three DSP blocks are the anomaly-detector multipliers."

---

## Slide 5 — TECH STACK  *(template calls it "Final Reflections", but its body asks for tools — treat as Tech Stack)*
- **Languages:** Verilog (RTL), Python (dashboard).
- **Tools:** Icarus Verilog (`iverilog`/`vvp`), GTKWave, **Yosys** (+ graphviz), Tkinter, Git/GitHub.
- **Hardware target:** FPGA/ASIC IP core — simulation-proven, synthesizable (Artix-7 xc7a35t reference). Sensors: soil moisture, NPK, temperature.
- **Platform:** local (macOS) simulation + synthesis. **No cloud needed — that's the point.**

---

## Slide 6 — EXPECTED DELIVERABLE: Prototype / Model
**Layout as 3 columns — the NUMBERS + a WAVEFORM are the hero, the netlist is just a small "it's real" thumbnail.**

- **① Utilization (big text — the hero):** **~1,245 LUTs · 1,163 FFs · 3 DSPs · ~6% of an Artix-7 (xc7a35t)**. The 3 DSPs = the TEDA anomaly multipliers.
- **② Netlist thumbnail (small, captioned):** `synthesis/schematic_top_block_thumb.png` (pre-shrunk, 1100px, light) — caption *"Yosys netlist — synthesizes to real gates."* Don't try to make it readable; it's proof-of-synthesis, not a diagram.
- **③ Waveform (image: `synthesis/waveform_anomaly_radio.png`):** the cycle-by-cycle proof it actually runs — TEDA flags a channel → the Tier-2 radio transmits one 64-bit packet. *(This is the artifact chip judges expect — answers "did it run?" with a picture.)*
- Caption line: *"Synthesizes to real gates AND verified cycle-by-cycle."*
- (Honest: utilization from Yosys synthesis; timing/power would need Vivado P&R — not claimed.)

**Say:** "It's not slideware — it synthesizes to about 6% of a real FPGA, and here's the waveform: the anomaly detector fires and the radio transmits exactly one packet, on the right clock edge."

---

## Slide 7 — EXPECTED DELIVERABLE: Documentation / Research
**Make the hero a screenshot of the crop-profile data TABLE (`docs/CROP_PROFILE_DATA.md`) — that's research made concrete. The judges never saw the docs; show them the grounding.**

- **Literature reviewed → drove our design choices:**
  - Lozoya et al. 2021 (*Sensors*) — event-triggered irrigation saves ~20% power → *this is why we do sparse Tier-2 transmission.*
  - Angelov — TEDA (Typicality & Eccentricity) → *this is the self-tuning anomaly algorithm we put in silicon.*
- **Agronomy grounded (show the table):** thresholds aren't guessed — moisture / NPK setpoints for **4 crops × 3 soils** come from **FAO-56** (crop coefficients / depletion) and **USDA NRCS** (soil water capacity), all cited in `CROP_PROFILE_DATA.md`.
- **Headline finding:** *no surveyed system does the analytics in dedicated RTL/silicon* — that's our contribution.

**Say:** "Our thresholds aren't made up — they're from FAO-56 and USDA soil data, one profile per crop and soil type. And the literature is where our two big ideas came from: event-triggered radio to save power, and TEDA to self-tune. Nobody in the survey put that analytics in actual silicon — we did."

---

## Slide 8 — EXPECTED DELIVERABLE: Working demo
- **Mission Control** (`demo/mission_control.html`) — a live animated dashboard replaying the **real** 223-sample sim: 3 sensor graphs (raw+smoothed) + analytics charts (crop-health, depletion-rate) + status gauge + live-feature tiles (pump/doser/weed/fusion/TEDA, each with an info tooltip) + the **Tier-2 Radio Transmitter** + the **dumb-node-vs-our-chip** counter ending at **223 vs 6 → ~97%**.
- Backed by: the `iverilog` sim (RESULT: PASS) + the synthesized schematic.

**Image/video:** screen-recording of Mission Control + a screenshot.
**Say:** "This is the real chip output, replayed — watch the dumb node hit 223 transmissions while our chip stays silent and sends 6 precise, actionable alerts."

---

## Slide 9 — REFERENCES
- Lozoya et al. (2021), *Sensors* 21:5541 — event-triggered irrigation (85% / ~20% power).
- Angelov — TEDA (Typicality & Eccentricity Data Analytics); TEDA-on-FPGA work.
- Allen et al. (1998), **FAO-56** — crop coefficients / depletion; **USDA NRCS** — soil water capacity; land-grant extension NPK guides.
- Tools: Icarus Verilog, Yosys, GTKWave docs. SDG 9 & 11.

---

## Slide 10 — Closing
- "Edge analytics, in silicon — it decides on-device and only speaks when it matters."
- Repo: `github.com/Sanjeev2007/robochipx-edge-analytics-ip`  ·  Thank you / Questions.

---

# 🎤 EVALUATION PREP — demo script + likely questions

### Demo script (90 seconds)
1. Open Mission Control, hit play. "Healthy field, sensors smoothing in real time."
2. Dry spell → **pump auto-fires** (Tier-1, no human). Recovers.
3. **Weed** caught by abnormal depletion — *"note: normal temperature, so it's theft, not evaporation."*
4. Heat spike → fast drop but **weed suppressed** (temperature compensation).
5. **Sensor anomaly** → TEDA flags it → the **Tier-2 Radio Transmitter fires** one alert packet: "CHECK SENSOR."
6. End on the counter: **"223 radio transmissions for a dumb node, 6 for ours — ~97% fewer, same crop outcome. That silence is why it runs at the edge."**

### Grill Q&A (rehearse these)
- **"It's too common / just automation."** → "Automation is only Tier-1. The novelty is on-chip *triage* — the chip decides *whether a human is needed* and self-tunes per field. That's ~97% less radio traffic (6 alerts vs 223 samples) and it's in dedicated silicon, which no surveyed system does."
- **"Did it run on real hardware?"** → "It's simulation-proven and synthesizable — Yosys maps it to ~6% of an Artix-7, 3 DSP blocks for the anomaly math. *(point at the waveform)* Here's the actual cycle-by-cycle trace — the anomaly fires and the radio transmits one packet on the right clock edge. Full board bring-up is next; the RTL is FPGA-ready."
- **"Show me it actually works at the signal level."** → *(Slide 6 waveform)* "This is the real VCD from the simulation. Left waveform: TEDA flags a channel, `alert_anomaly` goes high, `msg_valid` strobes for one cycle, `msg_count` increments, and the 64-bit packet changes. Second waveform: raw moisture is noisy, the moving average smooths it, and the pump engages with hysteresis — closed-loop, no human."
- **"What's the clock speed / power?"** → "Those need place-and-route (Vivado), which we didn't run, so we don't quote a number. The design is small and fully pipelined, so timing closure on a modest FPGA isn't a concern." *(Never invent an MHz/mW figure.)*
- **"Your dashboard streams every sample — where's the saving?"** → "Two different links. The dashboard is the cheap on-site/wired link. The ~97% applies to the long-range battery caretaker radio — that's the one that stays silent."
- **"Is the data real?"** → "We drive the chip with directed test scenarios that model real field conditions — that's standard RTL verification. The agronomic setpoints (FAO-56, USDA) are real and cited."
- **"How does weed detection work without a camera?"** → "A weed steals water, so moisture drops abnormally fast. We detect the rate, and suppress it when it's hot (that's evaporation, not theft) — sensor fusion, no vision needed."
