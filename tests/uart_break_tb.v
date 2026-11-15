`timescale 1ns/1ps
// N04: This interface-compatible reproducer must fail on the pinned source.
module uart_break_tb;
  reg clk=0, rst=0, rx=1;
  wire valid;
  wire [7:0] data;
  integer count=0;
  always #5 clk=~clk;
  UART_RX dut(.i_Rst_L(rst), .i_Clock(clk), .i_RX_Serial(rx),
              .o_RX_DV(valid), .o_RX_Byte(data));
  always @(posedge clk) if (valid) count=count+1;
  initial begin
    repeat(3) @(negedge clk);
    rst=1;
    repeat(3) @(negedge clk);
    rx=0;
    repeat(10000) @(negedge clk);
    if(count != 0) $fatal(1,"N04: 10000-clock break accepted %0d bytes",count);
    $display("PASS: 10000-clock break accepted no bytes");
    $finish;
  end
endmodule
