// edge_analytics_tb.v
// -----------------------------------------------------------------------------
// Top-level testbench for edge_analytics_top (Phase 5: integration + egress).
//
// WHAT IT DOES:
//   1) Plays the field-sensor STORY TRACE into the chip, one aligned sample set
//      per clock: healthy -> gentle dry-spell (pump ON) -> irrigation recovery
//      (pump OFF) -> nutrient low -> heat stress.
//   2) On EVERY valid output cycle it prints ONE 17-field CSV row in the
//      dashboard's contract format (Phase 5.5, docs/INTERFACES.md 3):
//         timestamp,moisture_raw,nutrient_raw,temp_raw,moisture_avg,nutrient_avg,
//         temp_avg,pump_on,dose_nutrient,alert_nutrient,alert_weed,alert_heat,
//         alert_frost,alert_anomaly,status,crop_health,relocate_recommend
//      The header line is printed ONCE at the top.  Raw sensor COUNTS (0-4095)
//      are SCALED to display units here in the testbench (moisture/nutrient
//      count/5 clamped 0-100, temp count/10, crop_health health*100/255); the
//      RTL modules are untouched.  The stream pipes straight into the dashboard:
//         vvp simulation.vvp | python3 edge_agri_dashboard.py
//   3) PROVES LATENCY ALIGNMENT.  A tiny reference model recomputes, for each
//      timestamp, the raw value we fed and the 8-sample moving average that
//      SHOULD result.  On every D line it self-checks that the printed
//      raw (delayed +3), avg (delayed +2) and the decision (+0) all belong to
//      the SAME original sample.  A highlighted banner does the same for the
//      exact sample on which the pump turns ON (raw + avg + decision, one line).
//
// WHY ts == feed index:
//   Reset is released so the FIRST valid sample is captured while the
//   free-running counter is 0.  We then feed exactly one sample per cycle, so
//   sample #k carries timestamp k.  That lets the reference arrays be indexed
//   directly by the timestamp printed on each D line.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module edge_analytics_tb;

    // ---- Parameters (mirror the frozen contract, docs/INTERFACES.md 1) -------
    localparam DATA_WIDTH = 12;
    localparam TS_WIDTH   = 32;
    localparam NS         = 56;   // number of samples in the story trace

    // ---- DUT connections -----------------------------------------------------
    reg                    clk;
    reg                    rst;
    reg  [DATA_WIDTH-1:0]  moisture_in, nutrient_in, temp_in;
    reg                    sensors_valid;

    wire [TS_WIDTH-1:0]    out_timestamp;
    wire [DATA_WIDTH-1:0]  out_moisture, out_nutrient, out_temp;
    wire [DATA_WIDTH-1:0]  out_avg_moisture, out_avg_nutrient, out_avg_temp;
    wire                   out_pump_on, out_dose_nutrient;
    wire                   out_alert_weed, out_alert_heat, out_alert_frost;
    wire                   out_alert_nutrient, out_alert_anomaly;
    wire [1:0]             out_status;
    wire [7:0]             out_crop_health;
    wire [3:0]             out_event_id;
    wire [TS_WIDTH-1:0]    out_event_timestamp;
    wire                   out_valid;

    // ---- Device Under Test ---------------------------------------------------
    edge_analytics_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .TS_WIDTH  (TS_WIDTH)
    ) dut (
        .clk(clk), .rst(rst),
        .moisture_in(moisture_in), .nutrient_in(nutrient_in), .temp_in(temp_in),
        .sensors_valid(sensors_valid),
        .out_timestamp(out_timestamp),
        .out_moisture(out_moisture), .out_nutrient(out_nutrient), .out_temp(out_temp),
        .out_avg_moisture(out_avg_moisture), .out_avg_nutrient(out_avg_nutrient),
        .out_avg_temp(out_avg_temp),
        .out_pump_on(out_pump_on), .out_dose_nutrient(out_dose_nutrient),
        .out_alert_weed(out_alert_weed), .out_alert_heat(out_alert_heat),
        .out_alert_frost(out_alert_frost), .out_alert_nutrient(out_alert_nutrient),
        .out_alert_anomaly(out_alert_anomaly),
        .out_status(out_status), .out_crop_health(out_crop_health),
        .out_event_id(out_event_id), .out_event_timestamp(out_event_timestamp),
        .out_valid(out_valid)
    );

    // ---- Clock: 10 ns period -------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- The story-trace sample arrays (indexed by timestamp) ---------------
    reg [DATA_WIDTH-1:0] rm [0:NS-1];   // raw moisture we feed
    reg [DATA_WIDTH-1:0] rn [0:NS-1];   // raw nutrient we feed
    reg [DATA_WIDTH-1:0] rt [0:NS-1];   // raw temperature we feed

    integer k;
    integer errors;

    // ---- Reference moving-average model (matches moving_avg exactly) ---------
    // moving_avg's buffer is zero-initialised, so at sample ts the average is the
    // sum of the last 8 fed values (padded with zeros before ts=0) >> 3.  These
    // three tiny functions recompute that expected average for the checker.
    function [DATA_WIDTH-1:0] avg8_m;
        input integer ts; integer j; integer idx; integer sum;
        begin
            sum = 0;
            for (j = 0; j < 8; j = j + 1) begin
                idx = ts - j;
                if (idx >= 0) sum = sum + rm[idx];
            end
            avg8_m = sum >> 3;
        end
    endfunction
    function [DATA_WIDTH-1:0] avg8_n;
        input integer ts; integer j; integer idx; integer sum;
        begin
            sum = 0;
            for (j = 0; j < 8; j = j + 1) begin
                idx = ts - j;
                if (idx >= 0) sum = sum + rn[idx];
            end
            avg8_n = sum >> 3;
        end
    endfunction
    function [DATA_WIDTH-1:0] avg8_t;
        input integer ts; integer j; integer idx; integer sum;
        begin
            sum = 0;
            for (j = 0; j < 8; j = j + 1) begin
                idx = ts - j;
                if (idx >= 0) sum = sum + rt[idx];
            end
            avg8_t = sum >> 3;
        end
    endfunction

    // ---- event_id -> name (docs/INTERFACES.md 4) ----------------------------
    function [95:0] ev_name;    // up to 12 chars packed as a string
        input [3:0] id;
        begin
            case (id)
                4'd1: ev_name = "PUMP_ON";
                4'd2: ev_name = "PUMP_OFF";
                4'd3: ev_name = "WEED_DETECTED";
                4'd4: ev_name = "NUTRIENT_LOW";
                4'd5: ev_name = "HEAT_STRESS";
                4'd6: ev_name = "FROST_RISK";
                4'd7: ev_name = "SENSOR_ANOMALY";
                4'd8: ev_name = "STATUS_CRITICAL";
                default: ev_name = "NONE";
            endcase
        end
    endfunction

    // =========================================================================
    // LIVE STREAM + SELF-CHECK  (runs at negedge so all posedge updates settled)
    // =========================================================================
    integer ts_i;
    reg [DATA_WIDTH-1:0] exp_m, exp_am;

    // ---- Scaling scratch (raw sensor COUNTS -> dashboard display units) ------
    // `integer` (32-bit) so the *100 multiply for crop_health can't truncate.
    integer sc_m_raw, sc_n_raw, sc_t_raw;   // scaled raw moisture/nutrient/temp
    integer sc_m_avg, sc_n_avg, sc_t_avg;   // scaled smoothed moisture/nutrient/temp
    integer sc_health;                      // crop_health 0-255 -> 0-100
    integer relocate;                       // relocate_recommend flag

    always @(negedge clk) begin
        if (!rst && out_valid) begin
            ts_i = out_timestamp;

            // ---- Scale raw counts (0-4095) into dashboard display units ------
            // moisture/nutrient: count/5 clamped 0-100 (dry@200->40, off@350->70)
            // temperature:       count/10            (hot@400->40C, cold@100->10C)
            sc_m_raw = out_moisture     / 5;  if (sc_m_raw > 100) sc_m_raw = 100;
            sc_n_raw = out_nutrient     / 5;  if (sc_n_raw > 100) sc_n_raw = 100;
            sc_t_raw = out_temp         / 10;
            sc_m_avg = out_avg_moisture / 5;  if (sc_m_avg > 100) sc_m_avg = 100;
            sc_n_avg = out_avg_nutrient / 5;  if (sc_n_avg > 100) sc_n_avg = 100;
            sc_t_avg = out_avg_temp     / 10;
            // crop_health 0-255 -> 0-100 (wide multiply first, then divide)
            sc_health = (out_crop_health * 100) / 255;
            // relocate: still CRITICAL with a poor scaled-health score despite action
            relocate  = (out_status == 2'd2 && sc_health < 35) ? 1 : 0;

            // ---- 17-field dashboard CSV row (docs/INTERFACES.md 3) -----------
            // Field order EXACTLY matches the printed header (see initial block).
            $display("%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                     out_timestamp,
                     sc_m_raw, sc_n_raw, sc_t_raw,
                     sc_m_avg, sc_n_avg, sc_t_avg,
                     out_pump_on, out_dose_nutrient,
                     out_alert_nutrient, out_alert_weed, out_alert_heat,
                     out_alert_frost, out_alert_anomaly,
                     out_status, sc_health, relocate);
            $fflush;

            // ---- ALIGNMENT SELF-CHECK: every field on this D line is from ts_i
            // Raw is delayed +3, avg +2, decision +0; if the delay lines are
            // right, all three still describe the SAME original sample ts_i.
            if (out_moisture !== rm[ts_i]) begin
                errors = errors + 1;
                $display("  ** FAIL raw moisture @ts=%0d: got %0d expected %0d",
                         ts_i, out_moisture, rm[ts_i]);
            end
            if (out_nutrient !== rn[ts_i]) begin
                errors = errors + 1;
                $display("  ** FAIL raw nutrient @ts=%0d: got %0d expected %0d",
                         ts_i, out_nutrient, rn[ts_i]);
            end
            if (out_temp !== rt[ts_i]) begin
                errors = errors + 1;
                $display("  ** FAIL raw temp @ts=%0d: got %0d expected %0d",
                         ts_i, out_temp, rt[ts_i]);
            end
            if (out_avg_moisture !== avg8_m(ts_i)) begin
                errors = errors + 1;
                $display("  ** FAIL avg moisture @ts=%0d: got %0d expected %0d",
                         ts_i, out_avg_moisture, avg8_m(ts_i));
            end
            if (out_avg_nutrient !== avg8_n(ts_i)) begin
                errors = errors + 1;
                $display("  ** FAIL avg nutrient @ts=%0d: got %0d expected %0d",
                         ts_i, out_avg_nutrient, avg8_n(ts_i));
            end
            if (out_avg_temp !== avg8_t(ts_i)) begin
                errors = errors + 1;
                $display("  ** FAIL avg temp @ts=%0d: got %0d expected %0d",
                         ts_i, out_avg_temp, avg8_t(ts_i));
            end

            // ---- Single-sample alignment proof (pump-ON sample), SILENT ------
            // On the PUMP_ON sample the raw moisture, its 8-sample average and
            // the pump decision it triggered must all belong to ts_i.  Kept as a
            // silent self-check (prints ONLY on mismatch) so the CSV stream that
            // pipes to the dashboard stays clean.
            if (out_event_id == 4'd1) begin // PUMP_ON
                exp_m  = rm[ts_i];
                exp_am = avg8_m(ts_i);
                if (out_moisture !== exp_m || out_avg_moisture !== exp_am || out_pump_on !== 1'b1) begin
                    errors = errors + 1;
                    $display("  ** FAIL alignment proof mismatch @ts=%0d", ts_i);
                end
            end
        end
    end

    // =========================================================================
    // STIMULUS
    // =========================================================================
    integer s;
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, edge_analytics_tb);

        errors = 0;

        // ---- Print the 17-field dashboard CSV header ONCE ----------------
        // Field order here is the single source of truth; the per-cycle row in
        // the negedge block prints these same fields in this exact order.
        $display("timestamp,moisture_raw,nutrient_raw,temp_raw,moisture_avg,nutrient_avg,temp_avg,pump_on,dose_nutrient,alert_nutrient,alert_weed,alert_heat,alert_frost,alert_anomaly,status,crop_health,relocate_recommend");
        $fflush;

        // ---- Build the story trace (index = timestamp) -------------------
        // NOTE ON WARM-UP: the 8-sample moving_avg buffer starts at 0, so during
        // the first ~8 samples every average RAMPS UP from 0 (a filter-fill
        // artifact, inherent to moving_avg - not a wiring issue).  We keep the
        // healthy baseline WET (400 -> avg settles 400, above the 350 pump-off
        // point) so that once the window is full the pump sits cleanly OFF, and
        // the FIRST genuine PUMP_ON happens in the dry-spell below.
        //
        // Phase A - healthy & wet (fill the window; pump settles OFF)
        for (k = 0; k <= 9;  k = k + 1) begin rm[k]=400; rn[k]=300; rt[k]=250; end
        // Phase B - gentle dry-spell (~18/sample: gentle enough NOT to look like
        //           a weed, but long enough that avg crosses 200 -> dry -> PUMP_ON)
        rm[10]=385; rm[11]=367; rm[12]=349; rm[13]=331; rm[14]=313; rm[15]=295;
        rm[16]=277; rm[17]=259; rm[18]=241; rm[19]=223; rm[20]=205; rm[21]=187;
        rm[22]=169; rm[23]=151; rm[24]=133; rm[25]=115;
        for (k = 10; k <= 25; k = k + 1) begin rn[k]=300; rt[k]=250; end
        // Phase C - irrigation works: moisture jumps back, avg passes 350 -> PUMP_OFF
        for (k = 26; k <= 33; k = k + 1) begin rm[k]=900; rn[k]=300; rt[k]=250; end
        // Phase D - nutrient runs low (avg_nutrient < 250 -> NUTRIENT_LOW + dose)
        for (k = 34; k <= 43; k = k + 1) begin rm[k]=900; rn[k]=200; rt[k]=250; end
        // Phase E - heat stress (avg_temp climbs past 400 -> HEAT_STRESS)
        for (k = 44; k <= 55; k = k + 1) begin rm[k]=900; rn[k]=300; rt[k]=450; end

        // ---- Reset, then stream the trace one sample per cycle -----------
        rst = 1; sensors_valid = 0;
        moisture_in = 0; nutrient_in = 0; temp_in = 0;
        @(negedge clk);
        @(negedge clk);
        rst = 0;   // released; the next posedge captures sample 0 with ts=0

        for (s = 0; s < NS; s = s + 1) begin
            moisture_in   = rm[s];
            nutrient_in   = rn[s];
            temp_in       = rt[s];
            sensors_valid = 1;
            @(negedge clk);
        end

        // Stop feeding and let the pipeline drain (raw+3 latency, plus margin).
        sensors_valid = 0;
        moisture_in = 0; nutrient_in = 0; temp_in = 0;
        repeat (8) @(negedge clk);

        // ---- Verdict -----------------------------------------------------
        $display("----------------------------------------------------------");
        if (errors == 0)
            $display("RESULT: PASS - all D-line fields aligned to their sample (0 errors).");
        else
            $display("RESULT: FAIL - %0d alignment error(s).", errors);
        $display("----------------------------------------------------------");
        $finish;
    end

endmodule
