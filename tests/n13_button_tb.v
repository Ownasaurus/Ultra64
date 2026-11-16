`timescale 1ns/1ps
// Exercise the real top-level button wiring at 50 MHz; unrelated peripherals are stubbed.
module n13_button_tb;
reg clk = 0;
always #10 clk = !clk;
reg button = 1;
wire [7:0] led;
wire n64real, n64;
top dut(.clk12(clk), .button(button), .led(led), .n64real(n64real),
        .n64(n64), .rx_uart(1'b1), .tx_uart(), .debug());
integer transitions = 0;
reg previous = 1;
always @(negedge clk) begin
    if (led[7] !== previous) begin
        transitions = transitions + 1;
        previous = led[7];
    end
end

// Drive away from sampling edges and check every cycle to catch transient extra toggles.
task hold;
    input level;
    input integer cycles, expected;
    integer i;
    begin
        #1 button = level;
        for (i = 0; i < cycles; i = i + 1) begin
            @(negedge clk); #1;
            if (transitions != expected || led[7] !== (1 ^ (expected & 1)))
                $fatal(1, "button=%b cycle=%0d expected=%0d transitions=%0d mode=%b",
                       level, i, expected, transitions, led[7]);
        end
    end
endtask

initial begin
    // Optional diagnostic reproduces the report against the pinned original top/filter.
    if ($test$plusargs("bounce-trace")) begin
        #1 button = 0;
        repeat (50000) @(negedge clk);
        #1 button = 1;
        repeat (50000) @(negedge clk);
        #1 button = 0;
        repeat (50000) @(negedge clk);
        #1;
        $display("N13 low/high/low 1 ms: transitions=%0d final_mode=%b", transitions, led[7]);
        $finish;
    end
    hold(1, 100, 0);                   // Idle must preserve the initial TAS mode.
    hold(0, 50000, 0);
    hold(1, 50000, 0);
    hold(0, 50000, 0);                 // Reported low/high/low 1 ms bounce trace.
    hold(1, 400000, 0);                // Release bounce below 10 ms also resets qualification.
    hold(0, 500000, 0);                // Filter changes now; mode sees it on the next edge.
    hold(0, 1500000, 1);               // A long hold toggles exactly once.
    hold(1, 499999, 1);
    hold(0, 600000, 1);                // One sample short of release must not rearm.
    hold(1, 50000, 1);
    hold(0, 50000, 1);
    hold(1, 50000, 1);
    hold(0, 50000, 1);                 // Release bounce cannot become another press.
    hold(1, 500001, 1);                // Fully qualified release rearms the latch.
    hold(0, 499999, 1);
    hold(0, 1, 1);                    // Exact press boundary still has pipeline latency.
    hold(0, 1000000, 2);              // A second accepted press toggles back exactly once.
    $display("PASS N13 top: press/release bounce, threshold boundaries, holds, second press");
    $finish;
end
endmodule

// These stubs isolate the button path; they do not validate protocol or vendor primitives.
module pll_12_50(input clki, output clko);
assign clko = clki;
endmodule
module n64_controller(input sys_clk, inout n64d, input [31:0] real_controller_data,
    input input_mode, queue_WrEn, input [31:0] queue_data,
    output next_frame_request, input n64_controller_reset);
assign next_frame_request = 0;
endmodule
module n64_controller_reader(input sys_clk, inout n64d, output [31:0] controller_data);
assign controller_data = 0;
endmodule
module serial_handler #(parameter NUM_CONSOLES=1)(input clk,
    input [NUM_CONSOLES-1:0] request_frame, input rx_uart, output tx_uart,
    output queue_WrEn, output [31:0] received_frame_data, output n64_controller_reset);
assign tx_uart = 1;
assign queue_WrEn = 0;
assign received_frame_data = 0;
assign n64_controller_reset = 0;
endmodule
