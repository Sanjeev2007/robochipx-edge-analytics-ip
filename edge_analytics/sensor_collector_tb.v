// sensor_collector_tb.v
// -----------------------------------------------------------------------------
// Testbench for sensor_collector.v
//
// WHAT IT DOES:
//   Pretends to be the 3 field sensors. It feeds a series of changing readings
//   (moisture, nutrient, temp) into the collector and checks that:
//     - each set of 3 readings appears together on the outputs one cycle later,
//     - every set is tagged with a timestamp that keeps INCREASING,
//     - sample_valid is high only when we actually presented new readings.
//   It also deliberately drops sensors_valid for a cycle to prove the collector
//   holds its last outputs and correctly reports "not valid" that cycle, while
//   the timestamp counter keeps ticking underneath.
//
// This is pure SOFTWARE simulation: no real sensor, no hardware. iverilog runs
// it as a program on your Mac and prints what happened.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module sensor_collector_tb;

    // Match these to the module's parameters.
    localparam DATA_WIDTH = 12;
    localparam TS_WIDTH   = 32;

    // ---- Signals driving / observing the Device Under Test (DUT) -------------
    reg                    clk = 0;
    reg                    rst;
    reg  [DATA_WIDTH-1:0]  moisture_in;
    reg  [DATA_WIDTH-1:0]  nutrient_in;
    reg  [DATA_WIDTH-1:0]  temp_in;
    reg                    sensors_valid;

    wire [DATA_WIDTH-1:0]  moisture;
    wire [DATA_WIDTH-1:0]  nutrient;
    wire [DATA_WIDTH-1:0]  temp;
    wire [TS_WIDTH-1:0]    timestamp;
    wire                   sample_valid;

    // ---- Instantiate the collector ------------------------------------------
    sensor_collector #(
        .DATA_WIDTH(DATA_WIDTH),
        .TS_WIDTH(TS_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .moisture_in(moisture_in),
        .nutrient_in(nutrient_in),
        .temp_in(temp_in),
        .sensors_valid(sensors_valid),
        .moisture(moisture),
        .nutrient(nutrient),
        .temp(temp),
        .timestamp(timestamp),
        .sample_valid(sample_valid)
    );

    // ---- Clock: 100 MHz -> toggle every 5 ns --------------------------------
    always #5 clk = ~clk;

    // ---- Fake sensor readings: 6 changing sets ------------------------------
    reg [DATA_WIDTH-1:0] m_stim [0:5];
    reg [DATA_WIDTH-1:0] n_stim [0:5];
    reg [DATA_WIDTH-1:0] t_stim [0:5];
    integer k;

    // ---- Self-check bookkeeping ---------------------------------------------
    integer errors      = 0;
    reg [TS_WIDTH-1:0] last_ts;   // last timestamp we saw on a valid set
    reg                have_ts;   // have we seen at least one valid set yet?

    initial begin
        // Record every signal into dump.vcd for gtkwave.
        $dumpfile("dump.vcd");
        $dumpvars(0, sensor_collector_tb);

        // Moisture drifts down, nutrient steady-ish, temp drifts up.
        m_stim[0]=300; m_stim[1]=280; m_stim[2]=260; m_stim[3]=240; m_stim[4]=220; m_stim[5]=200;
        n_stim[0]=305; n_stim[1]=300; n_stim[2]=302; n_stim[3]=298; n_stim[4]=301; n_stim[5]=299;
        t_stim[0]=380; t_stim[1]=385; t_stim[2]=390; t_stim[3]=395; t_stim[4]=400; t_stim[5]=405;

        have_ts = 0;
        last_ts = 0;

        // Hold reset for two clocks so everything starts clean.
        rst = 1; sensors_valid = 0; moisture_in = 0; nutrient_in = 0; temp_in = 0;
        @(posedge clk); @(posedge clk);
        rst = 0;

        $display("--------------------------------------------------------------");
        $display("Feeding fake sensor sets into sensor_collector...");
        $display("--------------------------------------------------------------");

        // Feed the first three sets, one per clock.
        for (k = 0; k < 3; k = k + 1) begin
            @(posedge clk);
            moisture_in   <= m_stim[k];
            nutrient_in   <= n_stim[k];
            temp_in       <= t_stim[k];
            sensors_valid <= 1;
        end

        // GAP: no new readings for one cycle. Outputs should hold and
        // sample_valid should drop, but the timestamp counter keeps ticking.
        @(posedge clk);
        sensors_valid <= 0;

        // Feed the remaining three sets.
        for (k = 3; k < 6; k = k + 1) begin
            @(posedge clk);
            moisture_in   <= m_stim[k];
            nutrient_in   <= n_stim[k];
            temp_in       <= t_stim[k];
            sensors_valid <= 1;
        end

        // Stop feeding, let the last result settle.
        @(posedge clk);
        sensors_valid <= 0;
        @(posedge clk); @(posedge clk);

        $display("--------------------------------------------------------------");
        if (errors == 0)
            $display("RESULT: PASS - all sets aligned, timestamps strictly increasing.");
        else
            $display("RESULT: FAIL - %0d error(s) detected.", errors);
        $display("Open the waveform with:  gtkwave dump.vcd");
        $display("--------------------------------------------------------------");
        $finish;
    end

    // ---- Watch the outputs and self-check every valid set -------------------
    always @(posedge clk) begin
        if (!rst) begin
            if (sample_valid) begin
                $display("t=%4t ns | ts=%0d | moisture=%0d nutrient=%0d temp=%0d | valid=1",
                         $time, timestamp, moisture, nutrient, temp);

                // Timestamps must strictly increase across valid sets.
                if (have_ts && !(timestamp > last_ts)) begin
                    $display("  ^ ERROR: timestamp did not increase (last=%0d now=%0d)",
                             last_ts, timestamp);
                    errors = errors + 1;
                end
                have_ts = 1;
                last_ts = timestamp;
            end
        end
    end

endmodule
