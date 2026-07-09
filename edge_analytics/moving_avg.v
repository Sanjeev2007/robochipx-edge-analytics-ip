// moving_avg.v
// -----------------------------------------------------------------------------
// Moving Average Filter (sliding window) - the CORE of the Edge Analytics IP.
//
// PURPOSE:
//   Smooths a stream of noisy sensor readings by averaging the last N samples.
//   Raw sensors jitter (e.g. 100, 102, 98, 101...) even when nothing changes;
//   averaging throws away that flicker and reveals the true signal (~100).
//
// EFFICIENCY TRICK (why this is "hardware-friendly"):
//   Instead of re-adding all N samples every clock, we keep a running total and
//   update it in ONE step:   acc = acc + newest_sample - oldest_sample.
//   Dividing by N is just a right-shift, because N is a power of two (N = 2^LOG2_N).
//   No multiplier, no divider needed -> tiny, fast, low-power.
// -----------------------------------------------------------------------------

module moving_avg #(
    parameter DATA_WIDTH = 12,   // bit-width of each sensor sample
    parameter LOG2_N     = 3     // window size = 2^LOG2_N  (3 => 8 samples)
)(
    input  wire                   clk,          // system clock
    input  wire                   rst,          // synchronous, active-high reset
    input  wire                   sample_valid, // 1 = a new sample is present this cycle
    input  wire [DATA_WIDTH-1:0]  sample_in,    // incoming raw sensor reading
    output reg  [DATA_WIDTH-1:0]  avg_out,      // smoothed (averaged) result
    output reg                    avg_valid     // 1 = avg_out holds a fresh result
);

    // ---- Local constants derived from the parameters -------------------------
    localparam N         = (1 << LOG2_N);          // number of samples in the window
    localparam ACC_WIDTH = DATA_WIDTH + LOG2_N;    // extra bits so the sum can't overflow

    // ---- Internal state ------------------------------------------------------
    // Shift-register buffer holding the last N samples.
    //   buffer[0]   = newest sample
    //   buffer[N-1] = oldest sample (the one about to leave the window)
    reg [DATA_WIDTH-1:0] buffer [0:N-1];

    reg [ACC_WIDTH-1:0]  acc;   // running SUM of every sample currently in the buffer

    integer i;                  // loop index (used only to describe the shift)

    always @(posedge clk) begin
        if (rst) begin
            // On reset, empty the window and clear outputs.
            acc       <= 0;
            avg_out   <= 0;
            avg_valid <= 0;
            for (i = 0; i < N; i = i + 1)
                buffer[i] <= 0;
        end else if (sample_valid) begin
            // 1) Update the running sum: add the new sample, subtract the oldest.
            //    (Nonblocking <= reads the OLD acc and OLD buffer[N-1], which is what we want.)
            acc <= acc + sample_in - buffer[N-1];

            // 2) Slide the window: every entry moves up one slot; new sample enters slot 0.
            for (i = N-1; i > 0; i = i - 1)
                buffer[i] <= buffer[i-1];
            buffer[0] <= sample_in;

            // 3) Output the average = sum / N via a cheap right-shift.
            //    We divide the freshly-updated sum (old acc + new - oldest).
            avg_out   <= (acc + sample_in - buffer[N-1]) >> LOG2_N;
            avg_valid <= 1;
        end else begin
            // No new sample this cycle -> no fresh result.
            avg_valid <= 0;
        end
    end

endmodule
