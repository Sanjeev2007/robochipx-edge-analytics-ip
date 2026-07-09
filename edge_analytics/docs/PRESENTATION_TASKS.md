# Presentation & Docs — Task Sheet

**Branch:** `presentation`  ·  Owns: the pitch deck, demo script, and doc polish.
Presentation is a big share of the hackathon score — this is a full-time role.

---

## Goal
A slide deck + a rehearsed demo that tells the story clearly, backed by our real
results (waveforms, synthesis numbers, live dashboard).

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
8. **SDG alignment + future** (multi-zone, predictive watering, real FPGA).

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

## Demo script (the story arc)
Narrate the story trace live: healthy crop → soil dries → **pump auto-fires** → recovers
→ a **weed** is caught by abnormal depletion → a **heat** spike (and note the chip does
NOT mistake heat-evaporation for a weed). The event log timestamps each moment.

## Done when
Deck is complete, demo is rehearsed end-to-end, and every claim is backed by a shown result.
