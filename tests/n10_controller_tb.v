`timescale 1ns/1ps
// N10 integration regression uses the real filter, wrapper and transmitters.
// FIFO behavior is irrelevant in passthrough mode, so no vendor RAM is required.
module queue_1024(input Clock, RdEn, Reset, WrEn, input [31:0] Data,
                  output Empty, Full, output [31:0] Q);
assign Empty = 0;
assign Full = 0;
assign Q = 32'h12345678;
endmodule

module n10_controller_tb;
reg clk = 0;
always #10 clk = !clk;
tri1 bus;
reg console_low = 0;
assign bus = console_low ? 1'b0 : 1'bz;
wire next_frame;
n64_controller dut(clk,bus,32'h12345678,1'b0,1'b0,32'b0,1'b0,next_frame);
reg prohibit_reply = 1;
integer identity_replies = 0;
integer poll_replies = 0;
integer p, w;

// Any scheduled response while feeding an invalid/partial command is a failure.
always @(negedge clk) begin
    if(prohibit_reply && (dut.direction_output || dut.transmit_identity ||
                          dut.transmit_controller_state))
        $fatal(1,"N10 unsolicited response: position=%0d width=%0d",p,w);
    if(dut.transmit_identity === 1'b1) identity_replies = identity_replies + 1;
    if(dut.transmit_controller_state === 1'b1) poll_replies = poll_replies + 1;
end

task hold_bus;
    input low_level;
    input integer clocks;
    begin
        @(negedge clk); console_low = low_level;
        repeat(clocks) @(posedge clk);
    end
endtask

task pulse;
    input integer low_clocks;
    input integer high_clocks;
    begin hold_bus(1,low_clocks); hold_bus(0,high_clocks); end
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

task valid_command;
    input [7:0] value;
    integer old_ident,old_poll;
    begin
        old_ident = identity_replies; old_poll = poll_replies;
        prefix(value,8);
        hold_bus(1,50);
        // Permit a reply only once the final stop rises on the console bus.
        @(negedge clk); console_low = 0; prohibit_reply = 0;
        hold_bus(0,8000);
        if(value == 1) begin
            if(poll_replies != old_poll+1 || identity_replies != old_ident)
                $fatal(1,"N10 wrong poll response after recovery");
        end else if(identity_replies != old_ident+1 || poll_replies != old_poll)
            $fatal(1,"N10 wrong identity response after recovery");
        if(dut.direction_output) $fatal(1,"N10 response did not finish");
        prohibit_reply = 1;
    end
endtask

initial begin
    hold_bus(0,1000);
    // Pinned-source reproducer: seven old zeros must not consume a new poll.
    p = 7;
    prefix(8'h00,7); hold_bus(0,1000); valid_command(8'h01);
    for(p=0; p<=8; p=p+1) begin
        // Reproduce interrupted prefixes, including a missing final stop.
        prefix(8'h00,p); hold_bus(0,1000); valid_command(8'h01);
        prefix(8'hff,p); hold_bus(0,1000); valid_command(8'h00);
        for(w=0; w<4; w=w+1) begin
            prefix(8'h00,p);
            case(w)
                0: pulse(76,50);
                1: pulse(125,50);
                2: pulse(176,50);
                3: pulse(1000,50);
            endcase
            // Continuous residual traffic must be ignored until a long high.
            prefix(8'h00,8); pulse(50,10);
            hold_bus(0,1000); valid_command(8'hff);
        end
    end
    $display("PASS N10 wrapper: %0d identity and %0d poll replies; no premature response",
             identity_replies,poll_replies);
    $finish;
end
initial begin #100000000; $fatal(1,"N10 wrapper watchdog"); end
endmodule
