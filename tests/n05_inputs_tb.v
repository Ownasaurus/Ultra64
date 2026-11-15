`timescale 1ns/1ps
// N05 regression: asynchronous phases, synchronization latency, filter threshold,
// UART baud mismatch/back-to-back frames and N64 decoding through the real filter.
module n05_inputs_tb;
  reg clk = 0;
  always #10 clk = ~clk;
  reg reset_l = 0, rx = 1, pin = 1;
  wire valid, filtered;
  wire [7:0] received, command;
  wire [31:0] controller;
  reg command_trigger = 0, controller_trigger = 0;
  wire command_busy, controller_busy;
  UART_RX uart(reset_l, clk, rx, valid, received);
  glitch_filter filter(clk, pin, filtered);
  n64_receive_command cmd(clk, command_trigger, command, filtered, command_busy);
  n64_receive_controller_data data(clk, controller_trigger, controller, filtered, controller_busy);
  integer count = 0, expected_count = 0;
  reg [7:0] expected;
  always @(negedge clk) if (valid) begin
    if (received !== expected) $fatal(1, "UART got %h expected %h", received, expected);
    count = count + 1;
  end

  task uart_frame;
    input [7:0] value;
    input integer bit_ns;
    integer b;
    begin
      expected = value;
      expected_count = expected_count + 1;
      rx = 0; #(bit_ns);
      for (b=0; b<8; b=b+1) begin rx=value[b]; #(bit_ns); end
      rx=1; #(bit_ns);
      if (count != expected_count) $fatal(1, "UART missing/extra valid");
    end
  endtask

  task n64_bit;
    input value;
    input integer delta;
    integer low_ns;
    begin
      low_ns = (value ? 1000 : 3000) + delta;
      pin=0; #(low_ns); pin=1; #(4000-low_ns);
    end
  endtask

  integer phase, rate, j;
  reg [31:0] word_value = 32'hA55A8101;
  initial begin
    #100; reset_l=1;
    // A raw falling edge must not reach the UART FSM on the first two clocks.
    @(negedge clk); #1; rx=0;
    repeat (2) begin @(posedge clk); #1;
      if (uart.r_SM_Main !== 0) $fatal(1, "UART bypasses two-stage boundary");
    end
    rx=1; #10000;
    if (count != 0) $fatal(1, "Short start produced data");

    // Six differing samples remain necessary after two pipeline clocks.
    @(negedge clk); #1; pin=0;
    repeat (7) begin @(posedge clk); #1;
      if (filtered !== 1) $fatal(1, "Filter changed before pipeline + six samples");
    end
    @(posedge clk); #1;
    if (filtered !== 0) $fatal(1, "Filter latency exceeds eight sampling edges");
    pin=1; #400;
    // Five-sample glitches of either polarity must be suppressed.
    @(negedge clk); #1; pin=0; #100; pin=1; #400;
    if (filtered !== 1) $fatal(1, "Five-sample glitch passed");
    pin=0; #400;
    @(negedge clk); #1; pin=1; #100; pin=0; #400;
    if (filtered !== 0) $fatal(1, "Five-sample high glitch passed");
    pin=1; #400;

    // Sweep both sides of sampling edges and +/- approximately 2% baud error.
    for (phase=1; phase<20; phase=phase+6) begin
      for (rate=8500; rate<=8860; rate=rate+180) begin
        @(negedge clk); #(phase);
        uart_frame(8'h00, rate); uart_frame(8'hFF, rate);
        uart_frame(8'h55, rate); uart_frame(8'hAA, rate);
        uart_frame(8'h81, rate); uart_frame(8'h7E, rate);
        #10000;
      end
    end

    // Both N64 decoders see the synchronized/filtered stream, with edge jitter.
    for (phase=1; phase<20; phase=phase+6) begin
      @(negedge clk); command_trigger=1;
      @(negedge clk); command_trigger=0; #200; #(phase);
      for (j=7; j>=0; j=j-1) n64_bit(j==0, (j%3-1)*20);
      n64_bit(1, 0); #400;
      if (command_busy !== 0 || command !== 8'h01) $fatal(1, "N64 command decode");
      @(negedge clk); controller_trigger=1;
      @(negedge clk); controller_trigger=0; #200; #(phase);
      for (j=31; j>=0; j=j-1) n64_bit(word_value[j], (j%3-1)*20);
      n64_bit(1, 0); #400;
      if (controller_busy !== 0 || controller !== word_value) $fatal(1, "N64 response decode");
    end
    $display("PASS N05: 72 UART frames, 4 N64 commands/responses, latency and glitch checks");
    $finish;
  end
  // Bound failures such as a missed completion instead of hanging validation.
  initial begin #20000000; $fatal(1, "N05 timeout"); end
endmodule
