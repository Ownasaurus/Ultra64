`timescale 1ns/1ps
// Parameter boundaries verify uninterrupted qualification and the protocol default.
module filter_case #(parameter N=6)(output reg done = 0);
reg clk = 0;
always #10 clk = !clk;
reg pin = 1;
wire filtered;
glitch_filter #(.STABLE_CYCLES(N)) dut(clk, pin, filtered);
integer i;
task sample;
    input level, expected;
    begin
        @(negedge clk); pin = level;
        @(posedge clk); #1;
        if (filtered !== expected) $fatal(1, "N=%0d level=%b expected=%b got=%b", N, level, expected, filtered);
    end
endtask
initial begin
    sample(1, 1);
    for (i=1; i<N; i=i+1) sample(0, 1);
    sample(1, 1);                     // A matching sample cancels accumulated disagreement.
    for (i=1; i<N; i=i+1) sample(0, 1);
    sample(0, 0);
    for (i=1; i<N; i=i+1) sample(1, 0);
    sample(0, 0);                     // Release qualification also requires consecutive samples.
    for (i=1; i<N; i=i+1) sample(1, 0);
    sample(1, 1);
    $display("PASS filter interval=%0d", N);
    done = 1;
end
endmodule

// Also instantiate without an override to guard protocol timing independently of button timing.
module n13_filter_tb;
wire a,b,c,d;
filter_case #(1) one(a);
filter_case #(6) protocol(b);
filter_case #(7) non_power_of_two(c);
filter_case #(500000) button(d);
reg clk = 0;
always #10 clk = !clk;
reg pin = 1;
wire filtered;
glitch_filter default_filter(clk, pin, filtered);
integer i;
initial begin
    @(negedge clk); pin = 0;
    for (i=1; i<=6; i=i+1) begin
        @(posedge clk); #1;
        if (filtered !== (i < 6)) $fatal(1, "default protocol interval changed at %0d", i);
    end
    wait(a && b && c && d);
    $display("PASS N13 filter: default six clocks and interval boundaries");
    $finish;
end
endmodule
