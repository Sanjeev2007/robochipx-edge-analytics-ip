# 🎤 Judge Cheat Sheet — keep this open on your phone during Q&A

## THE #1 RULE — honesty beats expertise
Say this if asked how you built it:
> *"I'm new to VLSI — I used AI to accelerate the RTL, but I understand the
> architecture and the tradeoffs, and I verified every block. Let me walk you through it."*

Never bluff. Industry judges reward **"I don't know"** over confident wrongness.
When stuck: *"I don't know that off the top of my head — what I do know is ___, and I'd
check ___."*

---

## THE 30-SECOND PITCH (say it in your sleep)
> *"An on-chip Edge Analytics IP for precision agriculture. It collects → smooths →
> analyzes → acts, entirely on-device. It self-tunes to each field with TEDA, and it
> only radios a human when one is truly needed — 6 alerts instead of 223 samples,
> ~97% fewer transmissions. It's real synthesizable silicon, not software on a Pi."*

---

## THE 5 QUESTIONS THEY WILL ASK — your real answers

**1. "Why divider-free? Why not just divide?"**
> Dividers are big and slow in hardware — no cheap divide primitive. Our moving average
> uses a power-of-2 window, so it's just an add + a shift. TEDA avoids division too:
> instead of variance we compare `(x−μ)² > m²·V` — one multiply, no divide.

**2. "Why 3 DSP blocks?"**
> One multiplier per channel for the TEDA eccentricity test — moisture, nutrient, temp.
> Yosys maps each to a DSP48. Everything else is LUTs + the pipeline flip-flops.

**3. "Clock speed / will it meet timing?"**
> I won't quote an Fmax — that needs place-and-route in Vivado, which I didn't run, so
> any number would be made up. What I can say: it's small (~6% of an Artix-7), fully
> pipelined, no long combinational chains, so timing on a modest FPGA isn't a concern.
> *(Refusing to fabricate a number is a GREEN flag to them.)*

**4. "Walk me through one sample."** *(point at the block diagram)*
> Sensors → `sensor_collector` timestamps it → `smoothing_stage` runs the 3 moving
> averages → `analytics_engine` + `adaptive_anomaly` decide in parallel →
> `output_analytics` fires the pump locally (Tier-1) or, only on a real event,
> `comms_tx` sends one packet (Tier-2).

**5. "How do you know it's correct?"** *(pull up the waveform slide)*
> Every module has its own testbench, plus a 223-sample top-level story trace with
> self-checks — PASS, 0 errors. Here's the waveform proving it cycle-by-cycle.

---

## MORE LIKELY QUESTIONS (from the deck)

- **"It's too common / just automation."** → Automation is only Tier-1. The novelty is
  on-chip *triage* — the chip decides *whether a human is needed* and self-tunes per
  field. ~97% less radio traffic, in dedicated silicon — no surveyed system does that.
- **"Did it run on real hardware?"** → Simulation-proven + synthesizable; Yosys maps it
  to ~6% of an Artix-7, 3 DSPs for the anomaly math. Here's the waveform. Board bring-up
  is next; the RTL is FPGA-ready.
- **"Your dashboard streams every sample — where's the saving?"** → Two different links.
  The dashboard is the cheap on-site/wired link. The ~97% is the long-range *battery*
  caretaker radio — that's the one that stays silent.
- **"Is the data real?"** → Directed test scenarios that model real field conditions —
  standard RTL verification. The agronomic setpoints (FAO-56, USDA) are real and cited.
- **"How does weed detection work without a camera?"** → A weed steals water, so moisture
  drops abnormally fast. We detect the *rate*, and suppress it when it's hot (that's
  evaporation, not theft) — sensor fusion, no vision needed.

---

## STEER EVERY OPENING TO YOUR 3 FLEXES
1. **Real synthesizable silicon** — not a Pi running Python.
2. **Self-tuning TEDA** — scales to thousands of nodes with no hand-tuning.
3. **~97% fewer transmissions** (6 vs 223) — battery life at the edge.

## THE REAL NUMBERS (never fabricate beyond these)
- 6 caretaker packets vs 223 samples → **~97% fewer transmissions**
- **~1,245 LUTs · 1,163 FFs · 3 DSPs · ~6% of an Artix-7 (xc7a35t)**
- Story trace: **223 samples, PASS, 0 errors**
- ❌ NO Fmax, NO power figure — those need Vivado place-and-route (say so plainly).
