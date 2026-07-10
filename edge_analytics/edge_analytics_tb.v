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
    localparam NS         = 223;  // number of samples in the richer story trace (~210)

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
    // ---- Phase-8 side outputs (TEDA anomaly + Tier-2 caretaker radio) --------
    wire [2:0]             out_anom_ch;        // per-channel TEDA flags (t=4, debug)
    wire                   out_msg_valid;      // caretaker packet strobe (+1 vs D row)
    wire [63:0]            out_alert_packet;   // 64-bit caretaker alert packet
    wire [15:0]            out_msg_count;      // running caretaker-packet tally

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
        .out_valid(out_valid),
        .out_anom_ch(out_anom_ch),
        .out_msg_valid(out_msg_valid), .out_alert_packet(out_alert_packet),
        .out_msg_count(out_msg_count)
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
    integer samples_processed;   // # of valid D-line output cycles (all analytics on-chip)
    integer caretaker_pkts;      // # of caretaker packets seen on the wire (msg_valid strobes)
    integer warmup_pkts;         // # of caretaker packets fired at ts=0 (warm-up transient) - should be 0
    integer pct_saved;           // % transmissions saved vs a naive stream-everything node

    // ---- Story-phase windows (ts ranges) for the FEATURE self-checks --------
    // The trace is built so each feature fires inside its window; the checks at
    // the end assert the narrative actually happened (weed in the weed phases,
    // NO weed in the slow dry-spell, weed SUPPRESSED under heat, fusion catches
    // the combined case, frost/nutrient/anomaly all fire).  Keep these in sync
    // with the stimulus phases below.
    localparam DRY1_LO  =  21, DRY1_HI  =  46;   // gentle dry-spell (pump, NOT weed)
    localparam WEED1_LO =  55, WEED1_HI =  66;   // weed incident #1
    localparam HEAT_LO  =  75, HEAT_HI  = 104;   // heat wave (weed SUPPRESSED)
    localparam FROST_LO = 113, FROST_HI = 134;   // cold snap / frost
    localparam NUT_LO   = 143, NUT_HI   = 164;   // nutrient depletion
    localparam COMB_LO  = 171, COMB_HI  = 192;   // combined-stress / joint fusion
    localparam ANOM_LO  = 197, ANOM_HI  = 208;   // sensor anomaly (TEDA catch)
    localparam WEED2_LO = 209, WEED2_HI = 218;   // weed incident #2

    // ---- Feature observation flags (set during the live-stream monitor) ------
    integer saw_weed1, saw_weed2;       // weed fired in each weed window
    integer weed_in_dry1, weed_in_heat; // weed WRONGLY fired in dry-spell / heat (must stay 0)
    integer saw_heat, saw_frost;        // heat / frost alerts fired in their windows
    integer saw_nut, saw_anom;          // nutrient / anomaly alerts fired
    integer saw_combined;               // status>0 with EVERY single alert clear (joint fusion)

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
    function [127:0] ev_name;   // up to 16 chars packed as a string
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
                4'd9: ev_name = "PREDICT_DRY";
                default: ev_name = "NONE";
            endcase
        end
    endfunction

    // ---- action_code -> name (docs/INTERFACES.md 6 action_code table) -------
    function [127:0] ac_name;   // up to 16 chars packed as a string
        input [3:0] code;
        begin
            case (code)
                4'd1: ac_name = "INSPECT_WEED";
                4'd2: ac_name = "CHECK_SENSOR";
                4'd3: ac_name = "MANUAL_FERT";
                4'd4: ac_name = "PROTECT_FROST";
                4'd5: ac_name = "RELOCATE_REV";
                4'd6: ac_name = "PRE_IRRIGATE";
                default: ac_name = "NONE";
            endcase
        end
    endfunction

    // ---- severity -> name (docs/INTERFACES.md 6) ----------------------------
    function [63:0] sev_name;   // up to 8 chars packed as a string
        input [3:0] sev;
        begin
            case (sev)
                4'd1: sev_name = "INFO";
                4'd2: sev_name = "WARNING";
                4'd3: sev_name = "CRITICAL";
                default: sev_name = "?";
            endcase
        end
    endfunction

    // ---- Deterministic small +/-5 jitter (makes the RAW dashboard columns wiggle
    //   like real sensors).  A fixed pattern keyed by index -> fully reproducible
    //   across regenerations (no RNG).  The reference avg8 model reads the SAME
    //   arrays, so jitter is accounted for automatically in the alignment checks.
    function integer jit;
        input integer i;
        begin
            case (i % 10)
                0: jit =  3;  1: jit = -4;  2: jit =  2;  3: jit = -1;  4: jit =  5;
                5: jit = -3;  6: jit =  1;  7: jit = -5;  8: jit =  4;  9: jit = -2;
                default: jit = 0;
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
            samples_processed = samples_processed + 1;  // one on-chip-processed sample

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

            // ---- FEATURE OBSERVATION (per story-phase window) ----------------
            // Record whether each feature fired inside its window so the end-of-run
            // self-checks can assert the narrative really happened (and that weed
            // did NOT fire where it must not).
            if (ts_i >= WEED1_LO && ts_i <= WEED1_HI && out_alert_weed)     saw_weed1     = 1;
            if (ts_i >= WEED2_LO && ts_i <= WEED2_HI && out_alert_weed)     saw_weed2     = 1;
            if (ts_i >= DRY1_LO  && ts_i <= DRY1_HI  && out_alert_weed)     weed_in_dry1  = 1;
            if (ts_i >= HEAT_LO  && ts_i <= HEAT_HI  && out_alert_weed)     weed_in_heat  = 1;
            if (ts_i >= HEAT_LO  && ts_i <= HEAT_HI  && out_alert_heat)     saw_heat      = 1;
            if (ts_i >= FROST_LO && ts_i <= FROST_HI && out_alert_frost)    saw_frost     = 1;
            if (ts_i >= NUT_LO   && ts_i <= NUT_HI   && out_alert_nutrient) saw_nut       = 1;
            if (ts_i >= ANOM_LO  && ts_i <= ANOM_HI  && out_alert_anomaly)  saw_anom      = 1;
            // combined / joint fusion: WARNING-or-worse while EVERY single-channel
            // alert stays clear (the OR-of-thresholds detector would miss this).
            if (ts_i >= COMB_LO && ts_i <= COMB_HI && out_status > 0 &&
                !out_alert_nutrient && !out_alert_weed && !out_alert_heat &&
                !out_alert_frost && !out_alert_anomaly)                     saw_combined  = 1;

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
    // CARETAKER-RADIO MONITOR (Tier-2, Phase 8A comms_tx)
    //   comms_tx's msg_valid is +1 vs the aligned D row (async radio), so this is
    //   its OWN negedge monitor - it does NOT gate on out_valid.  Every strobe is
    //   decoded from the 64-bit packet (fields per docs/INTERFACES.md 6) and
    //   printed on a '#'-prefixed line so the dashboard's parser skips it and the
    //   17-field CSV contract stays clean.
    // =========================================================================
    reg [3:0]  pk_sev, pk_ev, pk_ac;   // severity / event_code / action_code
    reg [7:0]  pk_health;              // crop_health carried in the packet
    reg [11:0] pk_resv;                // reserved (must be 0 for now)
    reg [31:0] pk_ts;                  // event_timestamp

    always @(negedge clk) begin
        if (!rst && out_msg_valid) begin
            // Unpack the 64-bit alert packet, MSB->LSB (docs/INTERFACES.md 6).
            pk_sev    = out_alert_packet[63:60];
            pk_ev     = out_alert_packet[59:56];
            pk_ac     = out_alert_packet[55:52];
            pk_health = out_alert_packet[51:44];
            pk_resv   = out_alert_packet[43:32];
            pk_ts     = out_alert_packet[31:0];

            caretaker_pkts = caretaker_pkts + 1;
            // A packet stamped ts=0 would be the warm-up FROST transient (the false
            // alarm the warm-up gate is meant to kill).  Tally it for self-check (b).
            if (pk_ts == 0) warmup_pkts = warmup_pkts + 1;

            // ---- Human-readable monitor line (dashboard parser skips '#' lines) ---
            $display("# CARETAKER TX #%0d: sev=%0s event=%0s action=%0s health=%0d ts=%0d (packet=%016h)",
                     out_msg_count,
                     sev_name(pk_sev), ev_name(pk_ev), ac_name(pk_ac),
                     pk_health, pk_ts, out_alert_packet);
            // ---- Machine-readable caretaker line (Phase 8D) - the dashboard's
            //   "Caretaker's Phone" feed:  C,<ts>,<severity>,<event>,<action>,<health>,<msg_count>
            $display("C,%0d,%0s,%0s,%0s,%0d,%0d",
                     pk_ts, sev_name(pk_sev), ev_name(pk_ev), ac_name(pk_ac),
                     pk_health, out_msg_count);
            $fflush;

            // Reserved field sanity: must be zero in v1.
            if (pk_resv !== 12'd0) begin
                errors = errors + 1;
                $display("#  ** FAIL packet reserved field != 0 (got %0h)", pk_resv);
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
        samples_processed = 0;
        caretaker_pkts    = 0;
        warmup_pkts       = 0;
        saw_weed1 = 0; saw_weed2 = 0; weed_in_dry1 = 0; weed_in_heat = 0;
        saw_heat  = 0; saw_frost = 0; saw_nut = 0; saw_anom = 0; saw_combined = 0;

        // ---- Print the 17-field dashboard CSV header ONCE ----------------
        // Field order here is the single source of truth; the per-cycle row in
        // the negedge block prints these same fields in this exact order.
        $display("timestamp,moisture_raw,nutrient_raw,temp_raw,moisture_avg,nutrient_avg,temp_avg,pump_on,dose_nutrient,alert_nutrient,alert_weed,alert_heat,alert_frost,alert_anomaly,status,crop_health,relocate_recommend");
        $fflush;

        // ---- Build the RICHER multi-incident story trace (index = timestamp) ---
        // Every feature is exercised, spread out so the dashboard stays lively for
        // ~210 samples.  Steady segments carry a small +/-5 jit(k) so the RAW
        // columns wiggle; ramps/spikes use exact values so the trigger math is easy
        // to reason about.  The moving-average window (8) starts at 0, so the first
        // ~10 samples are FILTER WARM-UP (averages ramp up; the Tier-2 radio is
        // gated silent there by the top-level warm-up gate).
        //
        // NARRATIVE (phase -> ts):
        //   A warm-up + healthy .......... 0..20    (settle filters, SAFE baseline)
        //   B dry spell -> PUMP -> recover  21..46   (hysteresis; gentle, NOT a weed)
        //   C healthy ..................... 47..54
        //   D WEED #1 (sharp drop) ........ 55..66   (temp normal -> weed fires)
        //   E healthy ..................... 67..74
        //   F HEAT wave + fast drop ....... 75..104  (weed SUPPRESSED = evaporation)
        //   G healthy ..................... 105..112
        //   H COLD snap / FROST ........... 113..134 (avg_temp < 100 -> FROST_RISK)
        //   I healthy ..................... 135..142
        //   J NUTRIENT low ................ 143..164 (avg_nutrient < 250 -> dose+alert)
        //   K healthy ..................... 165..170
        //   L COMBINED stress / fusion .... 171..192 (marginal dry + marginal hot)
        //   M healthy ..................... 193..196
        //   N SENSOR anomaly (TEDA) ....... 197..208 (nutrient rail HIGH, engine misses)
        //   O WEED #2 (deeper drop) ....... 209..218
        //   P healthy tail ................ 219..222
        //
        // TEDA NOTE: the self-tuning anomaly block has near-zero learned variance on
        // a channel that has been quiet, so its FIRST abrupt excursion reads as an
        // outlier.  To keep the Tier-2 radio sparse and on-message, every transition
        // that should NOT be a "sensor anomaly" is made GENTLE (<= ~12 counts/sample,
        // like the dry-spell) so the running mean tracks it; only the WEED crashes,
        // the heat-driven fast drop, and the intended nutrient RAIL are abrupt.

        // Default: everything healthy & wet (avg settles moisture 400>350 pump-off,
        // nutrient 300>250, temp 250 in-band).  Phases below overwrite their spans.
        for (k = 0; k < NS; k = k + 1) begin
            rm[k] = 400 + jit(k);
            rn[k] = 300 + jit(k+3);
            rt[k] = 250 + jit(k+7);
        end

        // --- B: gentle dry-spell (~14/sample: crosses DRY=200 without looking like
        //        a weed), then GENTLE irrigation recovery (avg passes PUMP_OFF=350
        //        -> pump OFF) that does NOT overshoot-and-fall (which would trip weed).
        rm[21]=386; rm[22]=372; rm[23]=358; rm[24]=344; rm[25]=330; rm[26]=316;
        rm[27]=302; rm[28]=288; rm[29]=274; rm[30]=260; rm[31]=246; rm[32]=232;
        rm[33]=218; rm[34]=204; rm[35]=190; rm[36]=176; rm[37]=162; rm[38]=148; rm[39]=134;
        rm[40]=300; rm[41]=420; rm[42]=460; rm[43]=445; rm[44]=430; rm[45]=415; rm[46]=402;

        // --- D: WEED #1.  Sharp 4-sample moisture crash (avg falls > RATE=100 over
        //        HIST=4), temp normal -> weed fires; gentle recovery keeps avg > DRY
        //        so the weed is NOT masked as a pump event.
        rm[59]=150; rm[60]=150; rm[61]=150; rm[62]=150;
        rm[63]=250; rm[64]=360; rm[65]=400; rm[66]=400;

        // --- F: HEAT wave.  Temp climbs GENTLY into HOT (>400) FIRST (so the temp
        //        channel is not itself flagged as an anomaly), THEN moisture drops
        //        FAST while already hot -> the depletion is evaporation, so the weed
        //        flag is SUPPRESSED (temp-compensation) while alert_heat fires.
        rt[75]=262; rt[76]=274; rt[77]=286; rt[78]=298; rt[79]=310; rt[80]=322;
        rt[81]=334; rt[82]=346; rt[83]=358; rt[84]=370; rt[85]=382; rt[86]=394;
        rt[87]=406; rt[88]=418; rt[89]=430; rt[90]=442; rt[91]=454; rt[92]=460;
        rt[93]=460; rt[94]=460; rt[95]=460; rt[96]=460; rt[97]=460; rt[98]=460;
        rt[99]=460; rt[100]=460; rt[101]=400; rt[102]=340; rt[103]=290; rt[104]=250;
        rm[93]=340; rm[94]=290; rm[95]=250; rm[96]=230; rm[97]=225; rm[98]=225;
        rm[99]=228; rm[100]=230; rm[101]=300; rm[102]=360; rm[103]=400; rm[104]=400;

        // --- H: COLD snap.  Temp glides below COLD=100 -> cold -> FROST_RISK packet,
        //        then warms back up.  Gentle descent so TEDA tracks it (no anomaly).
        rt[113]=238; rt[114]=226; rt[115]=214; rt[116]=202; rt[117]=190; rt[118]=178;
        rt[119]=166; rt[120]=154; rt[121]=142; rt[122]=130; rt[123]=118; rt[124]=106;
        rt[125]=94;  rt[126]=82;  rt[127]=70;  rt[128]=60;  rt[129]=60;  rt[130]=60;
        rt[131]=60;  rt[132]=120; rt[133]=190; rt[134]=250;

        // --- J: NUTRIENT depletion.  avg_nutrient glides below NUT=250 -> dose_nutrient
        //        (Tier-1) AND a NUTRIENT_LOW caretaker page (Tier-2).  Gentle so the
        //        TEDA nutrient channel tracks the drop rather than flagging it.
        rn[143]=292; rn[144]=284; rn[145]=276; rn[146]=268; rn[147]=260; rn[148]=252;
        rn[149]=244; rn[150]=236; rn[151]=228; rn[152]=220; rn[153]=212; rn[154]=204;
        rn[155]=196; rn[156]=188; rn[157]=185; rn[158]=185; rn[159]=185; rn[160]=185;
        rn[161]=230; rn[162]=270; rn[163]=300; rn[164]=300;

        // --- L: COMBINED stress / JOINT fusion.  Moisture eased GENTLY into the
        //        "getting dry" band [DRY=200, DRY_WARN=260); temp eased GENTLY into the
        //        "getting warm" band (HOT_WARN=360, HOT=400].  EACH channel alone stays
        //        under its hard threshold (so every single-channel alert is clear), yet
        //        the JOINT view raises WARNING - the case OR-of-thresholds misses.
        rm[171]=390; rm[172]=378; rm[173]=366; rm[174]=354; rm[175]=342; rm[176]=330;
        rm[177]=318; rm[178]=306; rm[179]=294; rm[180]=282; rm[181]=270; rm[182]=258;
        rm[183]=248; rm[184]=245; rm[185]=245; rm[186]=245; rm[187]=245; rm[188]=245;
        rm[189]=245; rm[190]=245; rm[191]=245; rm[192]=245;
        rt[174]=262; rt[175]=274; rt[176]=286; rt[177]=298; rt[178]=310; rt[179]=322;
        rt[180]=334; rt[181]=346; rt[182]=358; rt[183]=370; rt[184]=382; rt[185]=386;
        rt[186]=385; rt[187]=385; rt[188]=385; rt[189]=386; rt[190]=385; rt[191]=385; rt[192]=385;

        // --- M: recover moisture + temp back to healthy (gentle).
        rm[193]=300; rm[194]=360; rm[195]=400; rm[196]=400;
        rt[193]=300; rt[194]=270; rt[195]=250; rt[196]=250;

        // --- N: SENSOR anomaly.  The NPK sensor fails stuck-HIGH (railed at 4095).
        //        The engine's fixed rail check watches MOISTURE only, so it MISSES
        //        this; the TEDA block (adaptive_anomaly) flags the nutrient channel,
        //        and the top INJECTS a SENSOR_ANOMALY -> CHECK_SENSOR caretaker page.
        rn[197]=4095; rn[198]=4095; rn[199]=4095; rn[200]=4095; rn[201]=4095; rn[202]=4095;
        rn[203]=300;  rn[204]=300;  rn[205]=300;  rn[206]=300;  rn[207]=300;  rn[208]=300;

        // --- O: WEED #2.  A second, deeper moisture crash at a different time; temp
        //        normal -> weed fires again (proves the detector repeats).
        rm[212]=120; rm[213]=120; rm[214]=120; rm[215]=120;
        rm[216]=250; rm[217]=380; rm[218]=400;

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

        // ---- EDGE-WIN METRIC (Phase 8D) ----------------------------------
        // A NAIVE node streams EVERY sample to the cloud/caretaker; OUR chip does
        // all analytics on-chip and transmits only the sparse caretaker packets.
        //   dumb_node_transmissions = samples_processed   (one per valid sample)
        //   our_transmissions       = out_msg_count       (only the alerts)
        //   pct_saved = (dumb - our)/dumb * 100   (integer floor; honest round-DOWN).
        //   NB: do NOT write `100 - (100*our)/dumb` - integer division floors the small
        //   term (600/223 -> 2) and inflates the saving to 98%; the correct value is 97%.
        if (samples_processed > 0)
            pct_saved = (100 * (samples_processed - out_msg_count)) / samples_processed;
        else
            pct_saved = 0;

        // ---- Verdict -----------------------------------------------------
        // Four integration self-checks (all '#'-prefixed so the CSV stays clean):
        //   (a) the D-line is still a valid 17-field aligned row (0 align errors)
        //   (b) NO caretaker packet fired at ts=0 (the warm-up gate works)
        //   (c) at least 2 real caretaker packets transmitted
        //   (d) our msg_count is MUCH smaller than the sample count (the sparseness
        //       we pitch: transmit K alerts, not N raw samples)
        $display("#---------------------------------------------------------");
        $display("# INTEGRATION SUMMARY (Tier-1 D-line + Tier-2 caretaker radio)");
        $display("#   samples processed on-chip : %0d", samples_processed);
        $display("#   caretaker packets TX'd    : %0d (msg_count reg = %0d)",
                 caretaker_pkts, out_msg_count);
        $display("#   EDGE-WIN: dumb node = %0d transmissions, our chip = %0d -> %0d%% saved",
                 samples_processed, out_msg_count, pct_saved);
        // ---- Machine-readable edge-win summary (Phase 8D) ----------------
        //   M,<samples_processed>,<our_msg_count>,<pct_saved>
        $display("M,%0d,%0d,%0d", samples_processed, out_msg_count, pct_saved);
        $fflush;

        // consistency: the counted strobes must match the module's msg_count reg
        if (out_msg_count !== caretaker_pkts) begin
            errors = errors + 1;
            $display("#  ** FAIL msg_count reg (%0d) != strobes counted (%0d)",
                     out_msg_count, caretaker_pkts);
        end
        // (b) warm-up gate: no caretaker packet may fire at ts=0 (the false FROST)
        if (warmup_pkts != 0) begin
            errors = errors + 1;
            $display("#  ** FAIL warm-up gate leaked %0d packet(s) at ts=0.", warmup_pkts);
        end else begin
            $display("#   warm-up OK: 0 caretaker packets at ts=0 (false FROST suppressed)");
        end
        // (c) at least TWO real caretaker packets transmitted
        if (caretaker_pkts < 2) begin
            errors = errors + 1;
            $display("#  ** FAIL fewer than 2 real caretaker packets (got %0d).", caretaker_pkts);
        end
        // (d) sparseness: caretaker packets must be far fewer than samples (< 1/4).
        if (!(caretaker_pkts * 4 < samples_processed)) begin
            errors = errors + 1;
            $display("#  ** FAIL caretaker channel not sparse (packets %0d vs samples %0d)",
                     caretaker_pkts, samples_processed);
        end else begin
            $display("#   sparseness OK: %0d packets << %0d samples (Tier-2 radio is sparse)",
                     caretaker_pkts, samples_processed);
        end

        // ---- FEATURE SELF-CHECKS: the narrative actually happened --------------
        // Each asserts a feature fired (or correctly did NOT fire) inside its story
        // window.  These make the 210-sample trace self-verifying: if a future edit
        // shifts a phase, the matching check fails loudly instead of silently.
        $display("# FEATURE CHECKS (per story-phase window):");
        if (!saw_weed1) begin errors = errors + 1;
            $display("#  ** FAIL weed #1 did not fire in ts %0d..%0d", WEED1_LO, WEED1_HI);
        end else $display("#   OK weed #1 fired (ts %0d..%0d)", WEED1_LO, WEED1_HI);
        if (!saw_weed2) begin errors = errors + 1;
            $display("#  ** FAIL weed #2 did not fire in ts %0d..%0d", WEED2_LO, WEED2_HI);
        end else $display("#   OK weed #2 fired (ts %0d..%0d)", WEED2_LO, WEED2_HI);
        if (weed_in_dry1) begin errors = errors + 1;
            $display("#  ** FAIL weed WRONGLY fired during the slow dry-spell (ts %0d..%0d)", DRY1_LO, DRY1_HI);
        end else $display("#   OK slow dry-spell did NOT trip weed (ts %0d..%0d)", DRY1_LO, DRY1_HI);
        if (weed_in_heat) begin errors = errors + 1;
            $display("#  ** FAIL weed WRONGLY fired during heat (should be SUPPRESSED, ts %0d..%0d)", HEAT_LO, HEAT_HI);
        end else $display("#   OK weed SUPPRESSED under heat = evaporation (ts %0d..%0d)", HEAT_LO, HEAT_HI);
        if (!saw_heat) begin errors = errors + 1;
            $display("#  ** FAIL heat alert did not fire in ts %0d..%0d", HEAT_LO, HEAT_HI);
        end else $display("#   OK heat alert fired (ts %0d..%0d)", HEAT_LO, HEAT_HI);
        if (!saw_frost) begin errors = errors + 1;
            $display("#  ** FAIL frost alert did not fire in ts %0d..%0d", FROST_LO, FROST_HI);
        end else $display("#   OK frost alert fired (ts %0d..%0d)", FROST_LO, FROST_HI);
        if (!saw_nut) begin errors = errors + 1;
            $display("#  ** FAIL nutrient alert did not fire in ts %0d..%0d", NUT_LO, NUT_HI);
        end else $display("#   OK nutrient alert fired (ts %0d..%0d)", NUT_LO, NUT_HI);
        if (!saw_combined) begin errors = errors + 1;
            $display("#  ** FAIL combined-stress (status>0, all single alerts clear) not seen in ts %0d..%0d", COMB_LO, COMB_HI);
        end else $display("#   OK combined-stress caught by joint fusion (ts %0d..%0d)", COMB_LO, COMB_HI);
        if (!saw_anom) begin errors = errors + 1;
            $display("#  ** FAIL sensor anomaly did not fire in ts %0d..%0d", ANOM_LO, ANOM_HI);
        end else $display("#   OK TEDA sensor anomaly fired (ts %0d..%0d)", ANOM_LO, ANOM_HI);
        $display("#---------------------------------------------------------");
        if (errors == 0)
            $display("# RESULT: PASS - D-line aligned (17 fields), warm-up gate silent at ts=0, caretaker radio TX'd %0d sparse packet(s) (%0d%% saved), 0 errors.",
                     caretaker_pkts, pct_saved);
        else
            $display("# RESULT: FAIL - %0d error(s).", errors);
        $display("#---------------------------------------------------------");
        $finish;
    end

endmodule
