// Ownasaurus
// Designed to transmit a proper response to an n64 conroller button state request

module n64_transmit_controller_state(
	input sys_clk,
	input trigger,
    input [31:0] data,
	output n64d,
	output reg transmitting
);

wire n64_datab, n64_datas;

reg [7:0] byte;

localparam bit_stop = 2'b11;

localparam idle=0, wait1_sending_byte1=1, wait2_sending_byte1=2, wait1_sending_byte2=3, wait2_sending_byte2=4, wait1_sending_byte3=5, wait2_sending_byte3=6, wait1_sending_byte4=7, wait2_sending_byte4=8, wait1_sending_stop=9, wait2_sending_stop=10;
reg [3:0] state;

reg send_byte_trigger;
reg send_stop_trigger;
wire byte_transmitting;
wire stop_transmitting;

n64_transmit_byte send_byte(.sys_clk(sys_clk), .trigger(send_byte_trigger), .byte(byte), .n64d(n64_datab), .transmitting(byte_transmitting));
n64_transmit_bit send_stop(.sys_clk(sys_clk), .trigger(send_stop_trigger), .digit(bit_stop), .n64d(n64_datas), .transmitting(stop_transmitting));

initial begin
	send_stop_trigger = 0;
	send_byte_trigger = 0;
    byte = 0;
    state = 0;
    transmitting = 0;
end

assign n64d = (state <= wait2_sending_byte4) ? n64_datab : n64_datas;

always @(posedge sys_clk) begin
    if(trigger) begin
        transmitting <= 1'b1;
    end

    case(state)
        idle: begin
            if(transmitting) begin
        		byte <= data[31:24];
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
        		byte <= data[23:16];
        		send_byte_trigger <= 1'b1;
        		state <= wait1_sending_byte2;
        	end
        end
        wait1_sending_byte2: begin
        	send_byte_trigger <= 1'b0;
        	state <= wait2_sending_byte2;
        end
        wait2_sending_byte2: begin
        	if(!byte_transmitting) begin
        		byte <= data[15:8];
        		send_byte_trigger <= 1'b1;
        		state <= wait1_sending_byte3;
        	end
        end
        wait1_sending_byte3: begin
        	send_byte_trigger <= 1'b0;
        	state <= wait2_sending_byte3;
        end
        wait2_sending_byte3: begin
        	if(!byte_transmitting) begin
                byte <= data[7:0];
        		send_byte_trigger <= 1'b1;
        		state <= wait1_sending_byte4;
        	end
        end
        wait1_sending_byte4: begin
            send_byte_trigger <= 1'b0;
            state <= wait2_sending_byte4;
        end
        wait2_sending_byte4: begin
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
