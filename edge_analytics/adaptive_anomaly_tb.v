// adaptive_anomaly_tb.v
// -----------------------------------------------------------------------------
// Testbench for the Phase-8F TEDA adaptive anomaly detector.
//
// THE PROOF WE WANT (why TEDA beats a fixed check):
//   Channel 0 (moisture) sits at ~600 +/- ~12 (its own "normal"), then SPIKES to
//   660.  660 is NOT a rail (not 0, not 4095), so the OLD fixed rail-check
//   (x==0 || x==4095) MISSES it completely.  The learned TEDA detector, having
//   calibrated mu~600 and a small variance, sees (660-mu)^2 blow past 9*V and
//   FLAGS it.  Meanwhile channels 1 (nutrient=300) and 2 (temp=250) sit steady and
//   must NOT flag.
//
// We also confirm:
//   - NO false flag during warm-up (early samples suppressed even though the raw
//     statistics are noisy while mu/V settle).
//   - NO false flag on ordinary +/- jitter after warm-up.
//   - The flag lands on channel 0 ONLY (anom_ch == 3'b001) at the spike.
//   - After the spike the detector returns quiet (no lingering flag).
//
// TIMING: outputs are registered (1-cycle latency).  We drive one sample per clock
// on the negedge, then sample the outputs just after the following posedge - so the
// outputs we read belong to the sample we just drove.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module adaptive_anomaly_tb;

    // ---- Params mirrored from the DUT (named, no magic numbers) ------------------
    localparam DATA_WIDTH  = 12;
    localparam NUM_CH      = 3;
    localparam TEDA_WARMUP = 8;
    localparam NSAMP       = 30;      // total samples driven
    localparam SPIKE_IDX   = 24;      // index where moisture spikes to 660
    localparam SPIKE_VAL   = 12'd660; // the off-baseline (but NOT railed) spike

    // ---- DUT I/O -----------------------------------------------------------------
    reg                   clk;
    reg                   rst;
    reg                   in_valid;
    reg  [DATA_WIDTH-1:0] avg_moisture;
    reg  [DATA_WIDTH-1:0] avg_nutrient;
    reg  [DATA_WIDTH-1:0] avg_temp;
    wire                  anomaly;
    wire [NUM_CH-1:0]     anom_ch;

    // ---- Device under test -------------------------------------------------------
    adaptive_anomaly #(
        .DATA_WIDTH  (DATA_WIDTH),
        .NUM_CH      (NUM_CH),
        .TEDA_SIGMA_M(3),
        .TEDA_ALPHA  (3),
        .TEDA_WARMUP (TEDA_WARMUP)
    ) dut (
        .clk         (clk),
        .rst         (rst),
        .in_valid    (in_valid),
        .avg_moisture(avg_moisture),
        .avg_nutrient(avg_nutrient),
        .avg_temp    (avg_temp),
        .anomaly     (anomaly),
        .anom_ch     (anom_ch)
    );

    // ---- Clock: 10 ns period -----------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---- Moisture stimulus: ~600 +/- ~12 baseline, one 660 spike at SPIKE_IDX ----
    // Small jitter (within +/-12) keeps the learned variance modest so the spike is
    // unambiguous, while never itself looking like an outlier after warm-up.
    reg [DATA_WIDTH-1:0] mo_seq [0:NSAMP-1];
    integer k;
    initial begin
        mo_seq[0]  = 12'd600; mo_seq[1]  = 12'd606; mo_seq[2]  = 12'd594;
        mo_seq[3]  = 12'd604; mo_seq[4]  = 12'd596; mo_seq[5]  = 12'd608;
        mo_seq[6]  = 12'd592; mo_seq[7]  = 12'd602; mo_seq[8]  = 12'd598;
        mo_seq[9]  = 12'd605; mo_seq[10] = 12'd595; mo_seq[11] = 12'd603;
        mo_seq[12] = 12'd597; mo_seq[13] = 12'd607; mo_seq[14] = 12'd593;
        mo_seq[15] = 12'd601; mo_seq[16] = 12'd599; mo_seq[17] = 12'd604;
        mo_seq[18] = 12'd596; mo_seq[19] = 12'd602; mo_seq[20] = 12'd598;
        mo_seq[21] = 12'd606; mo_seq[22] = 12'd594; mo_seq[23] = 12'd600;
        mo_seq[24] = SPIKE_VAL; // <-- the spike (index 24), NOT a rail
        mo_seq[25] = 12'd600; mo_seq[26] = 12'd604; mo_seq[27] = 12'd596;
        mo_seq[28] = 12'd602; mo_seq[29] = 12'd598;
    end

    // ---- Self-check bookkeeping --------------------------------------------------
    integer errors;
    integer i;
    reg     exp_anom;          // expected anomaly for the sample just driven
    reg     rail_would_flag;   // what the OLD fixed rail-check would say
    reg     spike_seen_teda;   // did TEDA catch the spike?
    reg     spike_seen_rail;   // would the fixed rail-check have caught it?

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, adaptive_anomaly_tb);

        errors          = 0;
        spike_seen_teda = 1'b0;
        spike_seen_rail = 1'b0;

        // ---- Reset ----
        rst          = 1'b1;
        in_valid     = 1'b0;
        avg_moisture = 12'd0;
        avg_nutrient = 12'd300;   // channel 1 steady
        avg_temp     = 12'd250;   // channel 2 steady
        @(negedge clk);
        @(negedge clk);
        rst = 1'b0;

        $display("# idx  moisture  anomaly anom_ch  rail_check  note");
        $display("# ---  --------  ------- -------  ----------  ----");

        // ---- Drive NSAMP samples, one per clock, checking each ----
        for (i = 0; i < NSAMP; i = i + 1) begin
            @(negedge clk);
            avg_moisture = mo_seq[i];
            avg_nutrient = 12'd300;
            avg_temp     = 12'd250;
            in_valid     = 1'b1;

            // Let the registered outputs update on the coming posedge, then read them.
            @(posedge clk);
            #1;

            // What SHOULD happen for sample i:
            //  - only the moisture spike at SPIKE_IDX is a genuine anomaly,
            //  - and only once we are past warm-up (i >= TEDA_WARMUP).
            exp_anom = (i == SPIKE_IDX) && (i >= TEDA_WARMUP);

            // What the OLD fixed rail-check would have said for this sample.
            rail_would_flag = (mo_seq[i] == 12'd0) || (mo_seq[i] == 12'd4095);

            if (i == SPIKE_IDX) begin
                spike_seen_teda = anomaly;          // TEDA's verdict on the spike
                spike_seen_rail = rail_would_flag;  // fixed check's verdict
            end

            $display("# %0d  %0d  %b  %b  %b  %s",
                     i, mo_seq[i], anomaly, anom_ch, rail_would_flag,
                     (i < TEDA_WARMUP) ? "warm-up" :
                     (i == SPIKE_IDX)  ? "<== SPIKE" : "normal");

            // Check 1: anomaly matches expectation on every sample.
            if (anomaly !== exp_anom) begin
                $display("# ERROR idx=%0d: anomaly=%b expected=%b", i, anomaly, exp_anom);
                errors = errors + 1;
            end

            // Check 2: at the spike, the flag must be on channel 0 ONLY.
            if (i == SPIKE_IDX && anom_ch !== 3'b001) begin
                $display("# ERROR idx=%0d: anom_ch=%b expected 001 (moisture only)",
                         i, anom_ch);
                errors = errors + 1;
            end

            // Check 3: the steady channels 1 and 2 must NEVER flag.
            if (anom_ch[1] !== 1'b0 || anom_ch[2] !== 1'b0) begin
                $display("# ERROR idx=%0d: steady channel flagged (anom_ch=%b)",
                         i, anom_ch);
                errors = errors + 1;
            end
        end

        in_valid = 1'b0;
        @(negedge clk);

        // ---- Headline result: TEDA catches what the fixed check misses ----
        $display("#");
        $display("# ===== TEDA vs FIXED RAIL-CHECK on the 660 spike =====");
        $display("# TEDA (learned)     flagged the spike : %s", spike_seen_teda ? "YES" : "no");
        $display("# Fixed rail-check   flagged the spike : %s", spike_seen_rail ? "YES" : "no");
        if (spike_seen_teda && !spike_seen_rail)
            $display("# => TEDA CAUGHT an off-baseline outlier the fixed check WOULD MISS.");
        else begin
            $display("# => ERROR: expected TEDA=YES and fixed=no.");
            errors = errors + 1;
        end

        $display("#");
        if (errors == 0)
            $display("# RESULT: PASS (0 errors)");
        else
            $display("# RESULT: FAIL (%0d errors)", errors);

        $finish;
    end

endmodule
