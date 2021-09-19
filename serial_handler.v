// Ownasaurus
// Module to handle the serial communication, including buffering

module serial_handler #(parameter NUM_CONSOLES=1) (
    input clk,
	input [NUM_CONSOLES-1:0] request_frame,
    input rx_uart,
	output tx_uart,
	output reg queue_WrEn=1'b0,
	output reg [31:0] received_frame_data=32'b0,
	output reg n64_controller_reset=1'b0
);

// serial send buffer
wire send_buffer_empty, send_buffer_full;
reg serial_send_fifo_rden, serial_send_fifo_wren;
localparam queue_rst=1'b0;
wire [6:0] fifo_size;
wire [7:0] fifo_get_byte;
reg [7:0] fifo_input;

queue_64 serial_send_fifo(
	.Clock(clk),
	.Data(fifo_input), // 8 bits
	.RdEn(serial_send_fifo_rden),
	.Reset(queue_rst),
	.WrEn(serial_send_fifo_wren),
	.Empty(send_buffer_empty),
	.Full(send_buffer_full),
	.Q(fifo_get_byte), // 8 bits
	.WCNT(fifo_size) // [6:0] count of items in FIFO
);

// serial processing-------------------------------------
localparam IDLE = 0, AFTER_SEND = 1, RESET_1 = 2, RESET_2 = 3, SETUP_1 = 4, SETUP_2 = 5, SETUP_3 = 6, SETUP_4 = 7, SETUP_5 = 8, SETUP_6 = 9, SETUP_7 = 10;
localparam RECEIVE_A_1 = 11, RECEIVE_A_2 = 12, RECEIVE_A_3 = 13, RECEIVE_A_4 = 14, RECEIVE_A_5 = 15, POWER_1 = 16, BULK_1 = 17, BULK_2 = 18;
reg [4:0] state;

// USB UART STUFF
localparam serial_rst=1'b1;
reg [7:0] byte;
wire active, done;
reg send;
reg [16:0] send_timeout;
UART_TX serial_send(
   .i_Rst_L(serial_rst), // keep high for it to work
   .i_Clock(clk), // 50MHz clk
   .i_TX_DV(send), // wont send unless 1
   .i_TX_Byte(byte), // the byte to send
   .o_TX_Active(active), // is this actively sending?
   .o_TX_Serial(tx_uart), // the serial TX line from the FPGA's perspective
   .o_TX_Done(done) // is it done?
);

wire [7:0] new_byte;
wire received;
UART_RX serial_receive(
   .i_Rst_L(serial_rst),
   .i_Clock(clk),
   .i_RX_Serial(rx_uart),
   .o_RX_DV(received),
   .o_RX_Byte(new_byte)
);

integer w;

initial begin
   send = 0;
   state = 0;
   byte = 8'h00;
   
   serial_send_fifo_rden = 1'b0;
   serial_send_fifo_wren = 1'b0;
   
   send_timeout = 0;
end

// Handle dequeuing/reading from serial FIFO into serial UART_TX
localparam serial_send_IDLE=0, serial_send_SENDING1=1, serial_send_SENDING2=2, serial_send_CLEANUP=3;
reg [1:0] serial_send_SM=2'b00;

// adds bytes to outgoing serial FIFO
localparam send_IDLE=0, send_CLEANUP=1;
reg send_SM=0;
reg [7:0] byte_to_send=8'h00;
reg respond_to_serial_TX=1'b0;
reg new_data_request_lock=1'b0;
reg prebuffer_done=1'b0;
reg [32:0] frame_counter=32'h00000000;

