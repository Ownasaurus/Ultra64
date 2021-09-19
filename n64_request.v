// Ownasaurus
// Designed to write a request for controller state or controller identity

module n64_request(
	input sys_clk,
	input trigger,
    input request_type,
	output n64d,
	output reg transmitting
);

wire n64_datab, n64_datas;

// let request_type of 1 request controller state
// let request_type of 0 request identtiy

localparam [7:0] byte1 = 8'b00000001; // 0x01, request controller state
localparam [7:0] byte2 = 8'b00000000; // 0x00, request controller identity
reg [7:0] byte;

localparam bit_console_stop = 2'b10;

localparam idle=0, wait1_sending_byte1=1, wait2_sending_byte1=2, wait1_sending_stop=3, wait2_sending_stop=4;
reg [2:0] state;

reg send_byte_trigger;
reg send_stop_trigger;
wire byte_transmitting;
wire stop_transmitting;

n64_transmit_byte send_byte(.sys_clk(sys_clk), .trigger(send_byte_trigger), .byte(byte), .n64d(n64_datab), .transmitting(byte_transmitting));
n64_transmit_bit send_stop(.sys_clk(sys_clk), .trigger(send_stop_trigger), .digit(bit_console_stop), .n64d(n64_datas), .transmitting(stop_transmitting));

initial begin
	send_stop_trigger = 0;
	send_byte_trigger = 0;
    byte = 0;
    state = 0;
    transmitting = 0;
end

assign n64d = (state <= wait2_sending_byte1) ? n64_datab : n64_datas;

always @(posedge sys_clk) begin
    if(trigger) begin
        transmitting <= 1'b1;
    end

    case(state)
        idle: begin
            if(transmitting) begin
                if(request_type) begin
                    byte <= byte1; 
                end else begin
                    byte <= byte2;
                end
        		send_byte_trigger <= 1'b1;
        		state <= wait1_sending_byte1;
    		end
        end
        wait1_sending_byte1: begin
        	send_byte_trigger <= 1'b0;
        	state <= wait2_sending_byte1;
        end
        wait2_sending_byte1: begin
        	if(!byte_transmitting) begin
        		send_stop_trigger <= 1'b1;
        		state <= wait1_sending_stop;
        	end
        end
        wait1_sending_stop: begin
        	send_stop_trigger <= 1'b0;
        	state <= wait2_sending_stop;
        end
        wait2_sending_stop: begin
        	if(!stop_transmitting) begin
                transmitting <= 1'b0;
        		state <= idle;
        	end
        end
    endcase
end

endmodule
