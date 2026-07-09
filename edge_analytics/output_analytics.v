// output_analytics.v
// -----------------------------------------------------------------------------
// Output Analytics - Phase 4 of the Edge Analytics IP (mandatory feature #4).
//
// PURPOSE:
//   This is the chip's clean ACTUATOR / ALERT BUS.  The analytics_engine (Phase 3)
//   produces raw decisions (dry, weed, hot, ...) every cycle; this block turns them
//   into stable, registered outputs the outside world acts on:
//     - pump_on        : the irrigation pump, WITH HYSTERESIS so it never chatters
//     - dose_nutrient  : the fertilizer doser (fires while nutrient is low)
//     - alert_*        : the five clean alert lines (weed/heat/frost/nutrient/anomaly)
//     - status / crop_health / event_id / event_timestamp : passed through
//   It ALSO generates the PUMP_ON / PUMP_OFF events (event ids 1 & 2) that the
//   analytics_engine deliberately leaves for this stage (see BUILD_PLAN Phase 3f/4).
//
// PUMP HYSTERESIS (the key requirement - no oscillation):
//   The pump turns ON the moment the soil is `dry` (avg_moisture < 200, decided
//   upstream).  It then STAYS ON - even as the soil climbs back past the dry
//   threshold - until avg_moisture rises above PUMP_OFF_THRESH (350).  This gap
//   between the turn-on point (200) and the turn-off point (350) is the hysteresis
//   band: it stops the pump flickering on/off around a single threshold.
//
// TIMING:
//   ALL outputs are REGISTERED (1-cycle latency), matching the rest of the
//   pipeline.  A decision set presented with in_valid=1 on cycle T produces this
//   block's outputs on cycle T+1, and out_valid = in_valid delayed one cycle.
//
// INTERFACE NOTE (docs/INTERFACES.md 2):
//   The contract lists output_analytics' inputs loosely as "(all analytics_engine
//   outputs)".  Two extra inputs are required and added here:
//     - avg_moisture : needed to test avg_moisture > PUMP_OFF_THRESH for hysteresis
//     - timestamp    : needed to stamp the PUMP_ON / PUMP_OFF events we generate
//   Both are just the corresponding analytics_engine INPUTS carried alongside; at
//   the top level they are delayed to stay aligned with the registered decisions.
// -----------------------------------------------------------------------------

