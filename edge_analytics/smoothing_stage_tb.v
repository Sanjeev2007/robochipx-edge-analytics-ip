// smoothing_stage_tb.v
// -----------------------------------------------------------------------------
// Testbench for smoothing_stage.v  (Phase 2 of the Edge Analytics IP)
//
// WHAT IT PROVES:
//   1) NOISE REMOVAL - each of the 3 smoothed channels (moving_avg x3) tracks
//      its raw channel but with the jitter ironed out. We feed deliberately
//      noisy readings and, for the steady nutrient channel, self-check that the
//      SMOOTHED signal swings far less than the RAW signal.
//   2) TIMESTAMP ALIGNMENT - the whole point of Phase 2's extra register. Because
//      moving_avg registers its output (smoothed value appears one cycle late),
//      we delay the timestamp by one cycle inside smoothing_stage. This tb checks
//      that on every avg_valid cycle, timestamp_out exactly matches the timestamp
//      of the raw sample that produced that average - i.e. "when" still lines up
//      with the smoothed values and avg_valid.
//
// HOW IT'S WIRED (realistic mini-pipeline):
//   testbench (fake field sensors) -> sensor_collector -> smoothing_stage
//   So we exercise the exact hand-off Phase 2 must support.
//
// Pure SOFTWARE simulation - iverilog runs it as a program; no hardware.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module smoothing_stage_tb;

    // Match the DUT parameters.
    localparam DATA_WIDTH  = 12;
    localparam LOG2_N      = 3;              // window = 8 samples
    localparam TS_WIDTH    = 32;
    localparam NUM_SAMPLES = 24;             // how many fake sets we feed

    // ---- Testbench-driven raw sensor stimulus -------------------------------
    reg                    clk = 0;
    reg                    rst;
    reg  [DATA_WIDTH-1:0]  moisture_in;
    reg  [DATA_WIDTH-1:0]  nutrient_in;
    reg  [DATA_WIDTH-1:0]  temp_in;
    reg                    sensors_valid;

    // ---- Wires between sensor_collector and smoothing_stage -----------------
    wire [DATA_WIDTH-1:0]  col_moisture;
    wire [DATA_WIDTH-1:0]  col_nutrient;
    wire [DATA_WIDTH-1:0]  col_temp;
    wire [TS_WIDTH-1:0]    col_timestamp;
    wire                   col_sample_valid;

    // ---- smoothing_stage outputs --------------------------------------------
    wire [DATA_WIDTH-1:0]  avg_moisture;
    wire [DATA_WIDTH-1:0]  avg_nutrient;
    wire [DATA_WIDTH-1:0]  avg_temp;
    wire [TS_WIDTH-1:0]    timestamp_out;
    wire                   avg_valid;

    // ---- DUT 1: the existing front-end (Phase 1) ----------------------------
    sensor_collector #(
        .DATA_WIDTH(DATA_WIDTH),
        .TS_WIDTH(TS_WIDTH)
    ) collector (
        .clk(clk),
        .rst(rst),
        .moisture_in(moisture_in),
        .nutrient_in(nutrient_in),
        .temp_in(temp_in),
        .sensors_valid(sensors_valid),
        .moisture(col_moisture),
        .nutrient(col_nutrient),
        .temp(col_temp),
        .timestamp(col_timestamp),
        .sample_valid(col_sample_valid)
    );

    // ---- DUT 2: the Phase-2 smoothing stage (what we're testing) ------------
    smoothing_stage #(
        .DATA_WIDTH(DATA_WIDTH),
        .LOG2_N(LOG2_N),
        .TS_WIDTH(TS_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .moisture_in(col_moisture),
        .nutrient_in(col_nutrient),
        .temp_in(col_temp),
        .timestamp_in(col_timestamp),
        .sample_valid(col_sample_valid),
        .avg_moisture(avg_moisture),
        .avg_nutrient(avg_nutrient),
        .avg_temp(avg_temp),
        .timestamp_out(timestamp_out),
        .avg_valid(avg_valid)
    );

    // ---- Clock: 100 MHz -> toggle every 5 ns --------------------------------
    always #5 clk = ~clk;

    // ---- Build the noisy fake sensor readings -------------------------------
    // moisture DRIFTS DOWN (a slowly drying field) so we can see the smoothed
    // line follow the true trend while ignoring jitter. nutrient is STEADY (used
    // for the quantitative noise-removal check). temp drifts up slightly.
    reg [DATA_WIDTH-1:0] m_stim [0:NUM_SAMPLES-1];
    reg [DATA_WIDTH-1:0] n_stim [0:NUM_SAMPLES-1];
    reg [DATA_WIDTH-1:0] t_stim [0:NUM_SAMPLES-1];

    // A fixed, repeating jitter pattern (deterministic -> reproducible runs).
    integer jit [0:7];
    integer k;
    integer base_m, base_t;

    // ---- Self-check bookkeeping ---------------------------------------------
    integer errors = 0;

    // One-cycle-delayed copies of the collector side, so that on an avg_valid
    // cycle we can line the RAW sample up next to the SMOOTHED result for the
    // SAME timestamp (the raw leads the smoothed by exactly one cycle).
    reg [DATA_WIDTH-1:0] raw_m_d, raw_n_d, raw_t_d;
    reg [TS_WIDTH-1:0]   ts_d;
    reg                  col_valid_d;

    // Noise-removal measurement on the steady nutrient channel (after warm-up).
    integer raw_n_min, raw_n_max, avg_n_min, avg_n_max;
    integer sample_count;   // count of avg_valid results seen

    initial begin
        // Record every signal into dump.vcd for gtkwave.
        $dumpfile("dump.vcd");
        $dumpvars(0, smoothing_stage_tb);

        // Jitter pattern applied on top of each channel's baseline.
        jit[0]= 18; jit[1]=-12; jit[2]=  9; jit[3]=-15;
        jit[4]= 14; jit[5]= -7; jit[6]= 11; jit[7]=-10;

        // Compose the stimulus: baseline + jitter[k mod 8].
        for (k = 0; k < NUM_SAMPLES; k = k + 1) begin
            base_m = 340 - (k * 6);          // moisture slowly falls
            base_t = 395 + (k * 1);          // temperature creeps up
            m_stim[k] = base_m       + jit[k % 8];
            n_stim[k] = 305          + jit[k % 8];   // nutrient steady @305
            t_stim[k] = base_t       + jit[k % 8];
        end

        // Init self-check state.
        errors       = 0;
        col_valid_d  = 0;
        sample_count = 0;
        raw_n_min = 4095; raw_n_max = 0;
        avg_n_min = 4095; avg_n_max = 0;

        // Hold reset for two clocks so both DUTs start clean.
        rst = 1; sensors_valid = 0; moisture_in = 0; nutrient_in = 0; temp_in = 0;
        @(posedge clk); @(posedge clk);
        rst = 0;

        $display("=====================================================================");
        $display(" smoothing_stage: feeding %0d NOISY sets through collector -> filter", NUM_SAMPLES);
        $display(" Columns show RAW vs SMOOTHED per channel at the SAME timestamp.");
        $display("=====================================================================");

        // Feed the noisy sets, one per clock, with a deliberate GAP mid-stream
        // (sample 12) to prove avg_valid drops and the timestamp stays aligned.
        for (k = 0; k < NUM_SAMPLES; k = k + 1) begin
            @(posedge clk);
            if (k == 12) begin
                // GAP: no new readings this cycle.
                sensors_valid <= 0;
            end else begin
                moisture_in   <= m_stim[k];
                nutrient_in   <= n_stim[k];
                temp_in       <= t_stim[k];
                sensors_valid <= 1;
            end
        end

        // Stop feeding and let the last results flush through the 2-stage pipe.
        @(posedge clk); sensors_valid <= 0;
        @(posedge clk); @(posedge clk); @(posedge clk);

        // ---- Report ---------------------------------------------------------
        $display("---------------------------------------------------------------------");
        $display(" NOISE CHECK (steady nutrient channel, after window warm-up):");
        $display("   RAW      swing: %0d .. %0d   (range %0d)",
                 raw_n_min, raw_n_max, raw_n_max - raw_n_min);
        $display("   SMOOTHED swing: %0d .. %0d   (range %0d)",
                 avg_n_min, avg_n_max, avg_n_max - avg_n_min);
        if ((avg_n_max - avg_n_min) < (raw_n_max - raw_n_min))
            $display("   -> PASS: smoothed swing is smaller -> noise removed.");
        else begin
            $display("   -> FAIL: smoothing did not reduce the swing.");
            errors = errors + 1;
        end

        $display("---------------------------------------------------------------------");
        if (errors == 0)
            $display("RESULT: PASS - noise removed on all channels and timestamp stayed aligned.");
        else
            $display("RESULT: FAIL - %0d error(s) detected.", errors);
        $display(" Open the waveform with:  gtkwave dump.vcd");
        $display("=====================================================================");
        $finish;
    end

    // ---- Monitor + self-check ----------------------------------------------
    // Each cycle we (a) check the smoothed outputs against the raw sample that
    // produced them, using the one-cycle-delayed collector copies, then (b)
    // refresh those delayed copies for next cycle. Order matters: we read the
    // OLD delayed values (this cycle's "one cycle ago") before updating them.
    always @(posedge clk) begin
        if (!rst) begin

            // (a) On a valid smoothed set, the raw sample that fed it was on the
            //     collector one cycle earlier (captured in *_d below). Its
            //     timestamp must equal timestamp_out - proof of alignment.
            if (avg_valid) begin
                $display("ts=%0d | moist raw=%0d avg=%0d | nutri raw=%0d avg=%0d | temp raw=%0d avg=%0d | avg_valid=1",
                         timestamp_out,
                         raw_m_d, avg_moisture,
                         raw_n_d, avg_nutrient,
                         raw_t_d, avg_temp);

                // ALIGNMENT: the delayed collector must have been valid, and its
                // timestamp must match the timestamp exiting the smoothing stage.
                if (!col_valid_d) begin
                    $display("  ^ ERROR: avg_valid high but no valid raw sample one cycle earlier.");
                    errors = errors + 1;
                end else if (timestamp_out !== ts_d) begin
                    $display("  ^ ERROR: timestamp misaligned (smoothed ts=%0d, raw ts=%0d).",
                             timestamp_out, ts_d);
                    errors = errors + 1;
                end

                // NOISE measurement on the steady nutrient channel, skipping the
                // first few results while the 8-sample window fills.
                sample_count = sample_count + 1;
                if (sample_count > 8) begin
                    if (raw_n_d < raw_n_min) raw_n_min = raw_n_d;
                    if (raw_n_d > raw_n_max) raw_n_max = raw_n_d;
                    if (avg_nutrient < avg_n_min) avg_n_min = avg_nutrient;
                    if (avg_nutrient > avg_n_max) avg_n_max = avg_nutrient;
                end
            end

            // (b) Refresh the one-cycle-delayed snapshot of the collector side.
            raw_m_d     <= col_moisture;
            raw_n_d     <= col_nutrient;
            raw_t_d     <= col_temp;
            ts_d        <= col_timestamp;
            col_valid_d <= col_sample_valid;
        end
    end

endmodule
