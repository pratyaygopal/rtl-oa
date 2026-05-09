module packet_tb;
    timeunit 1ps;
    timeprecision 1ps;

    localparam logic [7:0] MATCH_PATTERN = 8'b1011_0010;

    logic       clk = 1'b0;
    logic       rst = 1'b1;
    logic       bit_valid = 1'b0;
    logic       bit_ready;
    logic       bit_in = 1'b0;
    logic       out_ready = 1'b1;
    logic       out_valid;
    logic [7:0] out_data;
    logic       packet_match;

    time clock_period_ps;
    time clock_half_period_ps;
    int unsigned sim_timeout;
    int unsigned cycle;
    bit dump_fsdb;

    bit have_prev_sample;
    logic prev_rst;
    logic prev_out_ready;
    logic prev_out_valid;
    logic [7:0] prev_out_data;

    packet dut (
        .clk          (clk),
        .rst          (rst),
        .bit_valid    (bit_valid),
        .bit_ready    (bit_ready),
        .bit_in       (bit_in),
        .out_ready    (out_ready),
        .out_valid    (out_valid),
        .out_data     (out_data),
        .packet_match (packet_match)
    );

    initial begin
        if (!$value$plusargs("CLOCK_PERIOD_PS=%d", clock_period_ps)) begin
            clock_period_ps = time'(1000);
        end
        if (clock_period_ps < 2) begin
            $display("packet_tb FAIL");
            $fatal(1, "packet_tb FAIL");
        end

        clock_half_period_ps = clock_period_ps / 2;
        forever #(clock_half_period_ps) clk = ~clk;
    end

    initial begin
        if (!$value$plusargs("SIM_TIMEOUT=%d", sim_timeout)) begin
            sim_timeout = 300;
        end
        if (!$value$plusargs("DUMP_FSDB=%d", dump_fsdb)) begin
            dump_fsdb = 1'b0;
        end

        if (dump_fsdb) begin
            $fsdbDumpfile("dump.fsdb");
            $fsdbDumpvars(0, packet_tb);
        end
    end

    initial begin
        wait (clock_half_period_ps > 0);
        repeat (sim_timeout) @(posedge clk);
        fail($sformatf("Simulation timeout after %0d cycles", sim_timeout));
    end

    always_ff @(posedge clk) begin
        cycle <= cycle + 1'd1;
    end

    task automatic fail(input string label);
        $display("packet_tb FAIL");
        $fatal(1, "packet_tb FAIL");
    endtask

    task automatic expect_logic(
        input logic actual,
        input logic expected,
        input string label
    );
        if (actual !== expected) begin
            fail($sformatf("%s: expected %b, got %b", label, expected, actual));
        end
    endtask

    task automatic expect_byte(
        input logic [7:0] actual,
        input logic [7:0] expected,
        input string label
    );
        if (actual !== expected) begin
            fail($sformatf("%s: expected 0x%02h, got 0x%02h", label, expected, actual));
        end
    endtask

    task automatic check_invariants(input string label);
        logic expected_match;

        expected_match = out_valid && (out_data == MATCH_PATTERN);

        if (out_valid && !out_ready && bit_ready) begin
            fail($sformatf("%s: bit_ready must be low while an output byte is stalled", label));
        end

        if (packet_match !== expected_match) begin
            fail($sformatf(
                "%s: packet_match must equal out_valid && out_data == 0x%02h",
                label,
                MATCH_PATTERN
            ));
        end

        if (
            have_prev_sample &&
            !rst &&
            !prev_rst &&
            prev_out_valid &&
            !prev_out_ready &&
            out_valid &&
            !out_ready
        ) begin
            expect_logic(out_valid, 1'b1, {label, ": held output remains valid"});
            expect_byte(out_data, prev_out_data, {label, ": held output data stable"});
        end

        have_prev_sample = 1'b1;
        prev_rst = rst;
        prev_out_ready = out_ready;
        prev_out_valid = out_valid;
        prev_out_data = out_data;
    endtask

    task automatic tick(input string label = "tick");
        @(posedge clk);
        #1;
        check_invariants(label);
    endtask

    task automatic expect_reset_state(input string label);
        expect_logic(out_valid, 1'b0, {label, ": out_valid reset"});
        expect_byte(out_data, 8'h00, {label, ": out_data reset"});
        expect_logic(packet_match, 1'b0, {label, ": packet_match reset"});
        expect_logic(bit_ready, 1'b1, {label, ": ready after reset"});
    endtask

    task automatic apply_reset(input string label);
        rst = 1'b1;
        bit_valid = 1'b0;
        bit_in = 1'b0;
        out_ready = 1'b1;

        repeat (2) tick({label, ": reset asserted"});
        expect_reset_state(label);

        rst = 1'b0;
        tick({label, ": reset released"});
        expect_reset_state({label, ": post-reset idle"});
    endtask

    task automatic drive_invalid_cycle(input logic value, input string label);
        bit_valid = 1'b0;
        bit_in = value;
        tick(label);
        expect_logic(out_valid, 1'b0, {label, ": invalid bit must not complete byte"});
    endtask

    task automatic drive_accepted_bit(input logic value, input string label);
        bit_valid = 1'b1;
        bit_in = value;

        if (bit_ready !== 1'b1) begin
            fail({label, ": attempted to drive accepted bit while bit_ready was low"});
        end

        tick(label);
    endtask

    task automatic drive_byte(
        input logic [7:0] value,
        input bit insert_invalid_gaps,
        input string label
    );
        for (int i = 7; i >= 0; i--) begin
            if (insert_invalid_gaps && ((i == 6) || (i == 3))) begin
                drive_invalid_cycle(~value[i], $sformatf("%s invalid gap before bit %0d", label, i));
            end

            drive_accepted_bit(value[i], $sformatf("%s accepted bit %0d", label, i));

            if (i != 0) begin
                expect_logic(
                    out_valid,
                    1'b0,
                    $sformatf("%s: no output before all 8 accepted bits", label)
                );
            end
        end

        bit_valid = 1'b0;
        bit_in = 1'b0;
    endtask

    task automatic expect_output(input logic [7:0] expected, input string label);
        expect_logic(out_valid, 1'b1, {label, ": out_valid"});
        expect_byte(out_data, expected, {label, ": out_data"});
        expect_logic(packet_match, expected == MATCH_PATTERN, {label, ": packet_match"});
        expect_logic(bit_ready, 1'b0, {label, ": input backpressure"});
    endtask

    task automatic consume_output(input string label);
        bit_valid = 1'b0;
        bit_in = 1'b0;
        out_ready = 1'b1;

        tick(label);
        expect_logic(out_valid, 1'b0, {label, ": output consumed"});
        expect_logic(packet_match, 1'b0, {label, ": packet_match cleared after consume"});
        expect_logic(bit_ready, 1'b1, {label, ": input ready after consume"});
    endtask

    task automatic test_header_match;
        drive_byte(MATCH_PATTERN, 1'b0, "header match");
        expect_output(MATCH_PATTERN, "header match");
        consume_output("header match consumed");
    endtask

    task automatic test_mismatch_with_invalid_gaps;
        drive_byte(8'h5c, 1'b1, "mismatch");
        expect_output(8'h5c, "mismatch");
        consume_output("mismatch consumed");
    endtask

    task automatic test_output_stall_and_ignored_input;
        out_ready = 1'b0;
        drive_byte(MATCH_PATTERN, 1'b0, "held header");
        expect_output(MATCH_PATTERN, "held header");

        for (int i = 0; i < 4; i++) begin
            bit_valid = 1'b1;
            bit_in = i[0];
            tick($sformatf("stall cycle %0d", i));
            expect_output(MATCH_PATTERN, $sformatf("stall cycle %0d", i));
        end

        out_ready = 1'b1;
        bit_valid = 1'b1;
        bit_in = 1'b0;
        tick("release stall while bit_valid is high");
        expect_logic(out_valid, 1'b0, "release stall: output consumed");
        expect_logic(bit_ready, 1'b1, "release stall: ready returns");

        bit_valid = 1'b0;
        bit_in = 1'b0;
        drive_byte(8'ha5, 1'b0, "post-stall byte");
        expect_output(8'ha5, "post-stall byte");
        consume_output("post-stall byte consumed");
    endtask

    task automatic test_reset_clears_partial_byte;
        drive_accepted_bit(1'b1, "partial byte bit 7");
        drive_accepted_bit(1'b0, "partial byte bit 6");
        drive_accepted_bit(1'b1, "partial byte bit 5");
        expect_logic(out_valid, 1'b0, "partial byte: no output before reset");

        apply_reset("mid-byte reset");

        drive_byte(8'h3c, 1'b0, "after mid-byte reset");
        expect_output(8'h3c, "after mid-byte reset");
        consume_output("after mid-byte reset consumed");
    endtask

    initial begin
        wait (clock_half_period_ps > 0);
        apply_reset("initial reset");

        test_header_match();
        test_mismatch_with_invalid_gaps();
        test_output_stall_and_ignored_input();
        test_reset_clears_partial_byte();

        $display("packet_tb PASS");
        $finish;
    end
endmodule
