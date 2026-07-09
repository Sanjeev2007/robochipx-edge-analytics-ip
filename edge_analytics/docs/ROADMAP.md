# Roadmap — Smart Agriculture Edge Analytics IP (4 people, 24h)

> Strategy: build the **mandatory core first** (an always-working demo), THEN layer
> bonus features. Integrate continuously — do NOT save integration for the end.

---

## Build tiers

### Tier 0 — MANDATORY CORE (must-have MVP)  → target: working end-to-end by ~hour 12
| Module | Role | Mandatory feature | Status |
|---|---|---|---|
| `sensor_collector` | 3 channels (moisture, nutrient, temp) + timestamp | #1 | ⬜ |
| `moving_avg` | Smooth each noisy channel | #2 | ✅ done |
| `analytics_engine` | Fixed thresholds → SAFE/WARNING/CRITICAL status | #3 | ⬜ |
| `output_analytics` | `pump_on`, `alert_nutrient`, `alert_weed`, status outputs | #4 | ⬜ |
| `edge_analytics_top` | Wire it all together | (all) | ⬜ |
| integration testbench | Healthy → dry-spell → recovery demo trace | — | ⬜ |

### Tier 1 — BONUS: smart RTL (high value, achievable)
| Module | Role | Bonus |
|---|---|---|
| `adaptive_anomaly` (TEDA) | Running mean+variance; flags `(x−μ)² > m²·V` (Chebyshev). Self-calibrating, no fixed thresholds, divider-free. **See BUILD_PLAN 8F for the datapath.** | AI-driven anomaly detection |
| `crop_health` (joint) | Fuse moisture+nutrient+temp into one *correlated* health score (combinations, not lone thresholds) | Multi-sensor fusion |
| temp-compensated weed logic | Fast depletion + normal temp = weed; + high temp = evaporation | fusion / anomaly |
| ~~extra channels (humidity, light)~~ | **Dropped:** would break the frozen 17-field dashboard contract. Make fusion smarter, not wider. | — |

### Tier 2 — BONUS: interface + demo
| Module / task | Role | Bonus |
|---|---|---|
| `uart_tx` | Packetize status/alerts into bytes, stream out | Cloud sync (chip egress half) |
| host dashboard (Python) | Read the UART/packet stream, show a live dashboard | Cloud sync (dashboard half) |
| smarter irrigation | Pump control with hysteresis (avoid rapid on/off) | polish |

### Tier 1.5 — DIFFERENTIATOR BONUS (added after judge feedback — see BUILD_PLAN Phase 8)
> Judge feedback: the design reads as "just automation, nothing unique," and pushed for
> a **caretaker communication system**. This tier is the answer. Build 8A + 8B; 8C/8D
> are near-free. Full detail in `BUILD_PLAN.md` Phase 8 and `INTERFACES.md` §6.
| Module / task | Role | Bonus |
|---|---|---|
| `comms_tx` ⭐ | **Two-tier response:** event-triggered alert packet (with a recommended *action*) to the remote caretaker over low-power radio — not just a dashboard | Differentiator: machine-to-human comms |
| **JOINT fusion** (8C) | Upgrade `crop_health` from OR-of-thresholds → correlated/interaction-aware judgment (NO humidity — keeps the 3-ch dashboard contract) | Multi-sensor fusion (headline) |
| **`adaptive_anomaly` TEDA** (8F) ⭐ | Self-tuning: running μ+σ², test `(x−μ)² > m²·V`, divider-free. Drawable datapath (multiplier + feedback state) | AI-at-edge anomaly + VLSI credibility |
| edge-win quantification (8D) | Count samples-processed vs packets-transmitted → % data / radio-on saved | Proof the edge design pays off |
| `predictor` (8B, lowest pri) | Extrapolate the moisture-depletion slope (divider-free) → warn *before* dry-out | Predictive / trend analytics |

### Tier 3 — STRETCH / wow (only if ahead of schedule)
- **Multi-zone:** replicate the pipeline for N plants/zones + aggregate (scalability story).
- **UART realism:** serialize `comms_tx` alert packets to real bytes (`uart_tx.v`).
- **Low-power story:** clock-gate the datapath when idle (real edge concern).

---

## 4-person work split (tooling-aware)

Reality: only the team lead has a Mac + Claude Code (fast RTL generation + local
`iverilog`/`gtkwave`). The other three are on Windows. So the lead is the RTL
**hub/integrator**; the others take tracks that don't need the Mac.

Note: `iverilog` also runs on Windows, and EDA Playground (edaplayground.com) is a
free in-browser simulator — so teammates CAN write/test RTL too if they want; they
push to GitHub and the lead integrates.

Deliverable is simulation-only, BUT **the judge explicitly mentioned FPGA** — so
**FPGA synthesis is now ELEVATED from optional bonus to an expected deliverable.** We must
show the design is real FPGA-able hardware: run it through Vivado/Quartus (or local Yosys)
→ **synthesized schematic + utilization/timing/power on a real FPGA target** (e.g. Xilinx
Artix-7 xc7a35t / Basys-3). Actual board deployment is still a stretch, but the FPGA
synthesis reports + schematic are no longer skippable. See `SYNTHESIS_TASKS.md` + Phase 8G.

- **You — RTL Lead & Integrator** (Mac + Claude Code): generate all core + bonus
  modules and testbenches, run all sims, capture waveforms, own
  `edge_analytics_top` integration, keep `main` working, publish the interface
  contract.
- **Teammate B — Synthesis & HW reports** (Windows + Vivado/Quartus): pull RTL,
  synthesize, fix synth warnings, capture resource/timing/schematic screenshots
  for the slides. Can also run iverilog on Windows to help test blocks.
- **Teammate C — Dashboard & Data** (any OS + Python): build the dashboard that
  reads the chip's output stream (cloud-sync bonus); research realistic sensor
  ranges; craft the demo data traces (healthy / dry spell / weed / heatwave).
- **Teammate D — Story, Slides & Docs** (any OS): block diagrams, SDG framing,
  feature-coverage table, pitch, demo script, README polish.

> `moving_avg` is already built and reused by everyone (instantiate one per channel).
> The lead MUST keep the interface contract (boundary-signal table) published and
> stable — B synthesizes against it, C parses the output format, D diagrams it.

---

## Rough 24h timeline
| Hours | Focus |
|---|---|
| 0–2 | Repo setup; **agree module interfaces / signal names** (critical for parallel work); stub every module so it compiles |
| 2–12 | Build Tier 0 in parallel → **MVP end-to-end simulation working** |
| 12–18 | Layer Tier 1 (adaptive anomaly, fusion) + Tier 2 (UART, dashboard) |
| 18–22 | Integration, polish, realistic demo trace, capture waveforms |
| 22–24 | Slides, rehearse the demo, buffer for surprises |

## Hackathon survival rules
1. **Freeze interfaces early** — 4 people can only work in parallel if the port
   lists / signal names are fixed up front. Change them rarely and loudly.
2. **Always keep a working demo.** Commit the MVP the moment it runs; never leave
   `main` broken.
3. **Integrate continuously**, not at hour 23. Most hackathon deaths are at the
   integration step.
4. **Bonuses are optional.** If time slips, ship Tier 0 + whatever Tier 1/2 is done.
