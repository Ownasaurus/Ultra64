// Ownasaurus
// Designed to transmit a byte of data according to n64's protocol

module n64_transmit_byte(
	input sys_clk,
	input trigger,
	input [7:0] byte,
	output n64d,
	output reg transmitting
);

localparam bit_zero = 2'b00, bit_one = 2'b01;
reg [1:0] bit_type;

localparam idle=0, wait1_sending_bit1=1, wait2_sending_bit1=2, wait1_sending_bit2=3, wait2_sending_bit2=4, wait1_sending_bit3=5, wait2_sending_bit3=6, wait1_sending_bit4=7, wait2_sending_bit4=8, wait1_sending_bit5=9, wait2_sending_bit5=10, wait1_sending_bit6=11, wait2_sending_bit6=12, wait1_sending_bit7=13, wait2_sending_bit7=14, wait1_sending_bit8=15, wait2_sending_bit8=16;
reg [4:0] state;

reg send_bit_trigger;
wire bit_transmitting;

n64_transmit_bit send_bit(.sys_clk(sys_clk), .trigger(send_bit_trigger), .digit(bit_type), .n64d(n64d), .transmitting(bit_transmitting));

initial begin
	send_bit_trigger = 0;
	state = 0;
    transmitting = 0;
	bit_type = 2'b00;
end

always @(posedge sys_clk) begin
    if(trigger) begin
        transmitting <= 1'b1;
    end

    case(state)
        idle: begin
            if(transmitting) begin
                case(byte[7])
                    0: begin
                        bit_type <= bit_zero;
                    end
                    1: begin
                        bit_type <= bit_one;
                    end
                endcase
                send_bit_trigger <= 1;
                state <= wait1_sending_bit1;
            end
        end
        wait1_sending_bit1: begin
            send_bit_trigger <= 0;
            state <= wait2_sending_bit1;
        end
        wait2_sending_bit1: begin
            if(!bit_transmitting) begin
                case(byte[6])
                    0: begin
                        bit_type <= bit_zero;
                    end
                    1: begin
                        bit_type <= bit_one;
                    end
                endcase
                send_bit_trigger <= 1;
            	state <= wait1_sending_bit2;
        	end
        end
        wait1_sending_bit2: begin
            send_bit_trigger <= 0;
            state <= wait2_sending_bit2;
        end
        wait2_sending_bit2: begin
            if(!bit_transmitting) begin
                case(byte[5])
                    0: begin
                        bit_type <= bit_zero;
                    end
                    1: begin
                        bit_type <= bit_one;
                    end
                endcase
                send_bit_trigger <= 1;
            	state <= wait1_sending_bit3;
        	end
        end
        wait1_sending_bit3: begin
            send_bit_trigger <= 0;
            state <= wait2_sending_bit3;
        end
        wait2_sending_bit3: begin
            if(!bit_transmitting) begin
                case(byte[4])
                    0: begin
                        bit_type <= bit_zero;
                    end
                    1: begin
                        bit_type <= bit_one;
                    end
                endcase
                send_bit_trigger <= 1;
            	state <= wait1_sending_bit4;
        	end
        end
        wait1_sending_bit4: begin
            send_bit_trigger <= 0;
            state <= wait2_sending_bit4;
        end
        wait2_sending_bit4: begin
            if(!bit_transmitting) begin
                case(byte[3])
                    0: begin
                        bit_type <= bit_zero;
                    end
                    1: begin
                        bit_type <= bit_one;
                    end
                endcase
                send_bit_trigger <= 1;
            	state <= wait1_sending_bit5;
        	end
        end
        wait1_sending_bit5: begin
            send_bit_trigger <= 0;
            state <= wait2_sending_bit5;
        end
        wait2_sending_bit5: begin
            if(!bit_transmitting) begin
                case(byte[2])
                    0: begin
                        bit_type <= bit_zero;
                    end
                    1: begin
                        bit_type <= bit_one;
                    end
                endcase
                send_bit_trigger <= 1;
            	state <= wait1_sending_bit6;
        	end
        end
        wait1_sending_bit6: begin
            send_bit_trigger <= 0;
            state <= wait2_sending_bit6;
        end
        wait2_sending_bit6: begin
            if(!bit_transmitting) begin
                case(byte[1])
                    0: begin
                        bit_type <= bit_zero;
                    end
                    1: begin
                        bit_type <= bit_one;
                    end
                endcase
                send_bit_trigger <= 1;
            	state <= wait1_sending_bit7;
        	end
        end
        wait1_sending_bit7: begin
            send_bit_trigger <= 0;
            state <= wait2_sending_bit7;
        end
        wait2_sending_bit7: begin
            if(!bit_transmitting) begin
                case(byte[0])
                    0: begin
                        bit_type <= bit_zero;
                    end
                    1: begin
                        bit_type <= bit_one;
                    end
                endcase
                send_bit_trigger <= 1;
            	state <= wait1_sending_bit8;
        	end
        end
        wait1_sending_bit8: begin
            send_bit_trigger <= 0;
            state <= wait2_sending_bit8;
        end
        wait2_sending_bit8: begin
            if(!bit_transmitting) begin
                transmitting <= 1'b0;
            	state <= idle;
        	end
        end
    endcase
end

endmodule
