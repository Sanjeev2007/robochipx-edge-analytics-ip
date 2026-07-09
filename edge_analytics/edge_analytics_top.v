// edge_analytics_top.v
// -----------------------------------------------------------------------------
// Edge Analytics IP - TOP LEVEL (Phase 5: integration + live-stream egress).
//
// PURPOSE:
//   Wire the four ALREADY-BUILT blocks into one chip and expose a single, fully
//   ALIGNED output bundle that the testbench turns into the live D / E stream:
//
//     sensor_collector -> smoothing_stage -> analytics_engine -> output_analytics
//
//   This file is PURE WIRING + ALIGNMENT.  None of the sub-modules are modified.
//
// ==> THE LATENCY-ALIGNMENT PROBLEM (the whole reason this phase is tricky) <==
//   Each field on a "D" dashboard line is BORN at a different pipeline stage, so
//   they come out on different cycles.  Follow ONE sample S down the pipe; below,
//   "t=k" means "S's value is valid on the output of that stage on cycle k":
//
//     t=1  sensor_collector : raw moisture/nutrient/temp, timestamp
//     t=2  smoothing_stage  : avg moisture/nutrient/temp   (moving_avg registers)
//     t=3  analytics_engine : dry/weed/status/health/event (all registered)
//     t=4  output_analytics : pump_on/alerts/event         (all registered)
//
//   The D line is printed at the FINAL stage (t=4).  To make every field on that
//   line belong to the SAME sample S we delay the earlier-born fields forward:
//
//     | field                         | born at | needs | delay added here |
//     |-------------------------------|---------|-------|------------------|
//     | raw moisture/nutrient/temp    |  t=1    |  t=4  |  +3              |
//     | sample timestamp              |  t=1    |  t=4  |  +3              |
//     | avg moisture/nutrient/temp    |  t=2    |  t=4  |  +2              |
//     | pump/status/health/event_*    |  t=4    |  t=4  |   0 (already here)|
//
//   The valid strobe itself is just a plain 1-clock delay at every stage
//   (avg_valid=sample_valid delayed 1; out_valid=in_valid delayed 1; ...), so a
//   PLAIN clock-cycle shift register keeps the delayed data locked to the valid
//   strobe even across sensor gaps.  That is why plain shift registers (not
//   valid-gated ones) are the correct, simplest fix.
//
//   output_analytics ALSO needs two of these fields at ITS OWN input cycle (t=3):
//     - avg_moisture (+1) : to test avg_moisture > PUMP_OFF_THRESH for hysteresis
//     - timestamp    (+2) : to stamp the PUMP_ON / PUMP_OFF events it generates
//   (see docs/INTERFACES.md 2, output_analytics inputs.)  We tap the same delay
//   lines at the right depth for those.
//
// ==> PHASE-8 INTEGRATION (two new blocks wired in, no sub-module changed) <==
//   Two verified stand-alone IP blocks are now folded into the pipeline here:
//
//   (A) adaptive_anomaly (Phase 8F, TEDA self-tuning anomaly) runs IN PARALLEL with
//       analytics_engine.  It is fed the SAME smoothed set + valid the engine gets
//       (born at t=2), and like the engine it REGISTERS its outputs, so its
//       anomaly / anom_ch land at t=3 - the exact same cycle as the engine's
//       decisions.  No extra alignment is needed between them.
//         anomaly_merged = ae_anomaly (always-on rail check, inside the engine)
//                        | ta_anomaly (learned TEDA outlier)
//       and anomaly_merged (not the raw engine anomaly) is what feeds
//       output_analytics' .anomaly() input, so alert_anomaly reflects BOTH detectors.
//
//   (B) comms_tx (Phase 8A, sparse caretaker radio) is a SIDE CHANNEL hung off
//       output_analytics' event bus (t=4).  A real engine/output event always WINS;
//       only when the merged pipeline reports NONE do we INJECT a SENSOR_ANOMALY
//       event on the 0->1 edge of the TEDA anomaly (a TEDA-only anomaly the engine's
//       event path never raised, because that path keys off the raw rail check).
//       Its outputs are +1 vs the aligned D-bundle (t=5) - that is fine: it is the
//       ASYNC caretaker radio, deliberately NOT part of the 17-field aligned row.
// -----------------------------------------------------------------------------

