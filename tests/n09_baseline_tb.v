`timescale 1ns/1ps
// N09 source reproduction: demonstrate partial publication after a high timeout.
module n09_baseline_tb;
reg clk = 0, trigger = 0, line = 1;
always #10 clk = ~clk;
wire busy;
wire [31:0] data;
n64_receive_controller_data dut(clk, trigger, data, line, busy);
integer i;
initial begin
    repeat (3) @(negedge clk);
    trigger = 1;
    @(negedge clk); trigger = 0;
    repeat (3) @(negedge clk);
    for (i = 0; i < 8; i = i + 1) begin
        line = 0; repeat (50) @(negedge clk);
        line = 1; repeat (150) @(negedge clk);
    end
    repeat (1000) @(negedge clk);
    if (busy !== 0 || data !== 32'hff000000)
        $fatal(1, "Source reproduction differed: busy=%b data=%h", busy, data);
    $display("CONFIRMED N09: 8 bits then high timeout exposes %h; wrapper unconditionally copies it", data);
    $finish;
end
endmodule
