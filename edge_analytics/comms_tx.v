// comms_tx.v
// -----------------------------------------------------------------------------
// Comms TX - Phase 8A of the Edge Analytics IP.  ⭐ THE DIFFERENTIATOR.
//
// PURPOSE (the "beyond automation" answer):
//   The chip has TWO output tiers.
//     - Tier 1 = LOCAL ACTUATION (pump_on / dose_nutrient, done in output_analytics):
//       the machine handles routine problems on-chip.  NO message is sent.
//     - Tier 2 = REMOTE COMMS (this block): a SPARSE, event-triggered alert packet
//       sent over a long-range radio (LoRa/GSM) to a HUMAN caretaker's phone, ONLY
//       for exceptions a machine should not handle alone.
//   This block is the machine-to-human channel.  It watches the merged event bus from
//   output_analytics and, on a qualifying event, "transmits" one compact 64-bit
//   alert_packet carrying a RECOMMENDED ACTION for the caretaker (e.g. INSPECT_WEED).
//   Deciding *whether a human is needed* on-chip - and sending K sparse alerts instead
//   of N raw samples - is the edge power/bandwidth win (quantified in Phase 8D).
//
// WHAT FIRES vs WHAT STAYS LOCAL (docs/INTERFACES.md 6):
//   Human-needed  -> packet: WEED_DETECTED, SENSOR_ANOMALY, NUTRIENT_LOW,
//                    STATUS_CRITICAL, FROST_RISK, PREDICT_DRY.
//   Machine-handled -> NO packet: PUMP_ON, PUMP_OFF (the pump already handled it).
//   (HEAT_STRESS is not a caretaker action in the 6 table -> no packet either.)
//
// PACKET LAYOUT (64-bit, MSB->LSB, docs/INTERFACES.md 6):
//   { severity[4], event_code[4], action_code[4], crop_health[8],
//     reserved[12], event_timestamp[32] }
//
// RATE LIMIT (anti-spam):
//   A down-counter (MSG_GAP) blocks a REPEAT of the SAME event until MSG_GAP valid
//   cycles have passed, so a flapping sensor cannot flood the caretaker.  A DIFFERENT
//   event is always allowed through immediately.
//
// TIMING:
//   All outputs are REGISTERED (1-cycle latency), matching the rest of the pipeline.
//   A qualifying event presented with in_valid=1 on cycle T makes msg_valid=1 with the
//   packet on cycle T+1, for exactly one cycle.
// -----------------------------------------------------------------------------

