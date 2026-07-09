# Synthesis Report — Edge Analytics IP (Phase 8G, "it's real silicon")

**Tool:** Yosys 0.66 (open-source RTL synthesis), run locally on macOS. No Vivado/Windows needed.
**Design:** full chip, top = `edge_analytics_top` (8 RTL modules, testbenches excluded).
**What this proves:** the Verilog is genuinely **synthesizable to real hardware** — it maps to
actual FPGA primitives (LUTs, flip-flops, DSP blocks, carry chains), not just a simulation.

---

## 1. FPGA utilization (Xilinx Artix-7, `synth_xilinx`)

| Resource | Used | Xilinx Artix-7 **xc7a35t** (Basys-3 board) | % used |
|---|---|---|---|
| LUTs (LUT1–6) | **1,245** | 20,800 | **~6 %** |
| Flip-flops (FDRE) | **1,163** | 41,600 | **~3 %** |
| **DSP48E1** | **3** | 90 | **~3 %** |
| CARRY4 (adder chains) | 200 | — | — |
| MUXF7 / MUXF8 | 119 / 42 | — | — |
| Block RAM | 0 | 50 | 0 % |

**The whole chip fits in ~6 % of an entry-level student FPGA.** 

**The 3 DSP48E1 blocks are the headline detail** — those are the **TEDA self-tuning anomaly
multipliers** (one per sensor channel: the `(x−μ)²` eccentricity term). The synthesizer mapped
our divider-free statistics straight onto dedicated DSP hardware. The 200 CARRY4 chains are the
moving-average / analytics adders; the 1,163 FFs are the fully-registered pipeline state.

Generic (technology-independent) synthesis gives **~7,471 cells** total, of which the TEDA block
(`adaptive_anomaly`) is the largest (~5,500) — expected, it carries the multipliers.

## 2. Schematics (in this folder)

- **`schematic_top_block.png` / `.svg`** — the whole chip as a synthesized netlist: all six
  module blocks (`sensor_collector → smoothing_stage → adaptive_anomaly + analytics_engine →
  output_analytics → comms_tx`) wired left-to-right with the pipeline delay registers between
  stages. This is the "real circuit, not a script" architecture slide.
- **`schematic_moving_avg.png` / `.svg`** — one module up close (coarse RTL cells): the 8-tap
  shift register (`buffer[0..7]`), flip-flops, and the running-accumulator add/sub + shift-divide.
  The clean "here are the actual gates" example.

## 3. Reproduce (all on macOS, `brew install yosys graphviz`)

```bash
cd edge_analytics
DESIGN="edge_analytics_top.v sensor_collector.v smoothing_stage.v moving_avg.v \
        analytics_engine.v output_analytics.v adaptive_anomaly.v comms_tx.v"

# FPGA utilization numbers:
yosys -p "read_verilog $DESIGN; synth_xilinx -top edge_analytics_top; stat"

# Top-level architecture schematic:
yosys -p "read_verilog $DESIGN; hierarchy -top edge_analytics_top; proc; opt_clean; \
          show -format svg -prefix synthesis/schematic_top_block -notitle edge_analytics_top"

# Clean single-module schematic:
yosys -p "read_verilog moving_avg.v; prep -top moving_avg; \
          show -format svg -prefix synthesis/schematic_moving_avg -notitle moving_avg"
```

## 4. ⚠️ Honesty note — what we CAN and CANNOT claim (read before the pitch)

- ✅ **CAN claim:** "synthesizable; maps to ~1,245 LUTs / 1,163 FFs / **3 DSP blocks** on an
  Artix-7; ~6 % of a low-end FPGA; the TEDA anomaly math becomes real DSP hardware." All from
  Yosys synthesis — reproducible above.
- ❌ **Do NOT quote a clock frequency (Fmax) or power (mW).** Yosys does synthesis, **not**
  place-and-route or static timing/power analysis — those need a full P&R tool (Vivado). Any
  MHz/mW number would be **fabricated**; a chip judge will catch it. If asked about timing:
  *"utilization is from Yosys synthesis; full timing/power would come from Vivado P&R, which we
  didn't run — but the design is small (~6 % LUTs) and fully pipelined/single-cycle-per-stage,
  so timing closure on a modest FPGA is not a concern."* Honest and defensible.
