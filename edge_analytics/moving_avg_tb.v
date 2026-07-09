// moving_avg_tb.v
// -----------------------------------------------------------------------------
// Testbench for moving_avg.v
//
// WHAT IT DOES:
//   Acts as a fake sensor. It streams a series of readings into the filter:
//     - a steady baseline around 100 with realistic jitter,
//     - one sharp SPIKE to 900 (an "anomaly"),
//     - then back to baseline.
//   Watch avg_out in gtkwave: it should stay smooth near 100 and only bump
//   gently when the spike passes through the window -- proving the filter works.
//
// This is pure SOFTWARE simulation: no real sensor, no hardware. The testbench
// supplies the numbers; iverilog runs it as a program on your Mac.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module moving_avg_tb;

    // Match these to the module's parameters.
    localparam DATA_WIDTH = 12;
    localparam LOG2_N     = 3;    // window of 8 samples

    // ---- Signals driving / observing the Device Under Test (DUT) -------------
    reg                    clk = 0;
    reg                    rst;
    reg                    sample_valid;
    reg  [DATA_WIDTH-1:0]  sample_in;
    wire [DATA_WIDTH-1:0]  avg_out;
    wire                   avg_valid;

    // ---- Instantiate the filter ---------------------------------------------
    moving_avg #(
        .DATA_WIDTH(DATA_WIDTH),
        .LOG2_N(LOG2_N)
    ) dut (
        .clk(clk),
        .rst(rst),
        .sample_valid(sample_valid),
        .sample_in(sample_in),
        .avg_out(avg_out),
        .avg_valid(avg_valid)
    );

    // ---- Clock: 100 MHz -> toggle every 5 ns --------------------------------
    always #5 clk = ~clk;

    // ---- Stimulus: 20 fake sensor readings ----------------------------------
    reg [DATA_WIDTH-1:0] stim [0:19];
    integer k;

    initial begin
        // Tell the simulator to record every signal into dump.vcd for gtkwave.
        $dumpfile("dump.vcd");
        $dumpvars(0, moving_avg_tb);

        // Baseline ~100 with jitter...
        stim[0]=100; stim[1]=102; stim[2]=98;  stim[3]=101;
        stim[4]=99;  stim[5]=100; stim[6]=103; stim[7]=97;
        // ...one big spike (the anomaly)...
        stim[8]=900;
        // ...then back to baseline.
        stim[9]=101;  stim[10]=99;  stim[11]=100; stim[12]=102;
        stim[13]=98;  stim[14]=101; stim[15]=100; stim[16]=99;
        stim[17]=100; stim[18]=101; stim[19]=100;

        // Hold reset for two clocks so the window starts clean.
        rst = 1; sample_valid = 0; sample_in = 0;
        @(posedge clk); @(posedge clk);
        rst = 0;

        // Feed one sample per clock.
        for (k = 0; k < 20; k = k + 1) begin
            @(posedge clk);
            sample_in    <= stim[k];
            sample_valid <= 1;
        end

        // Stop feeding, let the last result settle.
        @(posedge clk);
        sample_valid <= 0;
        @(posedge clk); @(posedge clk);

        $display("-------------------------------------------------");
        $display("Simulation complete. Open the waveform with:");
        $display("    gtkwave dump.vcd");
        $finish;
    end

    // ---- Print each averaged result as it appears ---------------------------
    always @(posedge clk) begin
        if (avg_valid)
            $display("t=%4t ns | sample_in=%3d | avg_out=%3d", $time, sample_in, avg_out);
    end

endmodule
