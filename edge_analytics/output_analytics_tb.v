// output_analytics_tb.v
// -----------------------------------------------------------------------------
// Testbench for output_analytics (Phase 4).
//
// It drives the analytics_engine DECISIONS directly (no need to chain the whole
// pipeline) through a story that exercises every requirement:
//   1. PUMP HYSTERESIS (the headline): dry -> pump ON; soil recovers INTO the
//      200..350 band -> pump STAYS ON (no chatter); soil crosses 350 -> pump OFF;
//      soil dips below 350 but not dry -> pump STAYS OFF (no re-trigger).
//   2. PUMP_ON / PUMP_OFF events fire with the correct event_timestamp.
//   3. Pump RE-ARMS: a second dry spell turns it back on.
//   4. ALERT MAPPING: weed/hot/cold/low_nutrient/anomaly -> the five alert lines
//      plus dose_nutrient.
//   5. EVENT PRIORITY: when an engine event and a pump toggle land the same cycle,
//      the engine event wins event_id (while the pump still actuates).
//
// TIMING MODEL: output_analytics registers all outputs, so each `step` applies the
// inputs, waits for the latching clock edge, and the outputs then reflect THAT
// step's inputs (1-cycle latency handled inside the task).
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module output_analytics_tb;

    // ---- Parameters mirrored from the DUT ----------------------------------
    localparam DATA_WIDTH   = 12;
    localparam TS_WIDTH     = 32;
    localparam STATUS_WIDTH = 2;
    localparam HEALTH_WIDTH = 8;

    // Event ids (docs/INTERFACES.md 4)
    localparam EV_NONE     = 4'd0;
    localparam EV_PUMP_ON  = 4'd1;
    localparam EV_PUMP_OFF = 4'd2;
    localparam EV_WEED     = 4'd3;

    // ---- DUT connections ----------------------------------------------------
    reg                     clk, rst, in_valid;
    reg  [DATA_WIDTH-1:0]   avg_moisture;
    reg  [TS_WIDTH-1:0]     timestamp;
    reg                     dry, low_nutrient, hot, cold, weed, anomaly;
    reg  [STATUS_WIDTH-1:0] status_in;
    reg  [HEALTH_WIDTH-1:0] crop_health_in;
    reg  [3:0]              event_id_in;
    reg  [TS_WIDTH-1:0]     event_timestamp_in;

    wire                    pump_on, dose_nutrient;
    wire                    alert_weed, alert_heat, alert_frost, alert_nutrient, alert_anomaly;
    wire [STATUS_WIDTH-1:0] status;
    wire [HEALTH_WIDTH-1:0] crop_health;
    wire [3:0]              event_id;
    wire [TS_WIDTH-1:0]     event_timestamp;
    wire                    out_valid;

    integer errors = 0;

    // ---- Instantiate the DUT ------------------------------------------------
    output_analytics #(
        .DATA_WIDTH(DATA_WIDTH), .TS_WIDTH(TS_WIDTH),
        .STATUS_WIDTH(STATUS_WIDTH), .HEALTH_WIDTH(HEALTH_WIDTH),
        .PUMP_OFF_THRESH(350)
    ) dut (
        .clk(clk), .rst(rst), .in_valid(in_valid),
        .avg_moisture(avg_moisture), .timestamp(timestamp),
        .dry(dry), .low_nutrient(low_nutrient), .hot(hot), .cold(cold),
        .weed(weed), .anomaly(anomaly),
        .status_in(status_in), .crop_health_in(crop_health_in),
        .event_id_in(event_id_in), .event_timestamp_in(event_timestamp_in),
        .pump_on(pump_on), .dose_nutrient(dose_nutrient),
        .alert_weed(alert_weed), .alert_heat(alert_heat), .alert_frost(alert_frost),
        .alert_nutrient(alert_nutrient), .alert_anomaly(alert_anomaly),
        .status(status), .crop_health(crop_health),
        .event_id(event_id), .event_timestamp(event_timestamp),
        .out_valid(out_valid)
    );

    // ---- Clock: 10ns period -------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- Drive one valid decision set, then wait for it to latch ------------
    // After this task returns, the DUT outputs reflect THESE inputs.
    task step(input [DATA_WIDTH-1:0] am, input d, ln, h, c, w, an,
              input [3:0] evin, input [TS_WIDTH-1:0] evts,
              input [STATUS_WIDTH-1:0] st, input [HEALTH_WIDTH-1:0] hl,
              input [TS_WIDTH-1:0] ts);
    begin
        avg_moisture = am; dry = d; low_nutrient = ln; hot = h; cold = c;
        weed = w; anomaly = an; event_id_in = evin; event_timestamp_in = evts;
        status_in = st; crop_health_in = hl; timestamp = ts; in_valid = 1'b1;
        @(posedge clk);   // decisions latch into the registered outputs
        #1;               // let the outputs settle before we inspect them
    end
    endtask

    // ---- Self-check helpers -------------------------------------------------
    task expect1(input actual, input exp, input [8*40:1] name);
    begin
        if (actual !== exp) begin
            errors = errors + 1;
            $display("  [FAIL] %0s = %b (expected %b) @ ts=%0d", name, actual, exp, timestamp);
        end
    end
    endtask

    task expect_ev(input [3:0] actual, input [3:0] exp,
                   input [TS_WIDTH-1:0] ts_actual, input [TS_WIDTH-1:0] ts_exp);
    begin
        if (actual !== exp) begin
            errors = errors + 1;
            $display("  [FAIL] event_id = %0d (expected %0d) @ ts=%0d", actual, exp, timestamp);
        end
        if (ts_actual !== ts_exp) begin
            errors = errors + 1;
            $display("  [FAIL] event_timestamp = %0d (expected %0d) @ ts=%0d", ts_actual, ts_exp, timestamp);
        end
    end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, output_analytics_tb);

        // ---- Reset ----------------------------------------------------------
        rst = 1; in_valid = 0;
        avg_moisture = 0; timestamp = 0;
        dry = 0; low_nutrient = 0; hot = 0; cold = 0; weed = 0; anomaly = 0;
        status_in = 0; crop_health_in = 0; event_id_in = 0; event_timestamp_in = 0;
        @(posedge clk); @(posedge clk);
        rst = 0;
        $display("=== output_analytics: Phase 4 story trace ===");

        // ===================================================================
        // 1. Soil goes DRY -> pump turns ON, PUMP_ON event stamped at ts=100
        // ===================================================================
        step(180, 1,0,0,0,0,0, EV_NONE,0, 1,195, 100);
        $display("ts=100 avgM=180 dry -> pump_on=%0d event=%0d ev_ts=%0d",
                 pump_on, event_id, event_timestamp);
        expect1(pump_on, 1'b1, "pump_on(dry->ON)");
        expect_ev(event_id, EV_PUMP_ON, event_timestamp, 100);
        expect1(out_valid, 1'b1, "out_valid");
        expect1(status == 1, 1'b1, "status passthrough=WARNING");

        // ===================================================================
        // 2. Soil recovers INTO the hysteresis band (200..350) -> pump HOLDS ON
        //    (dry=0 now, but avg_moisture <= 350) - proves NO chatter.
        // ===================================================================
        step(260, 0,0,0,0,0,0, EV_NONE,0, 0,255, 110);
        $display("ts=110 avgM=260 (band) -> pump_on=%0d event=%0d", pump_on, event_id);
        expect1(pump_on, 1'b1, "pump_on holds in band(260)");
        expect_ev(event_id, EV_NONE, event_timestamp, 100); // ts holds last event

        step(340, 0,0,0,0,0,0, EV_NONE,0, 0,255, 120);
        $display("ts=120 avgM=340 (band) -> pump_on=%0d event=%0d", pump_on, event_id);
        expect1(pump_on, 1'b1, "pump_on holds in band(340)");
        expect_ev(event_id, EV_NONE, event_timestamp, 100);

        // ===================================================================
        // 3. Soil crosses 350 -> pump turns OFF, PUMP_OFF event stamped at ts=130
        // ===================================================================
        step(360, 0,0,0,0,0,0, EV_NONE,0, 0,255, 130);
        $display("ts=130 avgM=360 (>350) -> pump_on=%0d event=%0d ev_ts=%0d",
                 pump_on, event_id, event_timestamp);
        expect1(pump_on, 1'b0, "pump_on OFF(>350)");
        expect_ev(event_id, EV_PUMP_OFF, event_timestamp, 130);

        // ===================================================================
        // 4. Soil dips back below 350 but is NOT dry -> pump STAYS OFF
        //    (no re-trigger until it is actually dry again).
        // ===================================================================
        step(210, 0,0,0,0,0,0, EV_NONE,0, 0,255, 140);
        $display("ts=140 avgM=210 (not dry) -> pump_on=%0d event=%0d", pump_on, event_id);
        expect1(pump_on, 1'b0, "pump_on stays OFF(210,not dry)");
        expect_ev(event_id, EV_NONE, event_timestamp, 130);

        // ===================================================================
        // 5. Second DRY spell -> pump RE-ARMS (turns back ON) at ts=150
        // ===================================================================
        step(190, 1,0,0,0,0,0, EV_NONE,0, 1,195, 150);
        $display("ts=150 avgM=190 dry -> pump_on=%0d event=%0d ev_ts=%0d",
                 pump_on, event_id, event_timestamp);
        expect1(pump_on, 1'b1, "pump_on RE-ARM(dry->ON)");
        expect_ev(event_id, EV_PUMP_ON, event_timestamp, 150);

        // ===================================================================
        // 6. EVENT PRIORITY: engine reports WEED the same cycle the pump would
        //    turn OFF (avgM=800>350).  Engine event WINS event_id; pump still
        //    actuates OFF.  Alerts reflect the conditions.
        // ===================================================================
        step(800, 0,0,0,0,1,0, EV_WEED,160, 2,175, 160);
        $display("ts=160 avgM=800 weed+pumpOFF -> pump_on=%0d event=%0d ev_ts=%0d alert_weed=%0d",
                 pump_on, event_id, event_timestamp, alert_weed);
        expect1(pump_on, 1'b0, "pump_on OFF while engine event present");
        expect_ev(event_id, EV_WEED, event_timestamp, 160); // engine event wins
        expect1(alert_weed, 1'b1, "alert_weed");

        // ===================================================================
        // 7. ALERT MAPPING: hot + low_nutrient + anomaly (no engine event).
        // ===================================================================
        step(800, 0,1,1,0,0,1, EV_NONE,0, 2,80, 170);
        $display("ts=170 hot+lown+anom -> heat=%0d frost=%0d nutrient=%0d anomaly=%0d dose=%0d",
                 alert_heat, alert_frost, alert_nutrient, alert_anomaly, dose_nutrient);
        expect1(alert_heat,     1'b1, "alert_heat");
        expect1(alert_frost,    1'b0, "alert_frost(off)");
        expect1(alert_nutrient, 1'b1, "alert_nutrient");
        expect1(alert_anomaly,  1'b1, "alert_anomaly");
        expect1(dose_nutrient,  1'b1, "dose_nutrient");
        expect1(alert_weed,     1'b0, "alert_weed(off)");

        // ===================================================================
        // 8. FROST: cold -> alert_frost.
        // ===================================================================
        step(800, 0,0,0,1,0,0, EV_NONE,0, 2,205, 180);
        $display("ts=180 cold -> frost=%0d heat=%0d", alert_frost, alert_heat);
        expect1(alert_frost, 1'b1, "alert_frost");
        expect1(alert_heat,  1'b0, "alert_heat(off)");
        expect1(dose_nutrient, 1'b0, "dose_nutrient(off)");

        // ===================================================================
        // 9. in_valid drops: no new event, out_valid falls, pump state holds.
        // ===================================================================
        in_valid = 0; @(posedge clk); #1;
        $display("in_valid=0 -> out_valid=%0d event=%0d pump_on=%0d",
                 out_valid, event_id, pump_on);
        expect1(out_valid, 1'b0, "out_valid drops with in_valid");
        expect_ev(event_id, EV_NONE, event_timestamp, 160); // ts held from last real event (WEED@160)

        // ---- Verdict --------------------------------------------------------
        $display("=====================================================");
        if (errors == 0) $display("RESULT: PASS (0 errors) - Phase 4 output_analytics verified");
        else             $display("RESULT: FAIL (%0d errors)", errors);
        $display("=====================================================");
        $finish;
    end

endmodule
