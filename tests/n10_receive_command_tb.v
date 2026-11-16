`timescale 1ns/1ps
// N10 regression: exercise real receiver RTL, including every truncation point.
module n10_receive_command_tb;
reg clk = 0;
always #10 clk = !clk;
reg trigger = 0;
reg line = 1;
wire [7:0] command;
wire receiving;
n64_receive_command dut(clk, trigger, command, line, receiving);
integer accepted = 0;
integer checks = 0;
integer p, w, v;
reg previous_receiving = 0;
reg [7:0] last_command = 0;

// Count the public completion handshake, not internal state transitions.
always @(negedge clk) begin
    if(previous_receiving && !receiving) begin
        accepted = accepted + 1;
        last_command = command;
    end
    previous_receiving = receiving;
end

task hold_line;
    input level;
    input integer clocks;
    begin
        @(negedge clk); line = level;
        repeat(clocks) @(posedge clk);
    end
endtask

// Use sampled pulse widths exactly; falling edges never race the DUT clock.
task pulse;
    input integer low_clocks;
    input integer high_clocks;
    begin hold_line(0, low_clocks); hold_line(1, high_clocks); end
endtask

task arm;
    begin
        @(negedge clk); trigger = 1;
        @(negedge clk); trigger = 0;
        hold_line(1, 5);
    end
endtask

task prefix;
    input [7:0] value;
    input integer count;
    integer b;
    begin
        for(b=0; b<count; b=b+1)
            if(value[7-b]) pulse(50,150); else pulse(150,50);
    end
endtask

task expect_pending;
    input integer before_count;
    begin
        // Neither completion nor publication may occur for a malformed frame.
        @(negedge clk);
        if(!receiving || accepted != before_count || command !== last_command)
            $fatal(1, "N10 invalid command completed: position=%0d width=%0d", p,w);
        checks = checks + 1;
    end
endtask

task complete;
    input [7:0] value;
    integer before_count;
    begin
        before_count = accepted;
        prefix(value,8);
        pulse(50,10);
        @(negedge clk);
        if(receiving || accepted != before_count+1 || command !== value)
            $fatal(1, "N10 recovery/decode failed: expected=%h actual=%h accepted=%0d", value,command,accepted);
        checks = checks + 1;
        arm;
    end
endtask

integer before_count;
initial begin
    arm;
    // Unlimited idle before a command must neither complete nor overflow.
    hold_line(1,10000);
    expect_pending(0);
    complete(8'h01);
    for(p=0; p<=8; p=p+1) begin
        // Eight bits without a stop is also incomplete. Recover to both replies.
        before_count = accepted;
        prefix(8'h00,p);
        hold_line(1,1000);
        expect_pending(before_count);
        complete(8'h01);
        prefix(8'hff,p);
        hold_line(1,1000);
        expect_pending(accepted);
        complete(8'h00);
        // A controller stop at any position must never finish a console command.
        for(w=0; w<6; w=w+1) begin
            before_count = accepted;
            prefix(8'h00,p);
            case(w)
                0: pulse(25,50);
                1: pulse(76,50);
                2: pulse(100,50);
                3: pulse(125,50);
                4: pulse(176,50);
                5: pulse(1000,50);
            endcase
            // Residual bits cannot be reinterpreted before the idle boundary.
            prefix(8'h00,8);
            pulse(50,10);
            expect_pending(before_count);
            hold_line(1,1000);
            complete(8'hff);
        end
    end
    // A ninth zero is invalid; an early one remains data until a gap discards it.
    before_count = accepted;
    prefix(8'h00,8); pulse(150,50); pulse(50,10);
    expect_pending(before_count);
    hold_line(1,200); complete(8'h01);
    for(p=0; p<8; p=p+1) begin
        before_count = accepted;
        prefix(8'h00,p); pulse(50,1000);
        expect_pending(before_count);
        complete(8'h00);
    end
    // All byte values retain MSB-first decoding, including supported 00/01/FF.
    for(v=0; v<256; v=v+1) complete(v);
    // Accepted data and console-stop width endpoints retain existing tolerance.
    for(w=0; w<2; w=w+1) begin
        before_count = accepted;
        for(p=0; p<8; p=p+1) pulse(w ? 75 : 26,150);
        pulse(w ? 75 : 26,10);
        @(negedge clk);
        if(receiving || accepted != before_count+1 || command !== 8'hff)
            $fatal(1,"N10 one/stop boundary rejected");
        checks = checks + 1; arm;
        before_count = accepted;
        for(p=0; p<8; p=p+1) pulse(w ? 175 : 126,50);
        pulse(50,10);
        @(negedge clk);
        if(receiving || accepted != before_count+1 || command !== 8'h00)
            $fatal(1,"N10 zero boundary rejected");
        checks = checks + 1; arm;
    end
    // The default gap bound is exactly 200 sampled highs: retain at 199,
    // discard at 200, including the high interval after the eighth bit.
    before_count = accepted;
    pulse(150,199); prefix(8'h00,7); pulse(50,10);
    @(negedge clk);
    if(receiving || accepted != before_count+1 || command !== 8'h00)
        $fatal(1,"N10 legal gap below timeout rejected");
    checks = checks + 1; arm;
    pulse(150,200); complete(8'h01);
    prefix(8'h00,7); pulse(150,200); complete(8'hff);
    $display("PASS N10 receiver: %0d checks, %0d valid completions",checks,accepted);
    $finish;
end

// Bound failures even if a handshake stalls indefinitely.
initial begin #100000000; $fatal(1,"N10 receiver watchdog"); end
endmodule