module edge_analytics_top #(
    parameter DATA_WIDTH      = 12,   // bits per sensor sample (0-4095)
    parameter TS_WIDTH        = 32,   // free-running timestamp width
    parameter STATUS_WIDTH    = 2,    // 0=SAFE, 1=WARNING, 2=CRITICAL
    parameter HEALTH_WIDTH    = 8,    // crop-health score 0-255
    parameter LOG2_N          = 3,    // moving-average window = 2^3 = 8 samples
    parameter PUMP_OFF_THRESH = 350   // pump hysteresis turn-off point
)(
    input  wire                    clk,           // system clock
    input  wire                    rst,           // synchronous, active-high reset

    // ---- Raw sensor inputs (from the field) --------------------------------
    input  wire [DATA_WIDTH-1:0]   moisture_in,   // ch0 raw soil moisture (noisy)
    input  wire [DATA_WIDTH-1:0]   nutrient_in,   // ch1 raw nutrient / NPK  (noisy)
    input  wire [DATA_WIDTH-1:0]   temp_in,       // ch2 raw temperature     (noisy)
    input  wire                    sensors_valid, // 1 = new readings this cycle

    // ---- Aligned output bundle (the "D" line + the "E" event, all @ out_valid)
    output wire [TS_WIDTH-1:0]     out_timestamp,     // "when" of THIS sample (aligned +3)
    output wire [DATA_WIDTH-1:0]   out_moisture,      // raw moisture, aligned (+3)
    output wire [DATA_WIDTH-1:0]   out_nutrient,      // raw nutrient, aligned (+3)
    output wire [DATA_WIDTH-1:0]   out_temp,          // raw temperature, aligned (+3)
    output wire [DATA_WIDTH-1:0]   out_avg_moisture,  // smoothed moisture, aligned (+2)
    output wire [DATA_WIDTH-1:0]   out_avg_nutrient,  // smoothed nutrient, aligned (+2)
    output wire [DATA_WIDTH-1:0]   out_avg_temp,      // smoothed temperature, aligned (+2)
    output wire                    out_pump_on,       // irrigation pump (with hysteresis)
    output wire                    out_dose_nutrient, // fertilizer doser
    output wire                    out_alert_weed,    // weed alert
    output wire                    out_alert_heat,    // heat-stress alert
    output wire                    out_alert_frost,   // frost-risk alert
    output wire                    out_alert_nutrient,// low-nutrient alert
    output wire                    out_alert_anomaly, // sensor-anomaly alert
    output wire [STATUS_WIDTH-1:0] out_status,        // 0=SAFE 1=WARNING 2=CRITICAL
    output wire [HEALTH_WIDTH-1:0] out_crop_health,   // fused crop-health score
    output wire [3:0]              out_event_id,      // event this cycle (0=none, see 4)
    output wire [TS_WIDTH-1:0]     out_event_timestamp,// time the event fired
    output wire                    out_valid,         // 1 = the bundle above is valid

    // ---- Phase-8 additions: TEDA anomaly + Tier-2 caretaker radio -----------
    //   These are NOT part of the aligned 17-field D row.  out_anom_ch is a debug
    //   view of the per-channel TEDA flags (delayed +1 to sit on the same cycle as
    //   the alert bus, t=4).  The comms_tx outputs are the SPARSE, async caretaker
    //   radio and land one cycle LATER than the D-bundle (t=5) - see header (B).
    output wire [2:0]              out_anom_ch,       // per-channel TEDA flags (bit c = ch c)
    output wire                    out_msg_valid,     // 1-cycle strobe: a caretaker packet is TX'd
    output wire [63:0]             out_alert_packet,  // the 64-bit caretaker alert packet (INTERFACES 6)
    output wire [15:0]             out_msg_count      // running tally of caretaker packets sent
);

    // ---- Event ids referenced at this level (must match docs/INTERFACES.md 4) -
    localparam [3:0] EV_NONE        = 4'd0;   // no event
    localparam [3:0] EV_SENSOR_ANOM = 4'd7;   // injected for a TEDA-only anomaly

    // =========================================================================
    // STAGE 1 - sensor_collector : timestamp + snapshot the 3 raw channels
    // =========================================================================
    wire [DATA_WIDTH-1:0] sc_moisture, sc_nutrient, sc_temp;
    wire [TS_WIDTH-1:0]   sc_timestamp;
    wire                  sc_valid;

    sensor_collector #(
        .DATA_WIDTH(DATA_WIDTH),
        .TS_WIDTH  (TS_WIDTH)
    ) u_sensor_collector (
        .clk          (clk),
        .rst          (rst),
        .moisture_in  (moisture_in),
        .nutrient_in  (nutrient_in),
        .temp_in      (temp_in),
        .sensors_valid(sensors_valid),
        .moisture     (sc_moisture),
        .nutrient     (sc_nutrient),
        .temp         (sc_temp),
        .timestamp    (sc_timestamp),
        .sample_valid (sc_valid)
    );

    // =========================================================================
    // STAGE 2 - smoothing_stage : 3x moving_avg (one per channel)
    // =========================================================================
    wire [DATA_WIDTH-1:0] sm_avg_moisture, sm_avg_nutrient, sm_avg_temp;
    wire [TS_WIDTH-1:0]   sm_timestamp_unused; // its own +1 ts; we build our own line
    wire                  sm_valid;

    smoothing_stage #(
        .DATA_WIDTH(DATA_WIDTH),
        .LOG2_N    (LOG2_N),
        .TS_WIDTH  (TS_WIDTH)
    ) u_smoothing_stage (
        .clk          (clk),
        .rst          (rst),
        .moisture_in  (sc_moisture),
        .nutrient_in  (sc_nutrient),
        .temp_in      (sc_temp),
        .timestamp_in (sc_timestamp),
        .sample_valid (sc_valid),
        .avg_moisture (sm_avg_moisture),
        .avg_nutrient (sm_avg_nutrient),
        .avg_temp     (sm_avg_temp),
        .timestamp_out(sm_timestamp_unused),
        .avg_valid    (sm_valid)
    );

    // =========================================================================
    // DELAY LINES (the alignment fix) - all PLAIN clock-cycle shift registers
    // =========================================================================
    // Timestamp: tap +2 (for output_analytics) and +3 (for the D line).
    reg [TS_WIDTH-1:0] ts_d1, ts_d2, ts_d3;
    // Raw channels: +3 to reach the output_analytics stage for the D line.
    reg [DATA_WIDTH-1:0] m_d1, m_d2, m_d3;
    reg [DATA_WIDTH-1:0] n_d1, n_d2, n_d3;
    reg [DATA_WIDTH-1:0] t_d1, t_d2, t_d3;
    // Averages: tap +1 (moisture, for output_analytics hysteresis) and +2 (D line).
    reg [DATA_WIDTH-1:0] am_d1, am_d2;
    reg [DATA_WIDTH-1:0] an_d1, an_d2;
    reg [DATA_WIDTH-1:0] at_d1, at_d2;

    always @(posedge clk) begin
        if (rst) begin
            ts_d1 <= 0; ts_d2 <= 0; ts_d3 <= 0;
            m_d1 <= 0; m_d2 <= 0; m_d3 <= 0;
            n_d1 <= 0; n_d2 <= 0; n_d3 <= 0;
            t_d1 <= 0; t_d2 <= 0; t_d3 <= 0;
            am_d1 <= 0; am_d2 <= 0;
            an_d1 <= 0; an_d2 <= 0;
            at_d1 <= 0; at_d2 <= 0;
        end else begin
            // timestamp born at t=1 -> ts_d1 is +1, ts_d2 is +2, ts_d3 is +3
            ts_d1 <= sc_timestamp; ts_d2 <= ts_d1; ts_d3 <= ts_d2;
            // raw channels born at t=1 -> *_d3 is +3
            m_d1 <= sc_moisture; m_d2 <= m_d1; m_d3 <= m_d2;
            n_d1 <= sc_nutrient; n_d2 <= n_d1; n_d3 <= n_d2;
            t_d1 <= sc_temp;     t_d2 <= t_d1; t_d3 <= t_d2;
            // averages born at t=2 -> *_d1 is +1, *_d2 is +2
            am_d1 <= sm_avg_moisture; am_d2 <= am_d1;
            an_d1 <= sm_avg_nutrient; an_d2 <= an_d1;
            at_d1 <= sm_avg_temp;     at_d2 <= at_d1;
        end
    end

    // =========================================================================
    // STAGE 3 - analytics_engine : the decisions (fed the smoothed set directly)
    // =========================================================================
    wire                    ae_dry, ae_low_nutrient, ae_hot, ae_cold, ae_weed, ae_anomaly;
    wire [STATUS_WIDTH-1:0] ae_status;
    wire [HEALTH_WIDTH-1:0] ae_crop_health;
    wire [3:0]              ae_event_id;
    wire [TS_WIDTH-1:0]     ae_event_timestamp;
    wire                    ae_valid;

    analytics_engine #(
        .DATA_WIDTH  (DATA_WIDTH),
        .TS_WIDTH    (TS_WIDTH),
        .STATUS_WIDTH(STATUS_WIDTH),
        .HEALTH_WIDTH(HEALTH_WIDTH)
    ) u_analytics_engine (
        .clk            (clk),
        .rst            (rst),
        .avg_moisture   (sm_avg_moisture),   // fed straight from smoothing (t=2)
        .avg_nutrient   (sm_avg_nutrient),
        .avg_temp       (sm_avg_temp),
        .timestamp      (sm_timestamp_unused), // smoothing's own +1 ts == this set's "when"
        .in_valid       (sm_valid),
        .dry            (ae_dry),
        .low_nutrient   (ae_low_nutrient),
        .hot            (ae_hot),
        .cold           (ae_cold),
        .weed           (ae_weed),
        .anomaly        (ae_anomaly),
        .status         (ae_status),
        .crop_health    (ae_crop_health),
        .event_id       (ae_event_id),
        .event_timestamp(ae_event_timestamp),
        .out_valid      (ae_valid)
    );

    // =========================================================================
    // STAGE 3b - adaptive_anomaly : TEDA self-tuning anomaly, IN PARALLEL with
    //   the engine.  Fed the SAME smoothed set (t=2) + sm_valid; it REGISTERS its
    //   outputs, so ta_anomaly / ta_anom_ch land at t=3 - the SAME cycle as the
    //   engine's ae_* decisions.  No extra alignment is needed (see header (A)).
    // =========================================================================
    wire            ta_anomaly;          // 1 = ANY channel flagged by TEDA (t=3)
    wire [2:0]      ta_anom_ch;           // per-channel TEDA flags (bit c = ch c)  (t=3)

    adaptive_anomaly #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_CH    (3)
    ) u_adaptive_anomaly (
        .clk         (clk),
        .rst         (rst),
        .in_valid    (sm_valid),         // same valid the engine sees (t=2 -> t=3)
        .avg_moisture(sm_avg_moisture),  // same smoothed set the engine sees
        .avg_nutrient(sm_avg_nutrient),
        .avg_temp    (sm_avg_temp),
        .anomaly     (ta_anomaly),
        .anom_ch     (ta_anom_ch)
    );

    // Merge the two anomaly detectors on the SAME cycle (both t=3):
    //   ae_anomaly = engine's always-on rail-stuck check (dead sensor at 0/4095)
    //   ta_anomaly = TEDA's learned statistical outlier (wrong-but-in-range value)
    // The merged flag is what output_analytics turns into alert_anomaly.
    wire anomaly_merged = ae_anomaly | ta_anomaly;

    // =========================================================================
    // STAGE 4 - output_analytics : the clean actuator/alert bus
    //   Its inputs land on cycle t=3 (the analytics_engine output cycle), so it
    //   is fed avg_moisture delayed +1 (am_d1) and timestamp delayed +2 (ts_d2).
    // =========================================================================
    wire                    oa_pump_on, oa_dose_nutrient;
    wire                    oa_alert_weed, oa_alert_heat, oa_alert_frost;
    wire                    oa_alert_nutrient, oa_alert_anomaly;
    wire [STATUS_WIDTH-1:0] oa_status;
    wire [HEALTH_WIDTH-1:0] oa_crop_health;
    wire [3:0]              oa_event_id;
    wire [TS_WIDTH-1:0]     oa_event_timestamp;
    wire                    oa_valid;

    output_analytics #(
        .DATA_WIDTH     (DATA_WIDTH),
        .TS_WIDTH       (TS_WIDTH),
        .STATUS_WIDTH   (STATUS_WIDTH),
        .HEALTH_WIDTH   (HEALTH_WIDTH),
        .PUMP_OFF_THRESH(PUMP_OFF_THRESH)
    ) u_output_analytics (
        .clk               (clk),
        .rst               (rst),
        .in_valid          (ae_valid),
        .avg_moisture      (am_d1),  // +1 -> aligned with the engine decisions (t=3)
        .timestamp         (ts_d2),  // +2 -> the "when" for generated pump events
        .dry               (ae_dry),
        .low_nutrient      (ae_low_nutrient),
        .hot               (ae_hot),
        .cold              (ae_cold),
        .weed              (ae_weed),
        .anomaly           (anomaly_merged),  // rail-check OR TEDA (see STAGE 3b)
        .status_in         (ae_status),
        .crop_health_in    (ae_crop_health),
        .event_id_in       (ae_event_id),
        .event_timestamp_in(ae_event_timestamp),
        .pump_on           (oa_pump_on),
        .dose_nutrient     (oa_dose_nutrient),
        .alert_weed        (oa_alert_weed),
        .alert_heat        (oa_alert_heat),
        .alert_frost       (oa_alert_frost),
        .alert_nutrient    (oa_alert_nutrient),
        .alert_anomaly     (oa_alert_anomaly),
        .status            (oa_status),
        .crop_health       (oa_crop_health),
        .event_id          (oa_event_id),
        .event_timestamp   (oa_event_timestamp),
        .out_valid         (oa_valid)
    );

    // =========================================================================
    // STAGE 5 - comms_tx : the SPARSE Tier-2 caretaker radio (side channel)
    //
    //   output_analytics emits its event bus at t=4.  The TEDA anomaly ta_anomaly
    //   is born at t=3, so we delay it +1 (ta_anom_d) to sit on the SAME t=4 cycle,
    //   and edge-detect its 0->1 rise there.  A rising edge means "a TEDA-only
    //   anomaly just started this sample".
    //
    //   Event feed for comms (engine/output event ALWAYS wins; the TEDA injection
    //   only fills in when the merged pipeline itself reported NONE - i.e. a
    //   TEDA-only anomaly, which the engine's event path never raised because that
    //   path keys off the raw rail check, not the merged flag):
    //     comms_event_id = (oa_event_id != NONE) ? oa_event_id
    //                      : ta_anomaly_rising   ? EV_SENSOR_ANOM(7) : NONE
    //   The matching timestamp is the real event's stamp, or - for an injection -
    //   this sample's own aligned timestamp (ts_d3, the t=4 D-line "when").
    // =========================================================================
    reg [2:0] ta_anom_ch_d;      // per-channel TEDA flags, delayed +1 (now at t=4)
    reg       ta_anom_d;         // TEDA anomaly delayed +1 (now aligned to t=4)
    reg       ta_anom_d_prev;    // previous t=4-aligned TEDA anomaly (for edge detect)

    always @(posedge clk) begin
        if (rst) begin
            ta_anom_ch_d   <= 3'b0;
            ta_anom_d      <= 1'b0;
            ta_anom_d_prev <= 1'b0;
        end else begin
            ta_anom_ch_d   <= ta_anom_ch;  // t=3 -> t=4 (line up with the alert bus)
            ta_anom_d      <= ta_anomaly;  // t=3 -> t=4 (line up with oa event bus)
            ta_anom_d_prev <= ta_anom_d;   // one more cycle back, for the rising edge
        end
    end

    // 0->1 rising edge of the (t=4-aligned) TEDA anomaly.  One-cycle pulse.
    wire ta_anomaly_rising = ta_anom_d & ~ta_anom_d_prev;

    // Build the comms event feed (engine/output event wins; else inject on a TEDA
    // rise).  All combinational off the t=4 bus, so it lines up with oa_valid.
    wire [3:0]          comms_event_id =
             (oa_event_id != EV_NONE) ? oa_event_id
           : (ta_anomaly_rising      ? EV_SENSOR_ANOM : EV_NONE);
    wire [TS_WIDTH-1:0] comms_event_ts =
             (oa_event_id != EV_NONE) ? oa_event_timestamp
           : ts_d3;   // injected anomaly is stamped with THIS sample's "when"

    wire            cx_msg_valid;
    wire [63:0]     cx_alert_packet;
    wire [15:0]     cx_msg_count;

    comms_tx #(
        .TS_WIDTH    (TS_WIDTH),
        .STATUS_WIDTH(STATUS_WIDTH),
        .HEALTH_WIDTH(HEALTH_WIDTH)
    ) u_comms_tx (
        .clk            (clk),
        .rst            (rst),
        .in_valid       (oa_valid),          // one decision set per valid output cycle
        .event_id       (comms_event_id),    // real event wins, else injected anomaly
        .event_timestamp(comms_event_ts),    // matching timestamp for that event
        .status         (oa_status),         // severity input
        .crop_health    (oa_crop_health),    // rides in the packet
        .msg_valid      (cx_msg_valid),      // +1 vs the D-bundle (t=5) - async radio
        .alert_packet   (cx_alert_packet),
        .msg_count      (cx_msg_count)
    );

    // =========================================================================
    // OUTPUT BUNDLE - every field re-aligned to the output_analytics cycle (t=4)
    // =========================================================================
    assign out_timestamp       = ts_d3;   // +3
    assign out_moisture        = m_d3;    // +3
    assign out_nutrient        = n_d3;    // +3
    assign out_temp            = t_d3;    // +3
    assign out_avg_moisture    = am_d2;   // +2
    assign out_avg_nutrient    = an_d2;   // +2
    assign out_avg_temp        = at_d2;   // +2
    assign out_pump_on         = oa_pump_on;
    assign out_dose_nutrient   = oa_dose_nutrient;
    assign out_alert_weed      = oa_alert_weed;
    assign out_alert_heat      = oa_alert_heat;
    assign out_alert_frost     = oa_alert_frost;
    assign out_alert_nutrient  = oa_alert_nutrient;
    assign out_alert_anomaly   = oa_alert_anomaly;
    assign out_status          = oa_status;
    assign out_crop_health     = oa_crop_health;
    assign out_event_id        = oa_event_id;
    assign out_event_timestamp = oa_event_timestamp;
    assign out_valid           = oa_valid;

    // ---- Phase-8 side outputs (NOT part of the aligned D row) ---------------
    assign out_anom_ch      = ta_anom_ch_d;    // per-channel TEDA flags @ t=4 (debug)
    assign out_msg_valid    = cx_msg_valid;    // caretaker radio strobe (+1 vs D-bundle)
    assign out_alert_packet = cx_alert_packet; // 64-bit caretaker packet
    assign out_msg_count    = cx_msg_count;    // running caretaker-packet tally

endmodule
