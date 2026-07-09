# Synthesis & Hardware Reports — Task Sheet

**Branch:** `synthesis`  ·  Owns: FPGA synthesis + the report numbers for the slides.
(The demo sensor **data** is a separate role — see `DATA_TASKS.md`.)

**Why it matters:** hardware isn't required (we deliver simulation), so this is
*bonus credibility* — it proves our Verilog is genuinely buildable silicon and gives
real numbers ("uses 3% of the chip, runs at 150 MHz, 40 mW") for the slides.

## Setup (do this first — the install is slow)
1. Install **Xilinx Vivado** (or **Intel Quartus**) on your Windows machine.
2. Pick a target device for reporting — e.g. **Xilinx Artix-7 (Basys-3, xc7a35t)**.
3. Clone the repo, then `git checkout -b synthesis` (see `WORKFLOW.md`).

## Rolling synthesis (start NOW — 4 modules are already done)
Ready to synthesize today: `moving_avg.v`, `sensor_collector.v`, `smoothing_stage.v`,
`analytics_engine.v`, `output_analytics.v`. For each finished module as it lands:
1. New Vivado project → **Add Sources** → add the `.v` files → set the top module.
2. **Run Synthesis.** Confirm it finishes with **no errors**.
3. Note any **warnings** (inferred latches, un-reset registers, multi-driven nets) and
   report them back to the RTL lead — these are real bugs to fix early.

## Phase 6 — the big one (full chip)
When `edge_analytics_top.v` exists, synthesize the whole design and capture:
- **Utilization report** — LUTs / flip-flops / % of chip → proves "lightweight".
- **Timing report** — max frequency (Fmax) → proves "real-time".
- **Power report** — estimated mW → proves "efficient edge".
- **RTL / synthesized schematic** — screenshot for the architecture slide.

Hand those 4 items to the presentation owner. **Stop at reports** — no bitstream / no
board needed (hardware is out of scope). Don't let tool trouble block the demo.

## ⭐ The schematic is presentation-critical (judge feedback: "show the chip")
The **synthesized/RTL schematic** (item above) is our single highest-impact "it's real
silicon" visual — a judge dinged us for looking like "just automation," and a schematic
generated FROM our Verilog is hard proof it's a genuine circuit. Prioritise it, capture a
clean high-res screenshot of the whole `edge_analytics_top`, and get it to presentation early.

**No Windows/Vivado handy? Generate it locally on the Mac with Yosys** (open-source):
```bash
brew install yosys graphviz
yosys -p "read_verilog *.v; hierarchy -top edge_analytics_top; proc; opt; show -format png -prefix chip_schematic edge_analytics_top"
```
(Point `read_verilog` at the module set; `show` emits `chip_schematic.png`.) The RTL lead
can produce this even before Windows synthesis lands, so the deck is never blocked on it.