module comms_tx #(
    parameter TS_WIDTH     = 32,    // timestamp width (free-running cycle count)
    parameter STATUS_WIDTH = 2,     // 0=SAFE, 1=WARNING, 2=CRITICAL
    parameter HEALTH_WIDTH = 8,     // crop-health score 0-255
    parameter PKT_WIDTH    = 64,    // alert_packet width (see layout above)
    parameter CNT_WIDTH    = 16,    // msg_count width (transmitted-packet tally)
    parameter MSG_GAP      = 16'd8  // min valid-cycles before the SAME event re-sends (TUNE, 7)
)(
    input  wire                    clk,             // system clock
    input  wire                    rst,             // synchronous, active-high reset

    // ---- Inputs: the merged event bus from output_analytics -----------------
    input  wire                    in_valid,        // 1 = a fresh output set is present
    input  wire [3:0]              event_id,        // current event (0=none, see 4)
    input  wire [TS_WIDTH-1:0]     event_timestamp, // when the event fired
    input  wire [STATUS_WIDTH-1:0] status,          // overall status (severity input)
    input  wire [HEALTH_WIDTH-1:0] crop_health,     // fused health score (rides in packet)

    // ---- Outputs: the sparse remote alert channel (ALL registered) ----------
    output reg                     msg_valid,       // 1-cycle strobe: transmitting a packet
    output reg  [PKT_WIDTH-1:0]    alert_packet,    // packed 64-bit alert (layout above)
    output reg  [CNT_WIDTH-1:0]    msg_count        // running tally of transmitted packets
);

    // ---- Event ids (must match docs/INTERFACES.md 4) ------------------------
    localparam EV_NONE          = 4'd0;
    localparam EV_PUMP_ON       = 4'd1;   // machine-handled -> no packet
    localparam EV_PUMP_OFF      = 4'd2;   // machine-handled -> no packet
    localparam EV_WEED          = 4'd3;   // human-needed
    localparam EV_NUTRIENT_LOW  = 4'd4;   // human-needed
    localparam EV_HEAT_STRESS   = 4'd5;   // (no caretaker action -> no packet)
    localparam EV_FROST_RISK    = 4'd6;   // human-needed
    localparam EV_SENSOR_ANOM   = 4'd7;   // human-needed
    localparam EV_STATUS_CRIT   = 4'd8;   // human-needed
    localparam EV_PREDICT_DRY   = 4'd9;   // human-needed (early warning)

    // ---- Action codes (must match docs/INTERFACES.md 6 action_code table) ---
    localparam AC_NONE          = 4'd0;   // no message
    localparam AC_INSPECT_WEED  = 4'd1;   // WEED_DETECTED  -> go remove the weed
    localparam AC_CHECK_SENSOR  = 4'd2;   // SENSOR_ANOMALY -> inspect/replace sensor
    localparam AC_MANUAL_FERT   = 4'd3;   // NUTRIENT_LOW   -> top up nutrients manually
    localparam AC_PROTECT_FROST = 4'd4;   // FROST_RISK     -> deploy cover/heater
    localparam AC_RELOCATE_REV  = 4'd5;   // STATUS_CRITICAL-> review/relocate site
    localparam AC_PRE_IRRIGATE  = 4'd6;   // PREDICT_DRY    -> check pump/water supply

    // ---- Severity codes (docs/INTERFACES.md 6) ------------------------------
    localparam SEV_INFO         = 4'd1;   // low-urgency notice
    localparam SEV_WARNING      = 4'd2;
    localparam SEV_CRITICAL     = 4'd3;

    localparam STAT_CRITICAL    = 2'd2;   // status value that forces CRITICAL severity

    // -------------------------------------------------------------------------
    // COMBINATIONAL DECODE: event_id -> {notify?, action_code, base severity}
    //   cand_* describe the packet we WOULD build for the current event this cycle.
    //   This is pure look-up logic (no registers) - it re-evaluates every cycle.
    // -------------------------------------------------------------------------
    reg        cand_notify;   // 1 = this event needs a human (Tier-2 packet)
    reg [3:0]  cand_action;   // recommended caretaker action for this event
    reg [3:0]  cand_base_sev; // event's inherent severity, before status escalation
    reg [3:0]  cand_sev;      // final severity (escalated to CRITICAL if status==2)

    always @(*) begin
        // Default: unknown / machine-handled event -> stay local, no packet.
        cand_notify   = 1'b0;
        cand_action   = AC_NONE;
        cand_base_sev = SEV_INFO;

        case (event_id)
            EV_WEED: begin
                cand_notify   = 1'b1;
                cand_action   = AC_INSPECT_WEED;
                cand_base_sev = SEV_CRITICAL;   // resource theft -> urgent
            end
            EV_SENSOR_ANOM: begin
                cand_notify   = 1'b1;
                cand_action   = AC_CHECK_SENSOR;
                cand_base_sev = SEV_CRITICAL;   // can't trust the node -> urgent
            end
            EV_NUTRIENT_LOW: begin
                cand_notify   = 1'b1;
                cand_action   = AC_MANUAL_FERT;
                cand_base_sev = SEV_WARNING;    // act soon, not emergency
            end
            EV_FROST_RISK: begin
                cand_notify   = 1'b1;
                cand_action   = AC_PROTECT_FROST;
                cand_base_sev = SEV_CRITICAL;   // crop can die overnight -> urgent
            end
            EV_STATUS_CRIT: begin
                cand_notify   = 1'b1;
                cand_action   = AC_RELOCATE_REV;
                cand_base_sev = SEV_CRITICAL;
            end
            EV_PREDICT_DRY: begin
                cand_notify   = 1'b1;
                cand_action   = AC_PRE_IRRIGATE;
                cand_base_sev = SEV_INFO;       // early heads-up, not yet a problem
            end
            // EV_NONE, EV_PUMP_ON, EV_PUMP_OFF, EV_HEAT_STRESS: notify stays 0.
            default: begin
                cand_notify   = 1'b0;
                cand_action   = AC_NONE;
                cand_base_sev = SEV_INFO;
            end
        endcase

        // Severity is derived from event_id AND status: a normally-mild event still
        // escalates to CRITICAL if the chip's overall status is CRITICAL.
        cand_sev = (status == STAT_CRITICAL) ? SEV_CRITICAL : cand_base_sev;
    end

    // -------------------------------------------------------------------------
    // EDGE + RATE-LIMIT STATE
    //   prev_event   : event_id seen on the previous VALID cycle - used to detect a
    //                  NEW event occurrence (event_id already pulses to NONE between
    //                  events upstream, so a change of value == a fresh occurrence).
    //   last_tx_event: the last event we actually transmitted - the rate-limit only
    //                  suppresses REPEATS of this same event.
    //   gap_counter  : down-counter of valid cycles; the SAME event may re-send only
    //                  once it reaches 0.  A DIFFERENT event bypasses it.
    // -------------------------------------------------------------------------
    reg [3:0]           prev_event;
    reg [3:0]           last_tx_event;
    reg [CNT_WIDTH-1:0] gap_counter;

    // fresh_event : a qualifying event that is a NEW occurrence this valid cycle.
    // send_ok     : fresh AND allowed past the rate limit (different event, or the
    //               same event but the gap has elapsed).
    reg fresh_event;
    reg send_ok;

    always @(posedge clk) begin
        if (rst) begin
            // Clean, silent reset: no packet, empty tally, counters clear.
            msg_valid     <= 1'b0;
            alert_packet  <= {PKT_WIDTH{1'b0}};
            msg_count     <= {CNT_WIDTH{1'b0}};
            prev_event    <= EV_NONE;
            last_tx_event <= EV_NONE;
            gap_counter   <= {CNT_WIDTH{1'b0}};
        end else begin
            // Default: no transmission this cycle (msg_valid is a 1-cycle strobe).
            msg_valid <= 1'b0;

            if (in_valid) begin
                // --- Is this a fresh, human-needed event occurrence? ----------
                fresh_event = cand_notify && (event_id != prev_event);

                // --- Rate limit: same event must wait MSG_GAP valid cycles ----
                send_ok = fresh_event &&
                          ((event_id != last_tx_event) || (gap_counter == 0));

                if (send_ok) begin
                    // TRANSMIT: build the 64-bit packet (MSB->LSB per 6) and count it.
                    alert_packet <= { cand_sev,            // [63:60] severity
                                      event_id,            // [59:56] event_code
                                      cand_action,         // [55:52] action_code
                                      crop_health,         // [51:44] crop_health
                                      12'd0,               // [43:32] reserved
                                      event_timestamp };   // [31: 0] event_timestamp
                    msg_valid     <= 1'b1;
                    msg_count     <= msg_count + 1'b1;
                    last_tx_event <= event_id;
                    gap_counter   <= MSG_GAP;   // reload the anti-spam window
                end else if (gap_counter != 0) begin
                    // Not sending: age the rate-limit window by one valid cycle.
                    gap_counter <= gap_counter - 1'b1;
                end

                // Remember this cycle's event for next cycle's edge detection.
                prev_event <= event_id;
            end
            // in_valid low: hold all state; msg_valid already forced low above.
        end
    end

endmodule
