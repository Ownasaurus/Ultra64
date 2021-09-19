// Ownasaurus
// TAS replay device to control up to 64 N64s at once. No kappa.
// Designed to work on the LFE5UM5G-85F-EVN development board by Lattice

// NUM_CONSOLES is the maximum number of N64 consoles to output to

module top #(parameter NUM_CONSOLES=9) (
    input clk12,
	output [7:0] led,
    inout n64real,
    inout [NUM_CONSOLES-1:0] n64,
    output tx_uart,
    input rx_uart,
	input button
);

// set up 50MHz to use as base clk ----------------------
wire clk;
pll_12_50 pll(.clki(clk12), .clko(clk));

// set up N64 consoles ----------------------------------
wire [31:0] real_controller_data;
wire [NUM_CONSOLES-1:0] ready_for_next_frame;
wire queueWrEn;
wire [31:0] received_frame_data;
wire n64_controller_reset;

reg input_mode;

generate
   genvar i;
   for(i=0; i<NUM_CONSOLES;i=i+1) begin
      n64_controller #(.NUM_CONSOLES(NUM_CONSOLES)) player_i (
		.sys_clk(clk),
		.n64d(n64[i]),
		.real_controller_data(real_controller_data),
		.input_mode(input_mode),
		.queue_WrEn(queueWrEn),
		.queue_data(received_frame_data),
		.next_frame_request(ready_for_next_frame[i]),
		.n64_controller_reset(n64_controller_reset)
		);
   end
endgenerate

// read a real N64 controller----------------------------
n64_controller_reader reader(
   .sys_clk(clk),
   .n64d(n64real),
   .controller_data(real_controller_data)
);


// toggle TAS mode vs passthrough mode-------------------
wire button_f;
reg debounce;
glitch_filter data_filter(.sys_clk(clk), .line_in(button), .line_out(button_f));

always @(posedge clk) begin
	if(!button_f && !debounce) begin
		debounce <= 1'b1;
		input_mode <= !input_mode;
	end else if(button_f) begin
		debounce <= 1'b0;
	end
end

initial begin
   input_mode = 1'b1;
   debounce = 1'b0;
end

// turn off all those darn bright LEDs!
assign led[6:0] = 7'b1111111;
assign led[7] = input_mode;

// serial handler------------------------------------------
serial_handler #(.NUM_CONSOLES(NUM_CONSOLES)) ftdi (
    .clk(clk),
	.request_frame(ready_for_next_frame),
    .rx_uart(rx_uart),
	.tx_uart(tx_uart),
	.queue_WrEn(queueWrEn),
	.received_frame_data(received_frame_data),
	.n64_controller_reset(n64_controller_reset)
);

endmodule
