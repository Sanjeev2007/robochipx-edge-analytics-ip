# Hackathon AI Agent Instructions (ROBOCHIPX '26)

### 🚨 CRITICAL CONTEXT FOR THE AGENT
* **User Knowledge Level:** Beginner / First-time hackathon participant. No deep prior background in VLSI, chip design, or HDLs.
* **Development Environment:** macOS (MacBook Air). Using local CLI tools (`icarus-verilog` and `gtkwave`) for local simulation.
* **Team Pipeline:** Design/Simulation happens here on Mac ➔ Code pushed to GitHub ➔ Teammates pull to Windows for final Synthesis/Compilation (Vivado/Quartus).

---

## 🛠️ CODE GENERATION RULES
1. **Synthesizable Verilog Only:** Always write standard, synthesizable Verilog. Avoid complex sequential software-like constructs. 
2. **Explicit Comments:** Every module generated must include clear comments explaining what the inputs, outputs, registers, and logic blocks do in plain English.
3. **No Code Dumps:** Do not build massive architectures in a single prompt. Break everything down into tiny, modular, testable blocks. Generate the block, then immediately generate its testbench.
4. **Clock & Reset Standards:** Always explicitly include `clk` and `rst` signals for sequential logic modules.

---

## 💻 GIT & COLLABORATION WORKFLOW
The user is working on shared remote branches with a team. Every time you are asked to handle Git actions, follow these exact protocols to prevent code loss:
* **Pulling:** Always run `git pull` or verify the local branch status before beginning a code edit session.
* **Branching:** Safely fetch and checkout remote tracking branches when requested (e.g., `git fetch --all` and `git checkout <branch>`).
* **Committing:** Stage files cleanly and write descriptive, concise commit messages (e.g., `git commit -m "feat: added 8-bit ALU control logic module"`).
* **Conflicts:** If a merge conflict occurs, analyze the git markers, prioritize keeping both changes if logical, or safely resolve the conflict so the HDL compiles. Explain the resolution briefly to the user.

---

## 📊 SIMULATION RUN COMMANDS
When generating or modifying a design block and its testbench, provide or execute the local compilation command for the user:
* Compilation: `iverilog -o simulation.vvp <design_file>.v <testbench_file>.v`
* Execution: `vvp simulation.vvp`
* Waveform Analysis: Ensure testbenches generate a VCD dump file (e.g., `dump.vcd`) so the user can open it instantly using `gtkwave dump.vcd`.

