// sensor_collector.v
// -----------------------------------------------------------------------------
// Sensor Collector - the FRONT-END of the Edge Analytics IP (mandatory #1).
//
// PURPOSE:
//   This is the very first block in the chip. It sits between the raw field
//   sensors and the rest of the pipeline. Its two jobs are simple:
//     1) Keep a running clock, so every reading can be stamped with a "when".
//     2) Snapshot the 3 sensor channels together (moisture, nutrient, temp)
//        so they stay aligned as one set travelling down the pipeline.
//
// WHY "PARALLEL" (all 3 channels together)?
//   We emit moisture, nutrient and temperature side-by-side every valid cycle
//   (see docs/INTERFACES.md 2). Keeping them aligned means the smoothing,
//   analytics and the "D" dashboard line can all handle one tidy sample set at
//   a time - no re-ordering, no channel mux to get out of sync.
//
// THE TIMESTAMP:
//   A free-running 32-bit counter ticks up by 1 every clock (it resets to 0).
//   That count is our notion of time ("cycle 65000"). When a new sample set is
//   captured we latch the current count alongside the readings, so downstream
//   blocks know exactly WHEN each reading was taken. This timestamp is the
//   thread that later lets analytics say "weed detected at cycle 120000".
// -----------------------------------------------------------------------------

module sensor_collector #(
    parameter DATA_WIDTH = 12,   // bits per sensor sample (0-4095)
    parameter TS_WIDTH   = 32    // width of the free-running timestamp counter
)(
    input  wire                   clk,           // system clock
    input  wire                   rst,           // synchronous, active-high reset

    // ---- Raw sensor inputs (from the field) --------------------------------
    input  wire [DATA_WIDTH-1:0]  moisture_in,   // ch0: soil moisture (noisy)
    input  wire [DATA_WIDTH-1:0]  nutrient_in,   // ch1: nutrient / NPK (noisy)
    input  wire [DATA_WIDTH-1:0]  temp_in,       // ch2: temperature (noisy)
    input  wire                   sensors_valid, // 1 = new readings present this cycle

    // ---- Registered, aligned outputs (to the pipeline) ---------------------
    output reg  [DATA_WIDTH-1:0]  moisture,      // ch0 held for this sample set
    output reg  [DATA_WIDTH-1:0]  nutrient,      // ch1 held for this sample set
    output reg  [DATA_WIDTH-1:0]  temp,          // ch2 held for this sample set
    output reg  [TS_WIDTH-1:0]    timestamp,     // cycle count when this set was captured
    output reg                    sample_valid   // 1 = outputs valid this cycle
);

    // ---- Internal state ------------------------------------------------------
    // The free-running clock-cycle counter. It ALWAYS advances (except on reset),
    // whether or not a sample arrives, so it is a true measure of elapsed time.
    reg [TS_WIDTH-1:0] cycle_count;

    always @(posedge clk) begin
        if (rst) begin
            // On reset: time restarts at 0 and no valid sample is presented.
            cycle_count  <= 0;
            moisture     <= 0;
            nutrient     <= 0;
            temp         <= 0;
            timestamp    <= 0;
            sample_valid <= 0;
        end else begin
            // 1) Advance the clock every cycle - this is our timestamp source.
            cycle_count <= cycle_count + 1'b1;

            // 2) When fresh readings arrive, latch all 3 channels together and
            //    tag them with the CURRENT time, then flag the set as valid.
            if (sensors_valid) begin
                moisture     <= moisture_in;
                nutrient     <= nutrient_in;
                temp         <= temp_in;
                timestamp    <= cycle_count;   // "when" these readings were taken
                sample_valid <= 1'b1;
            end else begin
                // No new readings this cycle -> outputs are not fresh.
                sample_valid <= 0;
            end
        end
    end

endmodule
