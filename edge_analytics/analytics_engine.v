// analytics_engine.v
// -----------------------------------------------------------------------------
// Analytics Engine - Phase 3 of the Edge Analytics IP (mandatory feature #3 +
// the anomaly / sensor-fusion bonuses).
//
// PURPOSE:
//   This is the "brain" of the chip. It takes the 3 SMOOTHED channels coming out
//   of the smoothing stage (moisture / nutrient / temperature) and turns them
//   into DECISIONS:
//     - simple threshold conditions   : dry, low_nutrient, hot, cold
//     - a temperature-compensated WEED detector (abnormal moisture depletion rate)
//     - a rail-stuck sensor ANOMALY check
//     - a fused 8-bit crop_health score
//     - an overall status (SAFE / WARNING / CRITICAL)
//     - an edge-triggered event_id + event_timestamp (the "when" of each alarm)
//   Everything downstream (the actuator bus in Phase 4, the live dashboard) reads
//   these decisions.  All thresholds live in docs/INTERFACES.md 5 and are exposed
//   here as named parameters so they can be tuned in one place.
//
// TIMING (important):
//   ALL outputs are REGISTERED (1-cycle latency).  So a smoothed set presented on
//   cycle T (with in_valid=1) produces its decisions on cycle T+1, and
//   out_valid = in_valid delayed by one cycle.  event_timestamp carries the
//   `timestamp` of the very sample that CAUSED the event.
//
// WEED = ABNORMAL DEPLETION RATE, TEMPERATURE-COMPENSATED (the clever bit):
//   A weed steals water, so moisture falls ABNORMALLY FAST.  We keep a tiny
//   history of avg_moisture and compare "now" against the value HIST_DEPTH valid
//   samples ago.  If moisture dropped by more than RATE_THRESH over that span AND
//   it is NOT hot, something is stealing water (a weed).  If it IS hot, the fast
//   drop is just evaporation - so we suppress the weed flag.  That "AND not hot"
//   is the sensor-fusion / temperature compensation.  A SLOW, ordinary dry-spell
//   drops gently (< RATE_THRESH over HIST_DEPTH samples) and does NOT trip it.
// -----------------------------------------------------------------------------