module output_analytics #(
    parameter DATA_WIDTH      = 12,   // bits per (smoothed) sensor sample, 0-4095
    parameter TS_WIDTH        = 32,   // timestamp width (free-running cycle count)
    parameter STATUS_WIDTH    = 2,    // 0=SAFE, 1=WARNING, 2=CRITICAL
    parameter HEALTH_WIDTH    = 8,    // crop-health score 0-255
    parameter PUMP_OFF_THRESH = 350   // pump stays on until avg_moisture > 350
)(
    input  wire                    clk,          // system clock
    input  wire                    rst,          // synchronous, active-high reset

    // ---- Inputs: the decisions from analytics_engine -----------------------
    input  wire                    in_valid,     // 1 = a fresh decision set is present
    input  wire [DATA_WIDTH-1:0]   avg_moisture, // smoothed moisture (for hysteresis)
    input  wire [TS_WIDTH-1:0]     timestamp,    // "when" (to stamp pump events)
    input  wire                    dry,          // soil too dry           -> pump ON
    input  wire                    low_nutrient, // nutrient below threshold
    input  wire                    hot,          // temperature too high
    input  wire                    cold,         // temperature too low
    input  wire                    weed,         // resource-stealing weed detected
    input  wire                    anomaly,      // rail-stuck / faulty sensor
    input  wire [STATUS_WIDTH-1:0] status_in,        // engine's overall status
    input  wire [HEALTH_WIDTH-1:0] crop_health_in,   // engine's fused health score
    input  wire [3:0]              event_id_in,      // engine's event this cycle (0=none)
    input  wire [TS_WIDTH-1:0]     event_timestamp_in, // engine's event timestamp

    // ---- Outputs: the clean actuator/alert bus (ALL registered) ------------
    output reg                     pump_on,      // irrigation pump (with hysteresis)
    output reg                     dose_nutrient,// fertilizer doser
    output reg                     alert_weed,   // weed alert
    output reg                     alert_heat,   // heat-stress alert
    output reg                     alert_frost,  // frost-risk alert
    output reg                     alert_nutrient,// low-nutrient alert
    output reg                     alert_anomaly,// sensor-anomaly alert
    output reg  [STATUS_WIDTH-1:0] status,       // 0=SAFE 1=WARNING 2=CRITICAL
    output reg  [HEALTH_WIDTH-1:0] crop_health,  // fused health score
    output reg  [3:0]              event_id,     // merged event this cycle (0=none)
    output reg  [TS_WIDTH-1:0]     event_timestamp, // its timestamp
    output reg                     out_valid     // 1 = outputs valid this cycle
);

    // ---- Event ids (must match docs/INTERFACES.md 4) ------------------------
    localparam EV_NONE     = 4'd0;
    localparam EV_PUMP_ON  = 4'd1;   // irrigation started (generated HERE)
    localparam EV_PUMP_OFF = 4'd2;   // irrigation stopped (generated HERE)

    // ---- Combinational scratch (evaluated fresh each valid cycle) -----------
    // pump_turn_on / pump_turn_off read the CURRENT pump_on register value, so
    // they describe a genuine 0->1 or 1->0 transition of the pump this cycle.
    reg pump_turn_on;
    reg pump_turn_off;

    always @(posedge clk) begin
        if (rst) begin
            // Reset every output to a clean, safe zero (pump OFF, no alerts).
            pump_on <= 0; dose_nutrient <= 0;
            alert_weed <= 0; alert_heat <= 0; alert_frost <= 0;
            alert_nutrient <= 0; alert_anomaly <= 0;
            status <= 0; crop_health <= 0;
            event_id <= EV_NONE; event_timestamp <= 0; out_valid <= 0;
        end else begin
            // out_valid is simply in_valid delayed one cycle (registered latency).
            out_valid <= in_valid;

            if (in_valid) begin
                // ---- Pump hysteresis -----------------------------------------
                //   turn ON  : pump is off AND soil is dry.
                //   turn OFF : pump is on  AND soil has recovered past 350.
                // (dry means avg_moisture < 200, so these two can never be true at
                //  once - the 200..350 band is where the pump simply holds state.)
                pump_turn_on  = (~pump_on) && dry;
                pump_turn_off = ( pump_on) && (avg_moisture > PUMP_OFF_THRESH);

                if (pump_turn_on)       pump_on <= 1'b1;
                else if (pump_turn_off) pump_on <= 1'b0;
                // else: hold pump_on unchanged (no chatter in the hysteresis band).

                // ---- Fertilizer doser: on while nutrient is low --------------
                dose_nutrient <= low_nutrient;

                // ---- Alert bus: clean registered mirrors of the conditions ---
                alert_weed     <= weed;
                alert_heat     <= hot;
                alert_frost    <= cold;
                alert_nutrient <= low_nutrient;
                alert_anomaly  <= anomaly;

                // ---- Pass-through status + health -----------------------------
                status      <= status_in;
                crop_health <= crop_health_in;

                // ---- Merged event_id -----------------------------------------
                // The analytics_engine already prioritised the severe conditions
                // (anomaly/weed/frost/heat/nutrient/critical), so a real engine
                // event WINS.  When the engine reports NONE, we surface the pump's
                // own PUMP_ON / PUMP_OFF actuation event (with the current time).
                if (event_id_in != EV_NONE) begin
                    event_id        <= event_id_in;
                    event_timestamp <= event_timestamp_in;
                end else if (pump_turn_on) begin
                    event_id        <= EV_PUMP_ON;
                    event_timestamp <= timestamp;
                end else if (pump_turn_off) begin
                    event_id        <= EV_PUMP_OFF;
                    event_timestamp <= timestamp;
                end else begin
                    // Nothing fired: hold event_timestamp (leave the register as-is)
                    // so it keeps the time of the LAST real event, not the engine's
                    // idle input (which is 0 when the engine reports NONE).
                    event_id <= EV_NONE;
                end
            end else begin
                // No fresh decision this cycle -> no new event; hold the rest.
                event_id <= EV_NONE;
            end
        end
    end

endmodule
