// analytics_engine_tb.v
// -----------------------------------------------------------------------------
// Testbench for analytics_engine.v  (Phase 3 of the Edge Analytics IP)
//
// WHAT IT PROVES (the story arc from BUILD_PLAN Phase 3):
//   1) HEALTHY     - steady, safe readings -> no conditions, status SAFE, health 255.
//   2) SLOW DRY-SPELL - moisture drifts down gently -> `dry` fires once it crosses
//      the threshold, BUT the drop is too gentle to be a weed.
//         >>> KEY SELF-CHECK: a slow dry-spell must NOT false-trigger `weed`. <<<
//   3) WEED        - moisture drops SHARPLY while temperature is NORMAL -> `weed`
//      fires and a WEED_DETECTED(3) event is stamped with the right timestamp.
//   4) HEAT        - temperature climbs past HOT_THRESH -> `hot` fires and a
//      HEAT_STRESS(5) event is stamped.  We ALSO drop moisture sharply here to
//      prove the TEMPERATURE COMPENSATION: because it is hot, the fast drop reads
//      as evaporation, so `weed` stays LOW (fusion, not a false weed alarm).
//   5) JOINT/FUSION (Phase 8C) - moisture sits at 240 (ABOVE DRY_THRESH=200, so
//      `dry`=0) AND temperature sits at 380 (BELOW HOT_THRESH=400, so `hot`=0),
//      nutrient healthy.  EVERY single-channel threshold reads "fine" - an
//      OR-of-thresholds engine would call this SAFE with full health 255.  But
//      the two channels are BOTH in their warning bands at once, so the joint
//      detector fires `combined_dry_heat` -> status leaves SAFE and crop_health
//      is penalised.
//         >>> KEY SELF-CHECK: a combination each channel-alone misses IS flagged
//             (status != SAFE) while every base condition stays 0. <<<
//
// HOW IT'S WIRED:
//   We drive the SMOOTHED values directly into analytics_engine (no need to chain
//   the whole pipeline for this unit test).  A free-running `tstamp` counter tags
//   every sample; because outputs are registered, we keep 1-cycle-delayed copies
//   of the inputs so, on each `out_valid`, we can line the decision up with the
//   sample (and its timestamp) that produced it.
//
//   Sample phases are classified by the delayed timestamp `ts_d`, so the self-
//   checks are robust to pipeline latency.
//
// Pure SOFTWARE simulation - iverilog runs it as a program; no hardware.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module analytics_engine_tb;

    // ---- Match the DUT parameters -------------------------------------------
    localparam DATA_WIDTH   = 12;
    localparam TS_WIDTH     = 32;
    localparam STATUS_WIDTH = 2;
    localparam HEALTH_WIDTH = 8;
    localparam DRY_THRESH   = 200;
    localparam NUT_THRESH   = 250;
    localparam HOT_THRESH   = 400;
    localparam COLD_THRESH  = 100;
    localparam HIST_DEPTH   = 4;
    localparam RATE_THRESH  = 100;
    // Phase 8C joint-fusion params (must match the DUT defaults).
    localparam DRY_WARN     = 260;  // moisture in [200,260) = "getting dry" (not dry)
    localparam HOT_WARN     = 360;  // temp in (360,400] = "getting warm" (not hot)

    localparam NUM_SAMPLES  = 50;   // total smoothed sets we feed (42 story + 8 joint)

    // ---- DUT stimulus / observation signals ---------------------------------
    reg                     clk = 0;
    reg                     rst;
    reg  [DATA_WIDTH-1:0]   avg_moisture;
    reg  [DATA_WIDTH-1:0]   avg_nutrient;
    reg  [DATA_WIDTH-1:0]   avg_temp;
    reg  [TS_WIDTH-1:0]     timestamp;
    reg                     in_valid;

    wire                    dry, low_nutrient, hot, cold, weed, anomaly;
    wire [STATUS_WIDTH-1:0] status;
    wire [HEALTH_WIDTH-1:0] crop_health;
    wire [3:0]              event_id;
    wire [TS_WIDTH-1:0]     event_timestamp;
    wire                    out_valid;

    // ---- DUT ----------------------------------------------------------------
    analytics_engine #(
        .DATA_WIDTH(DATA_WIDTH), .TS_WIDTH(TS_WIDTH),
        .STATUS_WIDTH(STATUS_WIDTH), .HEALTH_WIDTH(HEALTH_WIDTH),
        .DRY_THRESH(DRY_THRESH), .NUT_THRESH(NUT_THRESH),
        .HOT_THRESH(HOT_THRESH), .COLD_THRESH(COLD_THRESH),
        .HIST_DEPTH(HIST_DEPTH), .RATE_THRESH(RATE_THRESH)
    ) dut (
        .clk(clk), .rst(rst),
        .avg_moisture(avg_moisture), .avg_nutrient(avg_nutrient),
        .avg_temp(avg_temp), .timestamp(timestamp), .in_valid(in_valid),
        .dry(dry), .low_nutrient(low_nutrient), .hot(hot), .cold(cold),
        .weed(weed), .anomaly(anomaly), .status(status), .crop_health(crop_health),
        .event_id(event_id), .event_timestamp(event_timestamp), .out_valid(out_valid)
    );

    // ---- Clock: 100 MHz -> toggle every 5 ns --------------------------------
    always #5 clk = ~clk;

    // ---- Story-arc stimulus arrays ------------------------------------------
    //   Each sample carries a timestamp = 100*(k+1) so ts values are distinct and
    //   easy to read (100,200,...).  Phase boundaries by timestamp:
    //     HEALTHY    k 0..7   ts  100.. 800
    //     DRY-SPELL  k 8..19  ts  900..2000   (gentle down-slope, ~12/sample)
    //     RECOVERY   k 20..23 ts 2100..2400   (watered back to 320)
    //     WEED       k 24..29 ts 2500..3000   (sharp drop, temp normal)
    //     RECOVERY   k 30..33 ts 3100..3400   (watered back to 320)
    //     HEAT       k 34..41 ts 3500..4200   (temp > 400; moisture also drops)
    //     JOINT      k 42..49 ts 4300..5000   (Phase 8C: moisture 240 + temp 380;
    //                                          each fine alone, combination flagged)
    reg [DATA_WIDTH-1:0] m_stim [0:NUM_SAMPLES-1];
    reg [DATA_WIDTH-1:0] n_stim [0:NUM_SAMPLES-1];
    reg [DATA_WIDTH-1:0] t_stim [0:NUM_SAMPLES-1];
    integer k;

    // Phase-classification boundaries (by timestamp value).
    localparam DRY_LO  = 900,  DRY_HI  = 2000;
    localparam WEED_LO = 2500, WEED_HI = 3000;
    localparam HEAT_LO = 3500, HEAT_HI = 4200;
    localparam JOINT_LO = 4300, JOINT_HI = 5000;   // Phase 8C joint-fusion phase

    // ---- 1-cycle-delayed copies of the inputs (to align with reg'd outputs) --
    reg [DATA_WIDTH-1:0] avg_m_d, avg_n_d, avg_t_d;
    reg [TS_WIDTH-1:0]   ts_d;
    reg                  in_valid_d;

    // ---- Self-check bookkeeping ---------------------------------------------
    integer errors = 0;
    // Dry-spell observations
    integer saw_dry_in_dryspell   = 0;
    integer saw_weed_in_dryspell  = 0;   // MUST stay 0 (the false-trigger guard)
    // Weed-phase observations
    integer saw_weed_in_weed      = 0;
    integer saw_weedevt_in_weed   = 0;
    // Heat-phase observations
    integer saw_hot_in_heat       = 0;
    integer saw_heatevt_in_heat   = 0;
    integer saw_weed_in_heat      = 0;   // MUST stay 0 (temperature compensation)
    // Healthy-phase observations
    integer saw_bad_in_healthy    = 0;   // MUST stay 0
    // Joint/fusion-phase observations (Phase 8C)
    integer saw_joint_flag        = 0;   // status left SAFE on the combination
    integer saw_joint_single      = 0;   // any base condition fired (MUST stay 0)
    integer saw_joint_healthpen   = 0;   // crop_health penalised below 255
    integer joint_samples_seen    = 0;   // how many joint-phase samples we observed

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, analytics_engine_tb);

        // ---- Compose the story-arc stimulus ---------------------------------
        // Nutrient held healthy (300 > NUT_THRESH) the whole time so it never
        // confounds the moisture/temperature story.
        for (k = 0; k < NUM_SAMPLES; k = k + 1) n_stim[k] = 300;

        // Default temperature = 350 (normal: 100 < 350 < 400) unless overridden.
        for (k = 0; k < NUM_SAMPLES; k = k + 1) t_stim[k] = 350;

        // HEALTHY  k 0..7 : steady, safe moisture ~300.
        for (k = 0; k <= 7; k = k + 1) m_stim[k] = 300;

        // SLOW DRY-SPELL k 8..19 : moisture drifts down 12/sample from 300.
        // Drop over HIST_DEPTH(4) samples = 48 < RATE_THRESH(100) -> NOT a weed.
        for (k = 8; k <= 19; k = k + 1) m_stim[k] = 300 - (k - 7) * 12; // 288..156

        // RECOVERY k 20..23 : watered back up to 320 (refills history).
        for (k = 20; k <= 23; k = k + 1) m_stim[k] = 320;

        // WEED k 24..29 : sharp moisture drop, temperature NORMAL (350).
        m_stim[24] = 260; m_stim[25] = 200; m_stim[26] = 140;
        m_stim[27] = 110; m_stim[28] = 120; m_stim[29] = 130;

        // RECOVERY k 30..33 : watered back up to 320 (refills history).
        for (k = 30; k <= 33; k = k + 1) m_stim[k] = 320;

        // HEAT k 34..41 : temperature climbs past HOT_THRESH, AND moisture drops
        // sharply.  Because it is hot, the fast drop must NOT read as a weed.
        m_stim[34] = 260; m_stim[35] = 200; m_stim[36] = 140; m_stim[37] = 110;
        m_stim[38] = 120; m_stim[39] = 130; m_stim[40] = 140; m_stim[41] = 150;
        t_stim[34] = 380;                         // still normal (warming)
        t_stim[35] = 410; t_stim[36] = 420; t_stim[37] = 430;
        t_stim[38] = 440; t_stim[39] = 440; t_stim[40] = 440; t_stim[41] = 440;

        // JOINT / FUSION k 42..49 (Phase 8C): hold moisture at 240 and temp at
        // 380.  moisture 240 is ABOVE DRY_THRESH(200) so `dry`=0, yet inside the
        // "getting dry" band [200,260); temp 380 is BELOW HOT_THRESH(400) so
        // `hot`=0, yet inside the "getting warm" band (360,400].  Held steady so
        // there is no depletion trend (no weed / no moisture-falling) - the ONLY
        // thing wrong is the CORRELATION of two marginal channels.  An
        // OR-of-thresholds engine sees SAFE + health 255; the joint detector flags it.
        for (k = 42; k <= 49; k = k + 1) begin
            m_stim[k] = 240;   // > DRY_THRESH(200), < DRY_WARN(260)  -> dry=0, dry_warn=1
            t_stim[k] = 380;   // <= HOT_THRESH(400), > HOT_WARN(360) -> hot=0, hot_warn=1
        end                    // n_stim already 300 (healthy) for all k

        // ---- Init state -----------------------------------------------------
        in_valid_d = 0;
        rst = 1; in_valid = 0; avg_moisture = 0; avg_nutrient = 0; avg_temp = 0;
        timestamp = 0;
        @(posedge clk); @(posedge clk);
        rst = 0;

        $display("=====================================================================");
        $display(" analytics_engine: driving the story arc");
        $display("   HEALTHY -> slow DRY-SPELL -> WEED (sharp, normal temp) -> HEAT");
        $display("   -> JOINT/FUSION (Phase 8C: marginal moisture + marginal temp)");
        $display(" (weed = temp-compensated depletion rate; a slow dry-spell must NOT");
        $display("  read as a weed, and a hot fast-drop must NOT read as a weed; the");
        $display("  JOINT phase proves a combination each channel-alone misses is caught)");
        $display("=====================================================================");
        $display(" ts   | avgM avgN avgT | dry ln hot cld weed anom | st health | event");
        $display("---------------------------------------------------------------------");

        // ---- Feed the smoothed sets, one per clock --------------------------
        for (k = 0; k < NUM_SAMPLES; k = k + 1) begin
            @(posedge clk);
            avg_moisture <= m_stim[k];
            avg_nutrient <= n_stim[k];
            avg_temp     <= t_stim[k];
            timestamp    <= 100 * (k + 1);
            in_valid     <= 1;
        end

        // Stop feeding and flush the last registered result out.
        @(posedge clk); in_valid <= 0;
        @(posedge clk); @(posedge clk);

        // ---- Final report ---------------------------------------------------
        $display("---------------------------------------------------------------------");
        $display(" SELF-CHECKS:");

        // Healthy: nothing bad should have fired.
        if (saw_bad_in_healthy != 0) begin
            $display("   [FAIL] a condition fired during the HEALTHY phase.");
            errors = errors + 1;
        end else
            $display("   [PASS] HEALTHY phase clean (no conditions, status SAFE).");

        // Dry-spell: dry must fire, weed must NOT.
        if (saw_dry_in_dryspell == 0) begin
            $display("   [FAIL] `dry` never fired during the slow dry-spell.");
            errors = errors + 1;
        end else
            $display("   [PASS] `dry` fired during the slow dry-spell.");

        if (saw_weed_in_dryspell != 0) begin
            $display("   [FAIL] slow dry-spell FALSE-TRIGGERED `weed`.");
            errors = errors + 1;
        end else
            $display("   [PASS] slow dry-spell did NOT false-trigger `weed`.  <== key check");

        // Weed phase: weed + WEED_DETECTED event must fire.
        if (saw_weed_in_weed == 0) begin
            $display("   [FAIL] `weed` never fired on the sharp normal-temp drop.");
            errors = errors + 1;
        end else
            $display("   [PASS] `weed` fired on the sharp drop with normal temperature.");

        if (saw_weedevt_in_weed == 0) begin
            $display("   [FAIL] no WEED_DETECTED(3) event was stamped in the weed phase.");
            errors = errors + 1;
        end else
            $display("   [PASS] WEED_DETECTED(3) event stamped with a timestamp.");

        // Heat phase: hot + HEAT_STRESS event must fire, weed must NOT.
        if (saw_hot_in_heat == 0) begin
            $display("   [FAIL] `hot` never fired when temperature exceeded HOT_THRESH.");
            errors = errors + 1;
        end else
            $display("   [PASS] `hot` fired when temperature crossed HOT_THRESH.");

        if (saw_heatevt_in_heat == 0) begin
            $display("   [FAIL] no HEAT_STRESS(5) event was stamped in the heat phase.");
            errors = errors + 1;
        end else
            $display("   [PASS] HEAT_STRESS(5) event stamped with a timestamp.");

        if (saw_weed_in_heat != 0) begin
            $display("   [FAIL] a HOT fast moisture drop FALSE-TRIGGERED `weed`.");
            errors = errors + 1;
        end else
            $display("   [PASS] hot fast-drop did NOT read as `weed`.  <== temp compensation");

        // ---- Phase 8C JOINT / CORRELATED FUSION checks ----------------------
        $display("   - - - Phase 8C: joint / correlated fusion - - -");

        // Sanity: we actually observed the joint phase.
        if (joint_samples_seen == 0) begin
            $display("   [FAIL] joint/fusion phase produced no observed samples.");
            errors = errors + 1;
        end

        // The genuine-fusion proof: every base condition stayed 0 (each channel
        // individually "fine") yet the combination was flagged.
        if (saw_joint_single != 0) begin
            $display("   [FAIL] a single-channel threshold fired in the joint phase");
            $display("          (the case is supposed to be sub-threshold on every channel).");
            errors = errors + 1;
        end else
            $display("   [PASS] no single-channel threshold fired - each channel looks 'fine'.");

        if (saw_joint_flag == 0) begin
            $display("   [FAIL] the joint combination was NOT flagged (status stayed SAFE)");
            $display("          - fusion failed to catch what OR-of-thresholds would miss.");
            errors = errors + 1;
        end else
            $display("   [PASS] combination FLAGGED (status left SAFE) though every channel");
            $display("          alone is fine.  <== genuine fusion; independent thresholds miss it");

        if (saw_joint_healthpen == 0) begin
            $display("   [FAIL] crop_health was NOT penalised by the interaction (stayed 255).");
            errors = errors + 1;
        end else
            $display("   [PASS] crop_health penalised by the interaction (weighted fusion < 255).");

        $display("---------------------------------------------------------------------");
        if (errors == 0)
            $display("RESULT: PASS - all story-arc decisions correct; no false weed triggers.");
        else
            $display("RESULT: FAIL - %0d error(s) detected.", errors);
        $display(" Open the waveform with:  gtkwave dump.vcd");
        $display("=====================================================================");
        $finish;
    end

    // ---- Monitor + self-check -----------------------------------------------
    // On every out_valid, the decision belongs to the sample whose inputs we
    // captured one cycle earlier (avg_*_d / ts_d).  We classify that sample's
    // phase by its timestamp and update the observation counters.  Then we refresh
    // the 1-cycle-delayed input snapshot for next cycle (nonblocking, so the reads
    // above see the OLD "one cycle ago" values).
    always @(posedge clk) begin
        if (!rst) begin
            if (out_valid) begin
                $display(" %4d | %4d %4d %4d |  %0d  %0d   %0d   %0d    %0d    %0d  |  %0d   %3d  | id=%0d ts=%0d",
                         ts_d, avg_m_d, avg_n_d, avg_t_d,
                         dry, low_nutrient, hot, cold, weed, anomaly,
                         status, crop_health, event_id, event_timestamp);

                // --- HEALTHY phase (ts < DRY_LO): everything must be quiet ----
                if (ts_d < DRY_LO) begin
                    if (dry || low_nutrient || hot || cold || weed || anomaly || status != 0)
                        saw_bad_in_healthy = 1;
                end

                // --- SLOW DRY-SPELL phase -----------------------------------
                if (ts_d >= DRY_LO && ts_d <= DRY_HI) begin
                    if (dry)  saw_dry_in_dryspell  = 1;
                    if (weed) saw_weed_in_dryspell = 1;   // must remain 0
                end

                // --- WEED phase ---------------------------------------------
                if (ts_d >= WEED_LO && ts_d <= WEED_HI) begin
                    if (weed)              saw_weed_in_weed    = 1;
                    if (event_id == 4'd3)  saw_weedevt_in_weed = 1;
                end

                // --- HEAT phase ---------------------------------------------
                if (ts_d >= HEAT_LO && ts_d <= HEAT_HI) begin
                    if (hot)               saw_hot_in_heat     = 1;
                    if (event_id == 4'd5)  saw_heatevt_in_heat = 1;
                    if (weed)              saw_weed_in_heat    = 1;   // must remain 0
                end

                // --- JOINT / FUSION phase (Phase 8C) ------------------------
                // Each channel individually reads "fine" (all base conditions 0),
                // but the COMBINATION must be flagged (status leaves SAFE) and
                // crop_health penalised.  This is the case OR-of-thresholds misses.
                if (ts_d >= JOINT_LO && ts_d <= JOINT_HI) begin
                    joint_samples_seen = joint_samples_seen + 1;
                    if (status != 0)      saw_joint_flag      = 1;   // fusion caught it
                    if (dry || low_nutrient || hot || cold || weed || anomaly)
                                          saw_joint_single    = 1;   // must remain 0
                    if (crop_health < 255) saw_joint_healthpen = 1;  // interaction penalty
                end

                // --- Timestamp integrity: an event must stamp the sample's ts -
                if (event_id != 4'd0 && event_timestamp !== ts_d) begin
                    $display("   ^ ERROR: event_timestamp %0d != sample ts %0d",
                             event_timestamp, ts_d);
                    errors = errors + 1;
                end
            end

            // Refresh the 1-cycle-delayed input snapshot.
            avg_m_d    <= avg_moisture;
            avg_n_d    <= avg_nutrient;
            avg_t_d    <= avg_temp;
            ts_d       <= timestamp;
            in_valid_d <= in_valid;
        end
    end

endmodule
