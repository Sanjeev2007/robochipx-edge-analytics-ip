// adaptive_anomaly.v
// -----------------------------------------------------------------------------
// Adaptive Anomaly Detector - Phase 8F of the Edge Analytics IP.  ⭐ TEDA block.
//
// PURPOSE (the "AI at the edge" bonus, made real):
//   The old anomaly check was a FIXED rail-stuck test: flag only if a reading is
//   railed at 0 or 4095 (a totally dead sensor).  That misses a sensor that drifts
//   to a wrong-but-in-range value, or a real off-baseline spike.  This block instead
//   LEARNS each channel's own "normal" on-chip and flags statistical outliers -
//   self-calibrating, no hand-tuned threshold per field.
//
// THE ALGORITHM (TEDA, reduced to a divider-free datapath):
//   The TEDA eccentricity outlier test algebraically reduces to a clean Chebyshev
//   form:   anomaly  <=>  (x - mu)^2  >  m^2 * V
//   where mu = running mean, V = running variance, m = sigma multiplier (Chebyshev).
//   There is NO division in the test itself.  Per channel we keep two state
//   registers - mu (mean) and V (variance) - updated every valid sample by an
//   EXPONENTIAL MOVING AVERAGE done with a SHIFT, never a divide:
//       diff  = x - mu                        // subtractor
//       mu'   = mu + (diff >>> TEDA_ALPHA)    // EMA mean update   (weight 1/2^ALPHA)
//       sq    = diff * diff                   // THE one multiplier: (x - mu)^2
//       V'    = V  + ((sq - V) >>> TEDA_ALPHA)// EMA variance update
//       bound = m^2 * V                       // m=3 => 9*V = (V<<3)+V  (shift+add!)
//       anomaly_ch = (sq > bound)             // comparator; PRE-update mu,V are used
//   Cost per channel: 1 multiplier (diff^2) + a few adders + fixed shifts (free
//   wiring) + 1 comparator + the mu/V registers + a warm-up counter.  This is the
//   drawable-as-a-real-circuit datapath (feedback state + multiplier + comparator)
//   for the Phase-8G schematic - unlike a bare comparator threshold.
//   Backed by the TEDA-FPGA streaming-anomaly paper (138 ns, 7.2 MSPS, <7% LUTs).
//
// KEY GUARDS:
//   - WARM-UP: the mean/variance are not trustworthy until each channel has seen a
//     few samples, so flags are suppressed until warm_cnt >= TEDA_WARMUP.  (The very
//     first valid sample also PRIMES mu = x, V = 0, so the baseline starts at the
//     real signal instead of ramping up from 0 and inflating V for a long time.)
//   - RAIL FAST-PATH: the old fixed rail-stuck test (x==0 || x==4095) is OR'd in and
//     is ALWAYS active (even during warm-up), so a truly dead sensor still trips
//     instantly without waiting for the statistics to warm up.
//
// TIMING:
//   All outputs are REGISTERED (1-cycle latency), matching the rest of the pipeline.
//   A sample presented with in_valid=1 on cycle T sets anomaly / anom_ch on T+1.
//
// NOTE: standalone module for now (verified in isolation like Phase 8A).  Wiring its
//   anomaly output into analytics_engine (replacing the fixed rail check) is a LATER
//   integration step - this file does NOT touch any existing .v module.
// -----------------------------------------------------------------------------

