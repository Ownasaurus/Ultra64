`timescale 1ns/1ps
// N04: Exercise actual receiver RTL at production and odd/even test divisors.
module uart_framing_tb;
  parameter CPB=434;
  reg clk=0, rst=0, rx=1;
  wire valid, error;
  wire [7:0] data;
  integer valid_count=0, error_count=0, i, before_valid, before_error;
  reg last_valid=0, last_error=0;
  reg [7:0] expected;
  always #5 clk=~clk;
  UART_RX #(.CLKS_PER_BIT(CPB)) dut(
    .i_Rst_L(rst), .i_Clock(clk), .i_RX_Serial(rx),
    .o_RX_DV(valid), .o_RX_Byte(data), .o_RX_Framing_Error(error));

  // N04: Outputs are mutually exclusive single-clock events; data is gated by DV.
  always @(posedge clk) begin
    #1;
    if(valid && (last_valid || error)) $fatal(1,"invalid DV pulse");
    if(error && last_error) $fatal(1,"error held for multiple clocks");
    if(valid) begin
      valid_count=valid_count+1;
      if(data !== expected) $fatal(1,"data %h expected %h",data,expected);
    end
    if(error) error_count=error_count+1;
    last_valid=valid;
    last_error=error;
  end
  task hold_line(input level, input integer clocks);
    begin rx=level; repeat(clocks) @(negedge clk); end
  endtask
  task frame(input [7:0] value, input stop);
    integer bit_index;
    begin
      hold_line(0,CPB);
      for(bit_index=0;bit_index<8;bit_index=bit_index+1)
        hold_line(value[bit_index],CPB);
      hold_line(stop,CPB);
    end
  endtask
  initial begin
    repeat(3) @(negedge clk);
    rst=1;
    hold_line(1,CPB+3);
    // N04: Exhaust all byte values with valid stops and no extra inter-frame gap.
    for(i=0;i<256;i=i+1) begin
      expected=i;
      frame(i,1);
      if(valid_count != i+1) $fatal(1,"valid frame lost at %0d",i);
    end
    // N04: Both high and low final data bits must still require a high stop.
    for(i=0;i<256;i=i+1) begin
      before_valid=valid_count;
      before_error=error_count;
      frame(i,0);
      hold_line(0,25*CPB);
      if(valid_count != before_valid || error_count != before_error+1)
        $fatal(1,"bad stop/break accepted or repeated error at %0d",i);
      // N04: A short high glitch cannot rearm RX; lows restart qualification.
      hold_line(1,CPB-1);
      hold_line(0,12*CPB);
      if(valid_count != before_valid || error_count != before_error+1)
        $fatal(1,"short idle rearmed receiver");
      hold_line(1,CPB);
      expected=i;
      frame(i,1);
      if(valid_count != before_valid+1) $fatal(1,"recovery lost frame");
    end
    // N04: Reset during recovery clears the error and permits fresh reception.
    frame(8'h00,0);
    rst=0;
    hold_line(1,3);
    if(valid || error) $fatal(1,"reset did not clear events");
    rst=1;
    hold_line(1,CPB+3);
    // N04: Assert receipt too, so silent loss after reset cannot pass this test.
    before_valid=valid_count;
    expected=8'ha5;
    frame(8'ha5,1);
    if(valid_count != before_valid+1) $fatal(1,"reset recovery lost frame");
    $display("PASS: CPB=%0d, all 256 good/bad bytes, break, idle qualification, recovery, reset",CPB);
    $finish;
  end
  // N04: Bound regressions so broken recovery cannot hang validation.
  initial begin #100000000; $fatal(1,"timeout"); end
endmodule
