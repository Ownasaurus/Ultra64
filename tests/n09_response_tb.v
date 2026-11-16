`timescale 1ns/1ps
// N09 regression uses the real request, filter, receiver and publication wrapper.
module n09_response_tb;
reg clk = 0;
always #10 clk = ~clk;
tri1 line;
reg drive_low = 0;
assign line = drive_low ? 1'b0 : 1'bz;
wire [31:0] published;
n64_controller_reader dut(clk, line, published);
reg [31:0] committed = 0, expected = 0, previous = 0, previous_rx = 0;
integer cases = 0, bits, mode, width;
// Exercise prompt and delayed replies relative to the receiver trigger.
integer response_delay = 20;

// Observe every clock, including payload collection: no partial word may escape.
always @(negedge clk) begin
    if (published !== previous) begin
        if (dut.state !== 3 || published !== expected)
            $fatal(1, "Unexpected publication %h expected %h state %d", published, expected, dut.state);
    end
    if (dut.data_received !== previous_rx && !dut.response_valid)
        $fatal(1, "Receiver changed committed data without success");
    previous = published;
    previous_rx = dut.data_received;
end

// Bound the entire suite so busy/handshake failures cannot hang the regression.
initial begin
    #200000000;
    $fatal(1, "Regression watchdog expired");
end

task clocks;
    input integer count;
    begin repeat (count) @(negedge clk); end
endtask

task start_poll;
    input [31:0] result;
    begin
        expected = result;
        // Shorten only the inter-poll delay, preserving the actual request handshake.
        if (dut.state == 3) begin
            dut.delay_16ms = 0;
            wait (dut.state != 3);
        end
        wait (dut.get_data == 1);
        clocks(response_delay);
        if (!dut.is_receiving_data || dut.response_valid)
            $fatal(1, "New poll did not clear the old result: busy=%b valid=%b state=%d get=%b",
                dut.is_receiving_data, dut.response_valid, dut.receiver.state, dut.get_data);
    end
endtask

task pulse;
    input integer low_clocks;
    input integer high_clocks;
    begin
        drive_low = 1; clocks(low_clocks);
        drive_low = 0; clocks(high_clocks);
    end
endtask

task payload;
    input [31:0] word;
    input integer count;
    integer j;
    begin
        for (j = 0; j < count; j = j + 1)
            if (word[31-j]) pulse(50, 150);
            else pulse(150, 50);
    end
endtask

task finish_poll;
    input integer valid;
    begin
        wait (dut.state == 3);
        clocks(2);
        if (published !== expected || dut.response_valid !== (valid != 0) ||
            dut.data_received !== committed || dut.is_receiving_data !== 0)
            $fatal(1, "Case %0d: published=%h receiver=%h valid=%b expected=%h committed=%h",
                cases, published, dut.data_received, dut.response_valid, expected, committed);
        cases = cases + 1;
    end
endtask

task good_poll;
    input [31:0] word;
    begin
        start_poll(word);
        payload(word, 32);
        pulse(100, 20);
        committed = word;
        finish_poll(1);
    end
endtask

initial begin
    // Positive controls include both data symbols, alternating bits and neutral input.
    good_poll(32'h00000000);
    good_poll(32'hffffffff);
    good_poll(32'ha55a817e);
    // Interrupt at every payload boundary, including 32 bits without termination.
    // Each fault follows non-neutral input and is followed by a valid reconnection.
    for (mode = 0; mode < 3; mode = mode + 1) begin
        for (bits = 0; bits <= 32; bits = bits + 1) begin
            start_poll(mode == 2 && bits == 32 ? 32'hffffffff : 0);
            payload(32'hffffffff, bits);
            if (mode == 0) clocks(1000); // Missing data/stop: stuck high.
            if (mode == 1) begin // Truncate the next pulse: stuck low.
                drive_low = 1; clocks(1000); drive_low = 0;
            end
            if (mode == 2) pulse(100, 20); // Early stop, or valid at exactly 32.
            if (mode == 2 && bits == 32) committed = 32'hffffffff;
            finish_poll(mode == 2 && bits == 32);
            good_poll(32'h01010101);
        end
    end
    // Invalid final stop widths: glitch, console stop, extra zero/one, overlong.
    for (width = 0; width < 6; width = width + 1) begin
        start_poll(0);
        payload(32'h12345678, 32);
        case (width)
            0: pulse(10, 300);
            1: pulse(25, 300);
            2: pulse(50, 300);
            3: pulse(150, 300);
            4: pulse(176, 300);
            5: pulse(250, 300);
        endcase
        finish_poll(0);
        good_poll(32'h87654321);
    end
    // Malformed payload pulses must end busy instead of silently restarting.
    start_poll(0); payload(32'hffffffff, 8); pulse(10, 300); finish_poll(0);
    good_poll(32'h80000001);
    start_poll(0); payload(32'hffffffff, 8); pulse(176, 300); finish_poll(0);
    good_poll(32'h7ffffffe);
    // The turnaround guard must allow replies near arming and near the timeout.
    response_delay = 3; good_poll(32'h80000001);
    response_delay = 7; good_poll(32'h12345678);
    response_delay = 100; good_poll(32'hdeadbeef);
    response_delay = 200; good_poll(32'h01020304);
    $display("PASS N09: %0d integrated polls; all bit boundaries, stuck levels, stops, malformed pulses and reconnection", cases);
    $finish;
end
endmodule
