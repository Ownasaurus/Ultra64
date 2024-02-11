// Ownasaurus
// TAS replay device to control up to 64 N64s at once. No kappa.
// Designed to work on the LFE5UM5G-85F-EVN development board by Lattice

// NUM_CONSOLES is the maximum number of N64 consoles to output to

module top #(parameter NUM_CONSOLES=4) (
    input clk12,
    output [7:0] led,
    inout n64real,
    inout [NUM_CONSOLES-1:0] n64,
    output tx_uart,
    input rx_uart,
    input button,
    output [2:0] debug
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
      n64_controller player_i (
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

// deal with inactive consoles. let them time out
reg [NUM_CONSOLES-1:0] ready_override;
reg at_least_one_ready;
reg [31:0] console_timeout;

initial begin
    ready_override = 0;
    at_least_one_ready = 0;
    console_timeout = 0;
end

// logic for handling timeout timer
// TODO: might be race condition here
always @(posedge clk) begin
	if(!at_least_one_ready && !queueWrEn) begin
		if(|ready_for_next_frame) begin
			at_least_one_ready <= 1'b1;
		end
	end else begin
		if(queueWrEn) begin // data being given to all consoles. can reset logic
			// TODO: MIGHT NEED DELAY HERE
			console_timeout <= 1'b0;
			at_least_one_ready <= 1'b0;
		end
		console_timeout <= console_timeout + 1'b1;
	end
end

// actual timeout checks
generate
    genvar i;
    for(i=0; i<NUM_CONSOLES;i=i+1) begin
        assign consoles_ready[i] = ready_override[i] ? 1'b1 : ready_for_next_frame[i];

	always @(posedge clk) begin
		if(console_timeout >= 50_000_000) begin // 10 seconds without advancing
			if(!ready_for_next_frame[i]) begin // we are the one holding them up!
				ready_override[i] = 1'b1; // so ignore us in the future
			end
		end
	end
    end
endgenerate



// serial handler------------------------------------------
serial_handler #(.NUM_CONSOLES(NUM_CONSOLES)) ftdi (
    .clk(clk),
	.request_frame(ready_override),
    .rx_uart(rx_uart),
	.tx_uart(tx_uart),
	.queue_WrEn(queueWrEn),
	.received_frame_data(received_frame_data),
	.n64_controller_reset(n64_controller_reset)
);

endmodule

