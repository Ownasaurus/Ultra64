`timescale 1ns/1ps
// N07 regression: actual generated FIFO + vendor primitives, no FIFO behavioral substitute.
module n07_controller_tb;
reg clk=0;
always #10 clk=~clk;
reg gsr=0;
GSR GSR_INST(.GSR(gsr));
PUR PUR_INST(.PUR(1'b1));
reg reset=0, wr=0, mode=1;
reg [31:0] data=0;
tri1 bus_a, bus_b;
reg drive_a=0, drive_b=0;
assign bus_a=drive_a ? 1'b0 : 1'bz;
assign bus_b=drive_b ? 1'b0 : 1'bz;
wire fault_a, fault_b, request_a, request_b;
n64_controller a(.sys_clk(clk), .n64d(bus_a), .real_controller_data(32'h12345678),
 .input_mode(mode), .queue_WrEn(wr), .queue_data(data), .n64_controller_reset(reset),
 .next_frame_request(request_a), .tas_underrun(fault_a));
n64_controller b(.sys_clk(clk), .n64d(bus_b), .real_controller_data(32'h12345678),
 .input_mode(mode), .queue_WrEn(wr), .queue_data(data), .n64_controller_reset(reset),
 .next_frame_request(request_b), .tas_underrun(fault_b));
integer reads_a=0, reads_b=0, replies_a=0, replies_b=0;
integer credit_a=0, credit_b=0;
reg [31:0] expected_a, expected_b;
// Correlate every TAS trigger with a real primitive read enable and its returned word.
always @(posedge clk) begin
 if(reset) begin credit_a=0; credit_b=0; end
 else begin
  if(a.run_data.rden_i) begin reads_a=reads_a+1; credit_a=credit_a+1; end
  if(b.run_data.rden_i) begin reads_b=reads_b+1; credit_b=credit_b+1; end
  if(a.transmit_controller_state && mode) begin
   if(credit_a != 1 || a.tas_input !== expected_a) $fatal(1,"A invalid TAS response");
   credit_a=credit_a-1; replies_a=replies_a+1;
  end
  if(b.transmit_controller_state && mode) begin
   if(credit_b != 1 || b.tas_input !== expected_b) $fatal(1,"B invalid TAS response");
   credit_b=credit_b-1; replies_b=replies_b+1;
  end
 end
end
task tick;
 input integer n;
 begin repeat(n) @(negedge clk); end
endtask
task rst;
 begin reset=1; tick(4); reset=0; tick(10); end
endtask
task put;
 input [31:0] value;
 begin data=value; wr=1; tick(1); wr=0; tick(3); end
endtask
// Drive complete console commands through the real filter and receiver.
task command_a;
 input [7:0] value;
 integer i;
 begin
  for(i=7;i>=0;i=i-1) begin
   drive_a=1; if(value[i]) tick(50); else tick(150);
   drive_a=0; if(value[i]) tick(150); else tick(50);
  end
  drive_a=1; tick(50); drive_a=0; tick(15);
 end
endtask
task command_b;
 integer i;
 begin
  for(i=7;i>=0;i=i-1) begin
   drive_b=1; if(i==0) tick(50); else tick(150);
   drive_b=0; if(i==0) tick(150); else tick(50);
  end
  drive_b=1; tick(50); drive_b=0; tick(15);
 end
endtask
task silent_a;
 integer i;
 begin
  for(i=0;i<1000;i=i+1) begin
   if(a.transmit_controller_state === 1'b1 || a.direction_output !== 1'b0)
    $fatal(1,"underrun drove a response");
   tick(1);
  end
 end
endtask
integer before_reads, before_replies, i;
initial begin
 tick(10); gsr=1; tick(10);
 // Empty startup must fail-stop, with the line released and no dequeue.
 command_a(8'h01); silent_a;
 if(!fault_a || reads_a!=0 || replies_a!=0) $fatal(1,"empty startup not latched");
 put(32'hdeadbeef); command_a(8'h01); silent_a;
 if(reads_a!=0) $fatal(1,"refill silently recovered");
 $display("PASS empty startup, starvation and refill fail-stop");
 // Reset discards both queued and cached state; fresh data recovers the run.
 rst; if(fault_a || a.tas_input!==0) $fatal(1,"reset did not clear fault/cache");
 expected_a=32'h89abcdef; put(expected_a); command_a(8'h01); tick(7000);
 if(replies_a!=1 || reads_a!=1) $fatal(1,"fresh frame not consumed");
 command_a(8'h01); silent_a;
 if(!fault_a || replies_a!=1) $fatal(1,"drain repeated stale frame");
 $display("PASS drain-to-empty and reset/refill recovery");
 // Simultaneous write on an empty poll decision cannot authorize this response.
 rst; command_a(8'h01); wait(a.state==2 && a.delay_2us==0);
 @(negedge clk); wr=1; data=32'h01020304; tick(1); wr=0;
 silent_a; if(!fault_a || replies_a!=1) $fatal(1,"empty write bypassed policy");
 $display("PASS simultaneous empty poll/write");
 // Reset at each RAM pipeline stage must suppress the pending response.
 for(i=5;i<=6;i=i+1) begin
  rst; put(32'h11111111); command_a(8'h01); wait(a.state==i);
  @(negedge clk); reset=1; tick(2); reset=0; tick(10); silent_a;
  if(a.tas_input!==0 || fault_a) $fatal(1,"reset pipeline retained state");
 end
 $display("PASS reset adjacent to dequeue and RAM capture");
 // Reset during an accepted transmission lets that response finish with its word.
 rst; expected_a=32'h87654321; put(expected_a); command_a(8'h01);
 wait(a.is_transmitting_controller_state); tick(100); reset=1; tick(2); reset=0;
 if(a.tas_input!==expected_a) $fatal(1,"reset tore active response");
 tick(7000); if(a.tas_input!==0) $fatal(1,"reset TX cache not cleared");
 $display("PASS reset during accepted response");
 // Full slow console blocks shared replenishment while the faster console drains.
 rst; expected_a=32'h55aa55aa; expected_b=expected_a;
 for(i=0;i<1024;i=i+1) put(expected_a);
 if(request_a || request_b) $fatal(1,"queues not full");
 for(i=0;i<1024;i=i+1) begin command_a(8'h01); tick(7000); end
 before_replies=replies_a; before_reads=reads_a;
 command_a(8'h01); silent_a;
 if(!fault_a || fault_b || request_b || reads_a!=before_reads || replies_a!=before_replies)
  $fatal(1,"unequal rate starvation not isolated");
 command_b; tick(7000);
 if(replies_b!=1) $fatal(1,"slow console lost queued frame");
 $display("PASS unequal console rates with slow full queue");
 // Passthrough and identity still respond while TAS is faulted.
 mode=0; command_a(8'h01); tick(150);
 if(a.state!=3) $fatal(1,"passthrough blocked by TAS fault");
 tick(7000); mode=1; command_a(8'h00); tick(150);
 if(a.state!=4) $fatal(1,"identity blocked by TAS fault");
 tick(7000);
 $display("PASS passthrough and identity; reads A=%0d B=%0d replies A=%0d B=%0d",reads_a,reads_b,replies_a,replies_b);
 // A passthrough poll must not authorize an empty TAS response after a mode change.
 rst; mode=0; command_a(8'h01); wait(a.state==5);
 @(negedge clk); mode=1; silent_a;
 if(!fault_a) $fatal(1,"mode change bypassed empty TAS policy");
 $display("PASS TAS selected during empty passthrough RAM wait");
 $finish;
end
// Bound deadlocks in both protocol and RAM paths.
initial begin #300000000; $fatal(1,"test timeout"); end
endmodule
