`timescale 1ns/1ps
// N04: Drive the real wire protocol through receiver and parser at 115200 baud.
module serial_framing_tb;
  localparam CPB=434;
  reg clk=0, rx=1;
  wire tx, write_enable, controller_reset;
  wire [31:0] frame_data;
  integer writes=0, received=0, errors=0, s, k, old_writes, old_received, old_errors;
  reg [31:0] expected_frame=32'h12345678;
  always #5 clk=~clk;
  serial_handler dut(.clk(clk), .request_frame(1'b1), .rx_uart(rx),
    .tx_uart(tx), .queue_WrEn(write_enable), .received_frame_data(frame_data),
    .n64_controller_reset(controller_reset));
  // N04: Check at the queue-consumer edge, including data and pulse width.
  always @(posedge clk) begin
    if(write_enable) begin
      writes=writes+1;
      if(frame_data !== expected_frame) $fatal(1,"corrupted controller frame %h",frame_data);
    end
    if(dut.received) received=received+1;
    if(dut.framing_error) errors=errors+1;
  end
  task hold_line(input level, input integer clocks);
    begin rx=level; repeat(clocks) @(negedge clk); end
  endtask
  task frame(input [7:0] value, input stop);
    integer b;
    begin
      hold_line(0,CPB);
      for(b=0;b<8;b=b+1) hold_line(value[b],CPB);
      hold_line(stop,CPB);
    end
  endtask
  task good_transaction;
    begin
      frame(8'h41,1); frame(8'h12,1); frame(8'h34,1);
      frame(8'h56,1); frame(8'h78,1);
      hold_line(1,4);
    end
  endtask
  initial begin
    hold_line(1,CPB+4);
    // N04: Reproduce an invalid stop at each byte of a real frame transaction.
    for(k=0;k<5;k=k+1) begin
      old_writes=writes;
      old_received=received;
      old_errors=errors;
      if(k>0) frame(8'h41,1);
      if(k>1) frame(8'h12,1);
      if(k>2) frame(8'h34,1);
      if(k>3) frame(8'h56,1);
      frame(8'h00,0);
      hold_line(0,10000);
      if(writes!=old_writes || received!=old_received+k || errors!=old_errors+1)
        $fatal(1,"invalid transaction byte %0d accepted",k);
      if(dut.state!==dut.IDLE || frame_data!==0) $fatal(1,"partial frame retained");
      hold_line(1,CPB);
      good_transaction;
      if(writes!=old_writes+1) $fatal(1,"transaction did not recover");
    end
    // N04: Reach every waiting setup, power and bulk state via valid protocol
    // prefixes, then ensure a bad stop aborts it without executing any command.
    for(k=0;k<7;k=k+1) begin
      old_writes=writes;
      if(k<4) begin
        frame(8'h53,1);
        if(k>0) frame(8'h41,1);
        if(k>1) frame(8'h4d,1);
        if(k>2) frame(8'h80,1);
        if(dut.state !== dut.SETUP_1+k) $fatal(1,"setup prefix not reached");
      end else if(k==4) begin
        frame(8'h50,1);
        if(dut.state !== dut.POWER_1) $fatal(1,"power prefix not reached");
      end else begin
        frame(8'h51,1);
        if(k==6) frame(8'h00,1);
        if(dut.state !== dut.BULK_1+k-5) $fatal(1,"bulk prefix not reached");
      end
      old_received=received; old_errors=errors;
      frame(8'haa,0);
      hold_line(0,10000);
      if(dut.state!==dut.IDLE || received!=old_received ||
         errors!=old_errors+1 || writes!=old_writes)
        $fatal(1,"malformed setup/power/bulk byte accepted at %0d",k);
      hold_line(1,CPB);
      good_transaction;
      if(writes!=old_writes+1) $fatal(1,"prefix %0d did not recover",k);
    end
    // N04: Cover all 19 parser states at the error-consumption edge. Deposit
    // state after RX raises error to cover even one-clock post-processing states
    // without forcing receiver events or bypassing the physical break stimulus.
    for(s=0;s<=18;s=s+1) begin
      old_writes=writes; old_received=received; old_errors=errors;
      rx=0;
      wait(dut.framing_error===1'b1);
      @(negedge clk);
      dut.state=s;
      @(negedge clk);
      if(dut.state!==dut.IDLE || write_enable || controller_reset)
        $fatal(1,"framing failure did not abort state %0d",s);
      hold_line(0,10000);
      if(writes!=old_writes || received!=old_received || errors!=old_errors+1)
        $fatal(1,"break affected parser in state %0d",s);
      hold_line(1,CPB);
      good_transaction;
      if(writes!=old_writes+1) $fatal(1,"state %0d did not recover",s);
    end
    $display("PASS: parser invalid byte at all frame positions; setup/power/bulk prefixes; breaks/errors in all 19 states; %0d recovered frames",writes);
    $finish;
  end
  // N04: Fail quickly if an expected error never arrives.
  initial begin #100000000; $fatal(1,"timeout"); end
endmodule
