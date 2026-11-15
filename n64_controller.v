// Ownasaurus
// Designed to simulate a N64/GC controller
// Has one bidirectional data line
// Assumes 50MHz sys_clk

module n64_controller(
	input sys_clk,
	inout n64d,
	input [31:0] real_controller_data,
	input input_mode,
	input queue_WrEn,
	input [31:0] queue_data,
	input n64_controller_reset,
	output next_frame_request,
	// N07: sticky playback fault, cleared only by the host's FIFO reset.
	output reg tas_underrun=1'b0
);

wire queue_full, queue_empty;
wire [31:0] queue_output;
reg [31:0] tas_input=32'h00000000;
reg queue_RdEn=1'b0;
// N07: qualify the actual dequeue edge and remember validity across RAM latency.
wire queue_read_enable = queue_RdEn && !queue_empty && !n64_controller_reset;
reg frame_valid=1'b0;
reg firstFrame=1'b1;

// 1024-frame input buffer
queue_1024 run_data(
	.Clock(sys_clk),
	.RdEn(queue_read_enable), // N07: never request a rejected/reset read.
	.Reset(n64_controller_reset),
	.WrEn(queue_WrEn),
	.Data(queue_data),
	.Empty(queue_empty),
	.Full(queue_full),
	.Q(queue_output)
);

assign next_frame_request = !queue_full;

wire [31:0] input_data;

assign input_data = input_mode ? tas_input : real_controller_data;


localparam idle=0, start_read=1, read=2, write_controller=3, write_ident=4, buffer_read_1=5, buffer_read_2=6;
reg [2:0] state;

reg transmit_identity, transmit_controller_state, receive_command;
wire is_transmitting_identity, is_transmitting_controller_state, is_receiving_command;

wire [7:0] command;
wire n64_datai, n64_datac;

wire n64d_f;
glitch_filter data_filter(.sys_clk(sys_clk), .line_in(n64d), .line_out(n64d_f));

n64_transmit_identity identity_machine(.sys_clk(sys_clk), .trigger(transmit_identity), .n64d(n64_datai), .transmitting(is_transmitting_identity));
n64_transmit_controller_state controller_state_machine(.sys_clk(sys_clk), .trigger(transmit_controller_state), .data(input_data), .n64d(n64_datac), .transmitting(is_transmitting_controller_state));
n64_receive_command hey_listen_machine(.sys_clk(sys_clk), .trigger(receive_command), .command(command), .n64d(n64d_f), .receiving(is_receiving_command));

reg [6:0] delay_2us;

initial begin
	state = 0;
	delay_2us = 100;
end

// N07: an underrun (including RAM wait states) must leave the console bus released.
wire direction_output = (state == write_controller || state == write_ident);
wire out_data = (state == write_controller) ? n64_datac : n64_datai;
assign n64d = direction_output ? out_data : 1'bz;

always @(posedge sys_clk) begin
	case(state)
		idle: begin
			// N07: discard cached playback after a completed response, including reset during TX.
			tas_input <= 32'b0;
			frame_valid <= 1'b0;
			delay_2us <= 100;
			receive_command <= 1;
			state <= start_read;
		end
		start_read: begin
			receive_command <= 0;
			state <= read;
		end
		read: begin
			if(!is_receiving_command) begin
				if(command == 8'b00000001) begin // poll request
					if(delay_2us > 0) begin
						delay_2us <= delay_2us - 1'b1;
					end else begin
						// N07: fail-stop on starvation; refilling cannot silently resume a shifted run.
						if(input_mode && (tas_underrun || queue_empty)) begin
							tas_underrun <= 1'b1;
							state <= idle;
						end else begin
							queue_RdEn <= !queue_empty;
							state <= buffer_read_1;
						end
						
						
					end
				end else if (command == 8'b11111111 || command == 8'b00000000) begin
					if(delay_2us > 0) begin
						delay_2us <= delay_2us - 1'b1;
					end else begin
						transmit_identity <= 1;
						state <= write_ident;
					end
				end else begin
					state <= idle;
				end
			end
		end
		buffer_read_1: begin
			// N07: this is the FIFO sampling edge, not the earlier scheduling edge.
			frame_valid <= queue_read_enable;
			if(input_mode && !queue_read_enable) tas_underrun <= 1'b1;
			queue_RdEn <= 1'b0;
			state <= buffer_read_2; // eat another clock cycle before reading output port
		end
		buffer_read_2: begin
			// N07: only a newly accepted read may publish TAS data or trigger its response.
			// N07: also qualify the current mode if it changed during the RAM wait.
			if(!input_mode || (frame_valid && !tas_underrun)) begin
				if(frame_valid) tas_input <= queue_output;
				transmit_controller_state <= 1;
				state <= write_controller;
			end else begin
				tas_underrun <= 1'b1; // N07: a newly selected TAS mode still needs a valid frame.
				state <= idle;
			end
		end
		write_controller: begin
			transmit_controller_state <= 0;
			if(!transmit_controller_state && !is_transmitting_controller_state) begin
				state <= idle;
			end
		end
		write_ident: begin
			transmit_identity <= 0;
			if(!transmit_identity && !is_transmitting_identity) begin
				state <= idle;
			end
		end
	endcase
	// N07: cancel an in-flight dequeue on reset. A response already started finishes
	// with its accepted frame; idle then clears its cache without tearing the response.
	if(n64_controller_reset) begin
		queue_RdEn <= 1'b0;
		frame_valid <= 1'b0;
		tas_underrun <= 1'b0;
		if(state != write_controller && state != write_ident) begin
			tas_input <= 32'b0;
			transmit_controller_state <= 1'b0;
			transmit_identity <= 1'b0;
			receive_command <= 1'b0;
			state <= idle;
		end
	end
end

endmodule