module analytics_engine #(
    parameter DATA_WIDTH   = 12,   // bits per (smoothed) sensor sample, 0-4095
    parameter TS_WIDTH     = 32,   // timestamp width (free-running cycle count)
    parameter STATUS_WIDTH = 2,    // 0=SAFE, 1=WARNING, 2=CRITICAL
    parameter HEALTH_WIDTH = 8,    // crop-health score 0-255

    // ---- Thresholds & analytics params (docs/INTERFACES.md 5) --------------
    parameter DRY_THRESH   = 200,  // dry          = avg_moisture < 200
    parameter NUT_THRESH   = 250,  // low_nutrient = avg_nutrient < 250
    parameter HOT_THRESH   = 400,  // hot          = avg_temp     > 400
    parameter COLD_THRESH  = 100,  // cold         = avg_temp     < 100
    parameter HIST_DEPTH   = 4,    // compare moisture this many valid-samples back
    parameter RATE_THRESH  = 100   // weed = moisture dropped > 100 over HIST_DEPTH
)(
    input  wire                    clk,          // system clock
    input  wire                    rst,          // synchronous, active-high reset

    // ---- Inputs: the smoothed set from the smoothing stage -----------------
    input  wire [DATA_WIDTH-1:0]   avg_moisture, // ch0 smoothed - decisions use THIS
    input  wire [DATA_WIDTH-1:0]   avg_nutrient, // ch1 smoothed
    input  wire [DATA_WIDTH-1:0]   avg_temp,     // ch2 smoothed
    input  wire [TS_WIDTH-1:0]     timestamp,    // "when" this smoothed set is from
    input  wire                    in_valid,     // 1 = a fresh smoothed set is present

    // ---- Outputs: the decisions (ALL registered) ---------------------------
    output reg                     dry,          // soil too dry
    output reg                     low_nutrient, // nutrient below threshold
    output reg                     hot,          // temperature too high
    output reg                     cold,         // temperature too low
    output reg                     weed,         // resource-stealing weed detected
    output reg                     anomaly,      // rail-stuck / faulty sensor
    output reg  [STATUS_WIDTH-1:0] status,       // 0=SAFE 1=WARNING 2=CRITICAL
    output reg  [HEALTH_WIDTH-1:0] crop_health,  // fused health score (higher=healthier)
    output reg  [3:0]              event_id,     // which event fired this cycle (0=none)
    output reg  [TS_WIDTH-1:0]     event_timestamp, // time the event fired
    output reg                     out_valid     // 1 = outputs valid this cycle
);

    // ---- Event ids (must match docs/INTERFACES.md 4) ------------------------
    localparam EV_NONE         = 4'd0;
    localparam EV_PUMP_ON      = 4'd1;   // produced later in Phase 4
    localparam EV_PUMP_OFF     = 4'd2;   // produced later in Phase 4
    localparam EV_WEED         = 4'd3;   // WEED_DETECTED
    localparam EV_NUTRIENT_LOW = 4'd4;   // NUTRIENT_LOW
    localparam EV_HEAT         = 4'd5;   // HEAT_STRESS
    localparam EV_FROST        = 4'd6;   // FROST_RISK
    localparam EV_ANOMALY      = 4'd7;   // SENSOR_ANOMALY
    localparam EV_STATUS_CRIT  = 4'd8;   // STATUS_CRITICAL (status just became 2)

    // ---- Moisture history shift register (for the weed depletion-rate check) -
    //   moist_hist[0]            = newest pushed value (last valid sample)
    //   moist_hist[HIST_DEPTH-1] = value HIST_DEPTH valid-samples ago
    // We push avg_moisture on every in_valid.  Reading moist_hist[HIST_DEPTH-1]
    // inside the clocked block reads the OLD (pre-push) contents, which is exactly
    // the sample from HIST_DEPTH cycles back - what we want to compare against.
    reg [DATA_WIDTH-1:0] moist_hist [0:HIST_DEPTH-1];

    // ---- Previous-value trackers, for 0->1 RISING-edge event detection -------
    reg                     prev_weed;
    reg                     prev_anomaly;
    reg                     prev_cold;
    reg                     prev_hot;
    reg                     prev_low_nutrient;
    reg  [STATUS_WIDTH-1:0] prev_status;

    // ---- Combinational scratch (computed with = each valid cycle, then latched)
    reg                     d_dry, d_lown, d_hot, d_cold, d_weed, d_anom;
    reg  [DATA_WIDTH-1:0]   dropped;      // moisture fall over the HIST_DEPTH span
    integer                 active;       // count of mild conditions
    integer                 health_calc;  // signed so we can clamp at >= 0
    reg  [STATUS_WIDTH-1:0] s_calc;       // status this cycle
    reg  [3:0]              ev;           // chosen event this cycle
    integer                 i;            // shift-register loop index

    always @(posedge clk) begin
        if (rst) begin
            // Reset every output and all internal state to a clean, safe zero.
            dry <= 0; low_nutrient <= 0; hot <= 0; cold <= 0; weed <= 0; anomaly <= 0;
            status <= 0; crop_health <= 0; event_id <= EV_NONE;
            event_timestamp <= 0; out_valid <= 0;
            prev_weed <= 0; prev_anomaly <= 0; prev_cold <= 0;
            prev_hot <= 0; prev_low_nutrient <= 0; prev_status <= 0;
            for (i = 0; i < HIST_DEPTH; i = i + 1)
                moist_hist[i] <= 0;
        end else begin
            // out_valid is simply in_valid delayed one cycle (registered latency).
            out_valid <= in_valid;

            if (in_valid) begin
                // ---- (a) Threshold conditions (combinational on this sample) ---
                d_dry  = (avg_moisture < DRY_THRESH);
                d_lown = (avg_nutrient < NUT_THRESH);
                d_hot  = (avg_temp     > HOT_THRESH);
                d_cold = (avg_temp     < COLD_THRESH);

                // ---- (b) Weed = temperature-compensated depletion rate --------
                // Guard the subtract against underflow: only meaningful when the
                // past value is actually higher than now (moisture fell).
                if (moist_hist[HIST_DEPTH-1] > avg_moisture)
                    dropped = moist_hist[HIST_DEPTH-1] - avg_moisture;
                else
                    dropped = 0;

                d_weed = (moist_hist[HIST_DEPTH-1] > avg_moisture) // moisture fell
                       && (dropped > RATE_THRESH)                  // steeper than a dry-spell
                       && !d_hot;                                  // hot => evaporation, not weed

                // ---- (c) Anomaly: rail-stuck sensor (0 or full-scale) ---------
                d_anom = (avg_moisture == 0) || (avg_moisture == {DATA_WIDTH{1'b1}});

                // ---- (d) crop_health fusion (start 255, subtract, clamp >=0) --
                health_calc = 255;
                if (d_dry)  health_calc = health_calc - 60;
                if (d_lown) health_calc = health_calc - 50;
                if (d_hot)  health_calc = health_calc - 50;
                if (d_cold) health_calc = health_calc - 50;
                if (d_weed) health_calc = health_calc - 80;
                if (d_anom) health_calc = health_calc - 40;
                if (health_calc < 0) health_calc = 0;

                // ---- (e) status = SAFE / WARNING / CRITICAL -------------------
                active = d_dry + d_lown + d_hot + d_cold;   // count of mild conditions
                if (d_weed || d_anom || d_cold || (active >= 2))
                    s_calc = 2;                             // CRITICAL
                else if (active == 1)
                    s_calc = 1;                             // WARNING
                else
                    s_calc = 0;                             // SAFE

                // ---- (f) event_id: edge-triggered, prioritized ----------------
                // Fire on a 0->1 rising edge; among edges the same cycle pick the
                // highest priority: ANOMALY > WEED > FROST > HEAT > NUTRIENT_LOW
                // > STATUS_CRITICAL (status freshly became 2).
                if      (d_anom && !prev_anomaly)               ev = EV_ANOMALY;
                else if (d_weed && !prev_weed)                  ev = EV_WEED;
                else if (d_cold && !prev_cold)                  ev = EV_FROST;
                else if (d_hot  && !prev_hot)                   ev = EV_HEAT;
                else if (d_lown && !prev_low_nutrient)          ev = EV_NUTRIENT_LOW;
                else if ((s_calc == 2) && (prev_status != 2))   ev = EV_STATUS_CRIT;
                else                                            ev = EV_NONE;

                // ---- Latch the decisions into the registered outputs ----------
                dry <= d_dry; low_nutrient <= d_lown; hot <= d_hot;
                cold <= d_cold; weed <= d_weed; anomaly <= d_anom;
                crop_health <= health_calc[HEALTH_WIDTH-1:0];
                status <= s_calc;
                event_id <= ev;
                // Only stamp a NEW time when an event actually fires; otherwise
                // hold the last event's timestamp.
                if (ev != EV_NONE)
                    event_timestamp <= timestamp;

                // ---- Update edge trackers to THIS sample's conditions ---------
                prev_weed <= d_weed; prev_anomaly <= d_anom; prev_cold <= d_cold;
                prev_hot <= d_hot; prev_low_nutrient <= d_lown; prev_status <= s_calc;

                // ---- Push avg_moisture into the history shift register ---------
                for (i = HIST_DEPTH-1; i > 0; i = i - 1)
                    moist_hist[i] <= moist_hist[i-1];
                moist_hist[0] <= avg_moisture;
            end else begin
                // No fresh sample this cycle -> no new event; hold everything else.
                event_id <= EV_NONE;
            end
        end
    end

endmodule
