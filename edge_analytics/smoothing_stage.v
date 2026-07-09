// smoothing_stage.v
// -----------------------------------------------------------------------------
// Smoothing Stage - Phase 2 of the Edge Analytics IP (mandatory feature #2).
//
// PURPOSE:
//   Sits right after sensor_collector. Takes the 3 aligned raw channels
//   (moisture, nutrient, temp) and smooths EACH one with its own copy of the
//   already-built moving_avg filter. The result is 3 clean, de-noised channels
//   that the analytics engine can threshold reliably instead of chasing jitter.
//
// HOW IT'S BUILT (reuse, don't reinvent):
//   We simply INSTANTIATE the existing moving_avg.v three times - one per
//   channel - all driven by the same sample_valid. moving_avg is not touched;
//   this file is pure wiring. Each instance keeps its own 8-sample window
//   (LOG2_N=3 => N=8) and its own running accumulator.
//
// ==> THE ALIGNMENT PROBLEM (and the fix) <==
//   moving_avg REGISTERS its output, so a sample presented on cycle T only
//   appears smoothed on cycle T+1 (together with avg_valid going high).
//   The raw timestamp from sensor_collector, however, is valid on cycle T.
//   If we passed it straight through it would be ONE CYCLE AHEAD of the
//   smoothed data - the "when" would no longer match the values.
//   FIX: push the timestamp through a single register (timestamp_dly) so it
//   comes out on cycle T+1, perfectly lined up with avg_moisture/nutrient/temp
//   and avg_valid. All 3 channels share identical timing, so ONE avg_valid
//   represents the whole set.
// -----------------------------------------------------------------------------

module smoothing_stage #(
    parameter DATA_WIDTH = 12,   // bits per sensor sample (0-4095)
    parameter LOG2_N     = 3,    // moving-average window = 2^3 = 8 samples
    parameter TS_WIDTH   = 32    // width of the timestamp travelling with the data
)(
    input  wire                   clk,           // system clock
    input  wire                   rst,           // synchronous, active-high reset

    // ---- Inputs: the aligned raw sample set from sensor_collector ----------
    input  wire [DATA_WIDTH-1:0]  moisture_in,   // ch0 raw moisture
    input  wire [DATA_WIDTH-1:0]  nutrient_in,   // ch1 raw nutrient (NPK)
    input  wire [DATA_WIDTH-1:0]  temp_in,       // ch2 raw temperature
    input  wire [TS_WIDTH-1:0]    timestamp_in,  // "when" this set was captured
    input  wire                   sample_valid,  // 1 = a fresh raw set is present

    // ---- Outputs: the smoothed set, timestamp re-aligned -------------------
    output wire [DATA_WIDTH-1:0]  avg_moisture,  // ch0 smoothed
    output wire [DATA_WIDTH-1:0]  avg_nutrient,  // ch1 smoothed
    output wire [DATA_WIDTH-1:0]  avg_temp,      // ch2 smoothed
    output reg  [TS_WIDTH-1:0]    timestamp_out, // timestamp delayed 1 cycle to align
    output wire                   avg_valid      // 1 = smoothed set valid this cycle
);

    // ---- Per-channel avg_valid strobes --------------------------------------
    // All 3 filters run in lockstep (same clk/rst/sample_valid), so their valid
    // strobes rise on the same cycle. We keep all 3 wires for clarity but expose
    // only the moisture channel's as the representative for the whole set.
    wire avg_valid_m;
    wire avg_valid_n;
    wire avg_valid_t;

    // ---- Channel 0: soil moisture -------------------------------------------
    moving_avg #(
        .DATA_WIDTH(DATA_WIDTH),
        .LOG2_N(LOG2_N)
    ) avg_moisture_inst (
        .clk(clk),
        .rst(rst),
        .sample_valid(sample_valid),
        .sample_in(moisture_in),
        .avg_out(avg_moisture),
        .avg_valid(avg_valid_m)
    );

    // ---- Channel 1: nutrient (NPK) ------------------------------------------
    moving_avg #(
        .DATA_WIDTH(DATA_WIDTH),
        .LOG2_N(LOG2_N)
    ) avg_nutrient_inst (
        .clk(clk),
        .rst(rst),
        .sample_valid(sample_valid),
        .sample_in(nutrient_in),
        .avg_out(avg_nutrient),
        .avg_valid(avg_valid_n)
    );

    // ---- Channel 2: temperature ---------------------------------------------
    moving_avg #(
        .DATA_WIDTH(DATA_WIDTH),
        .LOG2_N(LOG2_N)
    ) avg_temp_inst (
        .clk(clk),
        .rst(rst),
        .sample_valid(sample_valid),
        .sample_in(temp_in),
        .avg_out(avg_temp),
        .avg_valid(avg_valid_t)
    );

    // The 3 channels are identical in timing; one strobe speaks for the set.
    assign avg_valid = avg_valid_m;

    // ---- Timestamp re-alignment ---------------------------------------------
    // Delay the incoming timestamp by exactly one clock so it emerges on the
    // same cycle as the smoothed outputs (which moving_avg registers). This
    // single register is the whole fix for the alignment note in the build plan.
    always @(posedge clk) begin
        if (rst)
            timestamp_out <= 0;
        else
            timestamp_out <= timestamp_in;
    end

endmodule
