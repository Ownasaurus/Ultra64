`timescale 1ns/1ps
// N07: exercise the new host query with the actual UART and generated serial FIFO.
module n07_status_tb;
reg clk=0;
always #10 clk=~clk;
reg gsr=0;
GSR GSR_INST(.GSR(gsr));
PUR PUR_INST(.PUR(1'b1));
reg rx=1;
reg [1:0] fault=0, request=2'b11;
wire tx, wr, reset;
wire [31:0] data;
serial_handler #(.NUM_CONSOLES(2)) dut(.clk(clk), .request_frame(request),
 .tas_underrun(fault), .rx_uart(rx), .tx_uart(tx), .queue_WrEn(wr),
 .received_frame_data(data), .n64_controller_reset(reset));
integer responses=0;
reg [7:0] expected=0;
// Decode the actual outgoing UART status byte, rather than only its enqueue pulse.
always @(negedge tx) begin : decode
 integer i;
 reg [7:0] value;
 repeat(651) @(negedge clk);
 for(i=0;i<8;i=i+1) begin
  value[i]=tx;
  repeat(434) @(negedge clk);
 end
 if(tx!==1 || value!==expected) $fatal(1,"bad status UART response %h expected %h",value,expected);
 responses=responses+1;
end
task tick;
 input integer n;
 begin repeat(n) @(negedge clk); end
endtask
task send_u;
 integer i;
 reg [7:0] value;
 begin
  value=8'h55; rx=0; tick(434);
  for(i=0;i<8;i=i+1) begin rx=value[i]; tick(434); end
  rx=1; tick(434);
 end
endtask
initial begin
 tick(10); gsr=1; tick(10);
 expected=0; send_u; tick(5000);
 if(responses!=1) $fatal(1,"missing healthy status");
 fault=2'b10; expected=8'hb1; send_u; tick(5000);
 if(responses!=2) $fatal(1,"missing second-console fault");
 send_u; tick(5000);
 if(responses!=3 || fault!=2'b10) $fatal(1,"status read cleared fault");
 $display("PASS UART U healthy, aggregate fault and non-clearing status");
 // Inject receive-valid at the parser boundary on producer cleanup; it must persist.
 force dut.send_SM=1'b1;
 force dut.received=1'b1;
 force dut.new_byte=8'h55;
 tick(1);
 release dut.received; release dut.new_byte;
 force dut.send_buffer_full=1'b1;
 release dut.send_SM;
 tick(10);
 if(!dut.underrun_status_pending) $fatal(1,"status lost during cleanup/full");
 fault=0; // The pending reply must retain its query-time snapshot.
 release dut.send_buffer_full;
 tick(5000);
 if(responses!=4) $fatal(1,"pending status did not recover");
 expected=0; send_u; tick(5000);
 if(responses!=5) $fatal(1,"status did not recover after fault clear");
 $display("PASS status retained across cleanup/full, snapshot and fault-clear recovery");
 $finish;
end
initial begin #2000000; $fatal(1,"status test timeout"); end
endmodule