module adaptive_anomaly #(
    parameter DATA_WIDTH   = 12,   // bits per sensor sample (0-4095)
    parameter NUM_CH       = 3,    // channels: 0=moisture, 1=nutrient, 2=temp
    parameter TEDA_SIGMA_M = 3,    // Chebyshev sigma multiplier m (bound = m^2 * V)
    parameter TEDA_ALPHA   = 3,    // EMA shift: weight 1/2^ALPHA per update (=1/8)
    parameter TEDA_WARMUP  = 8     // suppress flags until this many samples seen
)(
    input  wire                  clk,          // system clock
    input  wire                  rst,          // synchronous, active-high reset

    input  wire                  in_valid,     // 1 = a fresh smoothed sample set
    input  wire [DATA_WIDTH-1:0] avg_moisture, // channel 0 (smoothed)
    input  wire [DATA_WIDTH-1:0] avg_nutrient, // channel 1 (smoothed)
    input  wire [DATA_WIDTH-1:0] avg_temp,     // channel 2 (smoothed)

    output reg                   anomaly,      // 1 = ANY channel flagged this cycle
    output reg  [NUM_CH-1:0]     anom_ch       // per-channel flags (bit c = channel c)
);

    // ---- Internal fixed-point widths (wide enough that (x-mu)^2 and m^2*V never
    //      overflow: max diff^2 = 4095^2 ~= 2^24, max 9*V ~= 2^27 << 2^31) ---------
    localparam DIFF_WIDTH = DATA_WIDTH + 1;   // 13-bit SIGNED difference (x - mu)
    localparam ACC_WIDTH  = 32;               // SIGNED accumulator for sq / V / bound

    localparam [DATA_WIDTH-1:0] RAIL_LO = {DATA_WIDTH{1'b0}};   // 0
    localparam [DATA_WIDTH-1:0] RAIL_HI = {DATA_WIDTH{1'b1}};   // 4095

    // ---- Per-channel STATE registers ---------------------------------------------
    reg signed [DIFF_WIDTH-1:0] mu       [0:NUM_CH-1]; // running mean  (0..4095 range)
    reg signed [ACC_WIDTH-1:0]  var_reg  [0:NUM_CH-1]; // running variance V (>= 0)
    reg        [7:0]            warm_cnt [0:NUM_CH-1];  // samples seen (saturates)

    // ---- Combinational per-channel datapath (re-evaluates every cycle) ------------
    reg [DATA_WIDTH-1:0]  xin      [0:NUM_CH-1]; // the 3 inputs packed for looping
    reg signed [DIFF_WIDTH-1:0] diff  [0:NUM_CH-1]; // x - mu (signed)
    reg signed [ACC_WIDTH-1:0]  sq    [0:NUM_CH-1]; // (x - mu)^2  (the multiplier)
    reg signed [ACC_WIDTH-1:0]  bound [0:NUM_CH-1]; // m^2 * V = 9*V  (shift + add)
    reg                   warm_done [0:NUM_CH-1];    // 1 = past warm-up for this ch
    reg                   rail_flag [0:NUM_CH-1];    // fixed rail-stuck fast path
    reg                   teda_flag [0:NUM_CH-1];    // learned statistical outlier
    reg [NUM_CH-1:0]      ch_flag;                   // combined per-channel anomaly

    integer c;

    always @(*) begin
        // Pack the three named inputs into an array so the per-channel math is one loop.
        xin[0] = avg_moisture;
        xin[1] = avg_nutrient;
        xin[2] = avg_temp;

        for (c = 0; c < NUM_CH; c = c + 1) begin
            // diff = x - mu.  Zero-extend x to a positive signed value before the
            // subtract so signed arithmetic is used (mixing signed/unsigned would
            // silently make the whole expression unsigned).
            diff[c]  = $signed({1'b0, xin[c]}) - mu[c];

            // sq = (x - mu)^2 : this is the ONE multiplier per channel.
            sq[c]    = diff[c] * diff[c];

            // bound = m^2 * V.  For m = TEDA_SIGMA_M = 3 this is 9*V, built from a
            // shift and an add (V<<3)+V - NO extra multiplier.
            bound[c] = (var_reg[c] <<< 3) + var_reg[c];

            warm_done[c] = (warm_cnt[c] >= TEDA_WARMUP);

            // Fixed rail-stuck check - a dead sensor railed at 0 or 4095.  Always on
            // (even during warm-up) so a dead sensor trips instantly.
            rail_flag[c] = (xin[c] == RAIL_LO) || (xin[c] == RAIL_HI);

            // Learned TEDA outlier test - only trusted AFTER warm-up.  Uses the
            // PRE-update mu, V (the values currently in the state registers).
            teda_flag[c] = warm_done[c] && (sq[c] > bound[c]);

            // Combined per-channel anomaly: statistics OR the rail fast-path.
            ch_flag[c] = teda_flag[c] || rail_flag[c];
        end
    end

    // ---- Sequential: register outputs + EMA-update the mu/V state -----------------
    always @(posedge clk) begin
        if (rst) begin
            anomaly <= 1'b0;
            anom_ch <= {NUM_CH{1'b0}};
            for (c = 0; c < NUM_CH; c = c + 1) begin
                mu[c]       <= {DIFF_WIDTH{1'b0}};
                var_reg[c]  <= {ACC_WIDTH{1'b0}};
                warm_cnt[c] <= 8'd0;
            end
        end else begin
            // Default: no valid sample this cycle => no flag.
            anomaly <= 1'b0;
            anom_ch <= {NUM_CH{1'b0}};

            if (in_valid) begin
                // Register the anomaly outputs (1-cycle latency, like the pipeline).
                anom_ch <= ch_flag;
                anomaly <= |ch_flag;

                for (c = 0; c < NUM_CH; c = c + 1) begin
                    if (warm_cnt[c] == 8'd0) begin
                        // FIRST valid sample: prime the baseline at the real signal
                        // (mu = x, V = 0) instead of ramping up from 0.
                        mu[c]      <= $signed({1'b0, xin[c]});
                        var_reg[c] <= {ACC_WIDTH{1'b0}};
                    end else begin
                        // EMA updates (shift, not divide).  These run on EVERY valid
                        // sample; the flag above used the PRE-update mu, V.
                        mu[c]      <= mu[c] + (diff[c] >>> TEDA_ALPHA);
                        var_reg[c] <= var_reg[c] + ((sq[c] - var_reg[c]) >>> TEDA_ALPHA);
                    end

                    // Count samples seen, saturating at TEDA_WARMUP (that is all the
                    // warm-up test needs).
                    if (warm_cnt[c] < TEDA_WARMUP)
                        warm_cnt[c] <= warm_cnt[c] + 8'd1;
                end
            end
            // in_valid low: hold all state; outputs already forced to 0 above.
        end
    end

endmodule
