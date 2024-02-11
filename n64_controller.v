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
	output next_frame_request
);

wire queue_full, queue_empty;
wire [31:0] queue_output;
reg [31:0] tas_input=32'h00000000;
reg queue_RdEn=1'b0;
reg firstFrame=1'b1;

// 1024-frame input buffer
queue_1024 run_data(
	.Clock(sys_clk),
	.RdEn(queue_RdEn),
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

wire direction_output = (state <= read) ? 1'b0 : 1'b1;
wire out_data = (state == write_controller) ? n64_datac : n64_datai;
assign n64d = direction_output ? out_data : 1'bz;

always @(posedge sys_clk) begin
	case(state)
		idle: begin
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
						queue_RdEn <= 1'b1;
						state <= buffer_read_1;
						
						
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
			queue_RdEn <= 1'b0;
			state <= buffer_read_2; // eat another clock cycle before reading output port
		end
		buffer_read_2: begin
			tas_input <= queue_output;// now output data should be ready
			transmit_controller_state <= 1;
			state <= write_controller;
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
end

endmodule
