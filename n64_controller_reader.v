// Ownasaurus
// Designed to poll a N64/GC controller
// Has one bidirectional data line
// Assumes 50MHz sys_clk

module n64_controller_reader(
	input sys_clk,
	inout n64d,
	output reg [31:0] controller_data=32'h00000000
);

localparam idle=0, write_request=1, read_response=2, delay=3;
reg [1:0] state = idle;

reg ask_for_data = 1'b0, get_data = 1'b0;
wire is_asking_for_data, is_receiving_data;

wire n64_datac;

n64_request requester(
	.sys_clk(sys_clk),
	.trigger(ask_for_data),
    .request_type(1'b1), // request data; not identity
	.n64d(n64_datac),
	.transmitting(is_asking_for_data)
);

wire n64d_f;
glitch_filter data_filter(.sys_clk(sys_clk), .line_in(n64d), .line_out(n64d_f));

wire [31:0] data_received;
n64_receive_controller_data receiver(
	.sys_clk(sys_clk),
	.trigger(get_data),
    .controller_data(data_received),
	.n64d(n64d_f),
	.receiving(is_receiving_data)
);

reg direction_output = 1'b0;
assign n64d = direction_output ? n64_datac : 1'bz;
reg [19:0] delay_16ms = 800000;

always @(posedge sys_clk) begin
	case(state)
		idle: begin
			delay_16ms <= 800000;
			direction_output <= 1'b1;
			ask_for_data <= 1'b1;
			state <= write_request;
		end
		write_request: begin
			ask_for_data <= 1'b0;
			if(!ask_for_data && !is_asking_for_data) begin // done sending request
				direction_output <= 1'b0;
				get_data <= 1'b1;
				state <= read_response;
			end
		end
		read_response: begin
			get_data <= 1'b0;
			if(!get_data && !is_receiving_data) begin // done receiving response
				controller_data <= data_received; // lock in the data in the output register
				state <= delay;
			end
		end
		delay: begin
			if(delay_16ms == 0) begin
				state <= idle;
			end else begin
				delay_16ms <= delay_16ms - 1'b1;
			end
		end
	endcase
end

endmodule
