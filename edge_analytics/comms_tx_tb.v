// comms_tx_tb.v
// -----------------------------------------------------------------------------
// Testbench for comms_tx (Phase 8A) - the event-triggered caretaker comms channel.
//
// WHAT IT PROVES (self-checking, 0 errors on PASS):
//   1. msg_valid fires ONLY for human-needed events (WEED, NUTRIENT_LOW, FROST_RISK,
//      PREDICT_DRY here) and NOT for machine-handled ones (PUMP_ON, HEAT_STRESS).
//   2. Each transmitted packet carries the CORRECT severity + action_code + event_code
//      + crop_health + event_timestamp, packed per docs/INTERFACES.md 6.
//   3. The rate limit suppresses a rapid REPEAT of the SAME event (NUTRIENT_LOW twice
//      within MSG_GAP valid cycles -> only the first transmits).
//   4. msg_count equals the number of packets that actually went out.
//
// Story of events driven (one-cycle pulses, NONE between them = fresh edges):
//   WEED(hu)  -> PUMP_ON(mc) -> NUTRIENT_LOW(hu) -> NUTRIENT_LOW rapid-repeat(supp)
//   -> FROST_RISK(hu) -> PREDICT_DRY(hu) -> HEAT_STRESS(mc)
//   Expect 4 packets total; PUMP_ON, HEAT_STRESS and the repeat send nothing.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module comms_tx_tb;

    // ---- Params mirror the DUT so the self-check math matches --------------
    localparam TS_WIDTH     = 32;
    localparam STATUS_WIDTH = 2;
    localparam HEALTH_WIDTH = 8;
    localparam PKT_WIDTH    = 64;
    localparam CNT_WIDTH    = 16;
    localparam MSG_GAP      = 16'd8;

    // ---- Event ids (docs/INTERFACES.md 4) ---------------------------------
    localparam EV_NONE         = 4'd0;
    localparam EV_PUMP_ON      = 4'd1;
    localparam EV_PUMP_OFF     = 4'd2;
    localparam EV_WEED         = 4'd3;
    localparam EV_NUTRIENT_LOW = 4'd4;
    localparam EV_HEAT_STRESS  = 4'd5;
    localparam EV_FROST_RISK   = 4'd6;
    localparam EV_SENSOR_ANOM  = 4'd7;
    localparam EV_STATUS_CRIT  = 4'd8;
    localparam EV_PREDICT_DRY  = 4'd9;

    // ---- Action codes (docs/INTERFACES.md 6) ------------------------------
    localparam AC_NONE          = 4'd0;
    localparam AC_INSPECT_WEED  = 4'd1;
    localparam AC_CHECK_SENSOR  = 4'd2;
    localparam AC_MANUAL_FERT   = 4'd3;
    localparam AC_PROTECT_FROST = 4'd4;
    localparam AC_RELOCATE_REV  = 4'd5;
    localparam AC_PRE_IRRIGATE  = 4'd6;

    // ---- Severity codes ---------------------------------------------------
    localparam SEV_INFO     = 4'd1;
    localparam SEV_WARNING  = 4'd2;
    localparam SEV_CRITICAL = 4'd3;

    // ---- DUT connections --------------------------------------------------
    reg                     clk;
    reg                     rst;
    reg                     in_valid;
    reg  [3:0]              event_id;
    reg  [TS_WIDTH-1:0]     event_timestamp;
    reg  [STATUS_WIDTH-1:0] status;
    reg  [HEALTH_WIDTH-1:0] crop_health;

    wire                    msg_valid;
    wire [PKT_WIDTH-1:0]    alert_packet;
    wire [CNT_WIDTH-1:0]    msg_count;

    comms_tx #(
        .TS_WIDTH(TS_WIDTH), .STATUS_WIDTH(STATUS_WIDTH), .HEALTH_WIDTH(HEALTH_WIDTH),
        .PKT_WIDTH(PKT_WIDTH), .CNT_WIDTH(CNT_WIDTH), .MSG_GAP(MSG_GAP)
    ) dut (
        .clk(clk), .rst(rst), .in_valid(in_valid),
        .event_id(event_id), .event_timestamp(event_timestamp),
        .status(status), .crop_health(crop_health),
        .msg_valid(msg_valid), .alert_packet(alert_packet), .msg_count(msg_count)
    );

    // ---- Clock: 10ns period ------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- Unpack the captured packet for readable checks/prints -------------
    // (Same field split as the RTL, MSB->LSB.)
    wire [3:0]             pk_sev    = alert_packet[63:60];
    wire [3:0]             pk_event  = alert_packet[59:56];
    wire [3:0]             pk_action = alert_packet[55:52];
    wire [HEALTH_WIDTH-1:0] pk_health = alert_packet[51:44];
    wire [11:0]            pk_resv   = alert_packet[43:32];
    wire [TS_WIDTH-1:0]    pk_ts     = alert_packet[31:0];

    // ---- Scoreboard: record every transmitted packet -----------------------
    integer errors;
    integer tx_n;                 // how many packets we have captured
    reg [3:0]  got_sev   [0:15];
    reg [3:0]  got_event [0:15];
    reg [3:0]  got_action[0:15];
    reg [7:0]  got_health[0:15];
    reg [11:0] got_resv  [0:15];
    reg [31:0] got_ts    [0:15];

    // Capture on any cycle msg_valid is high (registered 1-cycle strobe).
    always @(posedge clk) begin
        if (!rst && msg_valid) begin
            got_sev   [tx_n] = pk_sev;
            got_event [tx_n] = pk_event;
            got_action[tx_n] = pk_action;
            got_health[tx_n] = pk_health;
            got_resv  [tx_n] = pk_resv;
            got_ts    [tx_n] = pk_ts;
            $display("# TX packet %0d : sev=%0d event=%0d action=%0d health=%0d resv=%0d ts=%0d  (raw=%016h)",
                     tx_n, pk_sev, pk_event, pk_action, pk_health, pk_resv, pk_ts, alert_packet);
            tx_n = tx_n + 1;
        end
    end

    // ---- Stimulus helper: drive ONE event pulse, then a NONE gap cycle -----
    // Two valid cycles per call: [event] then [NONE]. The NONE makes the next
    // same-value event a fresh edge, and ages the rate-limit counter.
    task send_event;
        input [3:0]  id;
        input [31:0] ts;
        input [1:0]  st;
        input [7:0]  hp;
        begin
            @(negedge clk);
            in_valid        = 1'b1;
            event_id        = id;
            event_timestamp = ts;
            status          = st;
            crop_health     = hp;
            @(negedge clk);
            event_id        = EV_NONE;   // drop to NONE -> edge gap, keep valid high
        end
    endtask

    // ---- One expected-packet checker --------------------------------------
    task check_tx;
        input integer      idx;
        input [3:0]        e_sev;
        input [3:0]        e_event;
        input [3:0]        e_action;
        input [7:0]        e_health;
        input [31:0]       e_ts;
        begin
            if (got_sev[idx]    !== e_sev)    begin errors=errors+1; $display("# FAIL tx%0d severity:    got %0d exp %0d", idx, got_sev[idx],    e_sev);    end
            if (got_event[idx]  !== e_event)  begin errors=errors+1; $display("# FAIL tx%0d event_code:  got %0d exp %0d", idx, got_event[idx],  e_event);  end
            if (got_action[idx] !== e_action) begin errors=errors+1; $display("# FAIL tx%0d action_code: got %0d exp %0d", idx, got_action[idx], e_action); end
            if (got_health[idx] !== e_health) begin errors=errors+1; $display("# FAIL tx%0d crop_health: got %0d exp %0d", idx, got_health[idx], e_health); end
            if (got_resv[idx]   !== 12'd0)    begin errors=errors+1; $display("# FAIL tx%0d reserved:    got %0d exp 0", idx, got_resv[idx]);              end
            if (got_ts[idx]     !== e_ts)     begin errors=errors+1; $display("# FAIL tx%0d timestamp:   got %0d exp %0d", idx, got_ts[idx],     e_ts);     end
        end
    endtask

    // ---- Main sequence -----------------------------------------------------
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, comms_tx_tb);

        errors = 0;
        tx_n   = 0;
        in_valid = 0; event_id = EV_NONE; event_timestamp = 0; status = 0; crop_health = 0;

        // Synchronous reset for a couple of cycles.
        rst = 1;
        @(negedge clk);
        @(negedge clk);
        rst = 0;

        $display("# comms_tx testbench - driving the caretaker-alert story");
        $display("# --------------------------------------------------------");

        // 1) WEED_DETECTED - human-needed, status CRITICAL -> packet (sev3, ac INSPECT_WEED)
        send_event(EV_WEED,         32'd100, 2'd2, 8'd30);
        // 2) PUMP_ON - machine-handled -> NO packet
        send_event(EV_PUMP_ON,      32'd110, 2'd0, 8'd95);
        // 3) NUTRIENT_LOW - human-needed, status WARNING -> packet (sev2, ac MANUAL_FERT)
        send_event(EV_NUTRIENT_LOW, 32'd120, 2'd1, 8'd60);
        // 4) NUTRIENT_LOW again immediately - rate-limited -> SUPPRESSED (no packet)
        send_event(EV_NUTRIENT_LOW, 32'd122, 2'd1, 8'd58);
        // 5) FROST_RISK - human-needed, status CRITICAL -> packet (sev3, ac PROTECT_FROST)
        send_event(EV_FROST_RISK,   32'd140, 2'd2, 8'd45);
        // 6) PREDICT_DRY - human-needed, status SAFE -> packet (sev1 INFO, ac PRE_IRRIGATE)
        send_event(EV_PREDICT_DRY,  32'd160, 2'd0, 8'd80);
        // 7) HEAT_STRESS - not a caretaker action -> NO packet
        send_event(EV_HEAT_STRESS,  32'd170, 2'd1, 8'd70);

        // Drain: a few idle valid cycles so the last strobe is captured.
        @(negedge clk); event_id = EV_NONE;
        @(negedge clk);
        @(negedge clk);
        in_valid = 0;
        @(negedge clk);

        // ---- Self-checks ---------------------------------------------------
        $display("# --------------------------------------------------------");
        $display("# Captured %0d packets; msg_count register = %0d", tx_n, msg_count);

        // Exactly 4 human-needed packets should have transmitted.
        if (tx_n !== 4) begin
            errors = errors + 1;
            $display("# FAIL: expected 4 transmitted packets, captured %0d", tx_n);
        end
        // msg_count register must agree with what we saw on the wire.
        if (msg_count !== 4) begin
            errors = errors + 1;
            $display("# FAIL: msg_count = %0d, expected 4", msg_count);
        end

        // Verify each packet's contents (order = transmit order).
        check_tx(0, SEV_CRITICAL, EV_WEED,         AC_INSPECT_WEED,  8'd30, 32'd100);
        check_tx(1, SEV_WARNING,  EV_NUTRIENT_LOW, AC_MANUAL_FERT,   8'd60, 32'd120);
        check_tx(2, SEV_CRITICAL, EV_FROST_RISK,   AC_PROTECT_FROST, 8'd45, 32'd140);
        check_tx(3, SEV_INFO,     EV_PREDICT_DRY,  AC_PRE_IRRIGATE,  8'd80, 32'd160);

        $display("# --------------------------------------------------------");
        if (errors == 0)
            $display("# RESULT: PASS (0 errors) - comms_tx transmits only for human-needed events, packets correct, rate-limit works, msg_count matches.");
        else
            $display("# RESULT: FAIL (%0d errors)", errors);

        $finish;
    end

endmodule