// Process commands received on the serial RX line
always @(posedge clk) begin
	case(serial_send_SM)
		serial_send_IDLE: begin
			if(!send_buffer_empty && !active) begin // send queue has an element waiting, and not currently sending a byte
				serial_send_fifo_rden <= 1'b1;
				serial_send_SM <= serial_send_SENDING1;
			end
		end
		serial_send_SENDING1: begin
			serial_send_fifo_rden <= 1'b0;
			serial_send_SM <= serial_send_SENDING2;
		end
		serial_send_SENDING2: begin
			send <= 1;
			byte <= fifo_get_byte;
			serial_send_SM <= serial_send_CLEANUP;
		end
		serial_send_CLEANUP: begin
			send <= 0;
			serial_send_SM <= serial_send_IDLE;
		end
	endcase
	
	// when all consoles are no longer requesting more data for the first time, then the prebuffer is complete!
	if((|request_frame) == 0) begin
		prebuffer_done <= 1'b1;
	end
	
	case(send_SM)
		send_IDLE: begin
			if(respond_to_serial_TX) begin // takes priority
				fifo_input <= byte_to_send; // whatever the serial SM wants to send
				serial_send_fifo_wren <= 1'b1;
				send_SM <= send_CLEANUP;
			end else if(prebuffer_done && &request_frame && !new_data_request_lock) begin
				// delay_frame_request is a delay to make sure it doesn't read again too quickly until the consoles have time to lower their not_full pulses
				fifo_input <= 8'd65; // capital A
				serial_send_fifo_wren <= 1'b1;
				new_data_request_lock <= 1'b1; // make sure only one request is pending at once
				send_SM <= send_CLEANUP;
			end
		end
		send_CLEANUP: begin
			serial_send_fifo_wren <= 1'b0;
			send_SM <= send_IDLE;
		end
	endcase
	
	if(received) begin //  should only be high for one cycle per command
		case(state)
			IDLE: begin
				case(new_byte)
					8'd82: begin // 'R' -- reset
						byte_to_send <= 8'h01; // first byte of reset response
						frame_counter <= 32'h00000000;
						n64_controller_reset <= 1'b1;
						prebuffer_done <= 1'b0;
						respond_to_serial_TX <= 1'b1;
						state <= RESET_1;
					end
					8'd83: begin // 'S' -- setup //S A M 0x00 0x00
						state <= SETUP_1;
					end
					8'd65: begin // 'A' -- receive data for run A
						state <= RECEIVE_A_1;
					end
					8'hAA: begin // ping
						byte_to_send <= 8'h55; // pong response
						respond_to_serial_TX <= 1'b1;
						state <= AFTER_SEND;
					end
					8'd80: begin // 'P' -- power control
						// no need to do anything with this byte
						state <= POWER_1;
					end
					8'd81: begin // 'Q' -- bulk data mode
						// no need to do anything with this byte
						state <= BULK_1;
					end
					default: begin
						byte_to_send <= 8'hFF; // command not recognized
						respond_to_serial_TX <= 1'b1;
						state <= AFTER_SEND;
					end
				endcase
			end
			BULK_1: begin
				// no need to process the second byte
				state <= BULK_2;
			end
			BULK_2: begin
				// no need to process the third byte
				state <= IDLE;
			end
			POWER_1: begin
				// no need to process the second byte
				state <= IDLE;
			end
			RECEIVE_A_1: begin // 1st byte received
				received_frame_data[31:24] <= new_byte;
				state <= RECEIVE_A_2;
			end
			RECEIVE_A_2: begin // 2nd byte received
				received_frame_data[23:16] <= new_byte;
				state <= RECEIVE_A_3;
			end
			RECEIVE_A_3: begin // 3rd byte received
				received_frame_data[15:8] <= new_byte;
				state <= RECEIVE_A_4;
			end
			RECEIVE_A_4: begin // 4th byte received
				received_frame_data[7:0] <= new_byte;
				if((&request_frame) == 0) begin // buffer is full in at least one console. send error instead of storing
					byte_to_send <= 8'hB0; // buffer overrun
					respond_to_serial_TX <= 1'b1;
					state <= AFTER_SEND;
				end else begin
					queue_WrEn <= 1'b1; // write data to n64 buffers
					frame_counter <= frame_counter + 1'b1;
					state <= RECEIVE_A_5;
				end
			end
			SETUP_1: begin
				if(new_byte == 8'd65) begin // run 'A'
					state <= SETUP_2;
				end else begin
					byte_to_send <= 8'hFE; // run number/letter not supported
					respond_to_serial_TX <= 1'b1;
					state <= AFTER_SEND;
				end
			end
			SETUP_2: begin
				if(new_byte == 8'd77) begin // run 'M'
					state <= SETUP_3;
				end else begin
				end
			end
			SETUP_3: begin // Controller byte
				if(new_byte == 8'h80) begin // 1 player, 1 data line
					state <= SETUP_4;
				end else begin
				end
			end
			SETUP_4: begin // Settings byte
				// can ignore for N64
				byte_to_send <= 8'h01; // first byte of setup response
				respond_to_serial_TX <= 1'b1;
				state <= SETUP_5;
			end
		endcase
	end else begin // did not receive new byte; "post-processing"
		case(state)
			AFTER_SEND: begin
				respond_to_serial_TX <= 1'b0;
				state <= IDLE;
			end
			RESET_1: begin
				respond_to_serial_TX <= 1'b0;
				n64_controller_reset <= 1'b0;
				send_timeout <= 0;
				state <= RESET_2;
			end
			RESET_2: begin
				if(done) begin // done sending the 0x01, now send the 'R'
					byte_to_send <= 8'd82; // second byte of reset response
					respond_to_serial_TX <= 1'b1;
					state <= AFTER_SEND;
				end else if(send_timeout >= 40000) begin // timed out
					state <= IDLE;
				end else begin
					send_timeout <= send_timeout + 1'b1;
				end
			end
			SETUP_5: begin
				respond_to_serial_TX <= 1'b0;
				state <= SETUP_6;
			end
			SETUP_6: begin
				if(done) begin // done sending the 0x01, now send the 'S'
					byte_to_send <= 8'd83; // second byte of setup response
					respond_to_serial_TX <= 1'b1;
					state <= AFTER_SEND;
				end
			end
			RECEIVE_A_5: begin
				queue_WrEn <= 1'b0;
				new_data_request_lock <= 1'b0;
				state <= IDLE;
			end
		endcase
	end
end

endmodule
