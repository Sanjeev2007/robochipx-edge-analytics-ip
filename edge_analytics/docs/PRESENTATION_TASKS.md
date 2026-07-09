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
3. **Architecture** — the pipeline: sensors → smoothing → analytics → auto-actions.
4. **Features** — the detect→act table (waters, feeds, spots weeds, ignores bad sensors).
5. **The edge advantage** — decides in microseconds, on-device, no cloud.
6. **Results** — waveforms (raw vs smoothed), the live dashboard + event log, synthesis
   numbers ("3% of chip, 150 MHz, 40 mW"). This is the proof section.
7. **Requirements coverage** — mandatory 1–4 all done + bonuses (anomaly, fusion, cloud egress).
8. **SDG alignment + future** (multi-zone, predictive watering, real FPGA).

## Demo script (the story arc)
Narrate the story trace live: healthy crop → soil dries → **pump auto-fires** → recovers
→ a **weed** is caught by abnormal depletion → a **heat** spike (and note the chip does
NOT mistake heat-evaporation for a weed). The event log timestamps each moment.

## Done when
Deck is complete, demo is rehearsed end-to-end, and every claim is backed by a shown result.
