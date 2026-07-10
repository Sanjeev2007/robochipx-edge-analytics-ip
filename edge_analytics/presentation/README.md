# 📊 Presentation — everything for the ROBOCHIPX '26 evaluation

Everything you need on the day is in this folder. Nothing to build — this is presentation only.

## Files here
- **`PROJECT_OVERVIEW.md`** — read this first if you're new to the project. One page: what it
  is, the hackathon context, how it's built, and the honest headline numbers.
- **`JUDGE_CHEATSHEET.md`** — keep this open on your phone during Q&A. 30-sec pitch, the 5
  questions judges ask + your real answers, the "I don't know" script, the real numbers.
- **`images/`** — all slide-ready PNGs in one place (Google Slides can't import SVG → use these):
  | File | Goes on slide |
  |---|---|
  | `architecture.png` | Technical Approach (block diagram — says "~97% fewer TX") |
  | `waveform_anomaly_radio.png` | Expected Deliverable (TEDA → radio, cycle-by-cycle) |
  | `waveform_pump_control.png` | backup / Q&A (moisture smoothing → pump hysteresis) |
  | `fsm_pump.png` | Technical Approach inset (2-state pump FSM) |
  | `schematic_top_block_thumb.png` | Expected Deliverable (netlist "real gates" thumbnail) |

## Slide text (source of truth)
Paste-ready content for all 10 slides + demo script lives in **`../docs/SLIDE_CONTENT.md`**.

## The live demo
Open **`../demo/mission_control.html`** in a browser, press Play, let it run to the end
(t=223) — the counter settles at **223 vs 6 → 97%**. Screen-record this for ~90 seconds.
Demo script is at the bottom of `../docs/SLIDE_CONTENT.md`.

## The honest numbers (do not exceed)
- **6 packets vs 223 samples → ~97% fewer transmissions**
- **~1,245 LUTs · 1,163 FFs · 3 DSPs · ~6% of an Artix-7 (xc7a35t)**
- Story trace: **223 samples, PASS, 0 errors**
- ❌ NO Fmax / NO power number (needs Vivado P&R — say so).

## Pre-flight checklist
- [ ] Deck: all "%"s read **97**, image + text agree (radio panel + architecture diagram)
- [ ] Demo recorded (Mission Control, ends on 97%)
- [ ] Rehearsed the 30-sec pitch + the 5 Q&A answers out loud once
- [ ] `mission_control.html` opens & plays on the presenting machine (test it!)
- [ ] Waveform slide ready to pull up if a judge goes deep
