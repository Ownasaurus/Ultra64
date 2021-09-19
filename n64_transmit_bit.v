// Ownasaurus
// Designed to turn an input signal into a pulse that fits the N64/GC protocol
// Assumes 50MHz sys_clk

module n64_transmit_bit(
	input sys_clk,
	input trigger,
	input[1:0] digit,
	output reg n64d,
	output reg transmitting
);

integer clk_cnt;

localparam one_us = 50;
localparam two_us = 100;
localparam three_us = 150;
localparam four_us = 200;

initial begin
	n64d = 1'b1;
	transmitting = 1'b0;
	clk_cnt = 0;
end

always @(posedge sys_clk) begin
    if(trigger) begin
        transmitting <= 1'b1;
    end

	case(digit)
		2'b01: // send a 1
			// low for 1 us, then high for 3 us
			if(transmitting) begin
				if(clk_cnt == 0) begin
					n64d <= 1'b0;
					clk_cnt <= clk_cnt + 1;
				end else if(clk_cnt == one_us) begin
					n64d <= 1'b1;
					clk_cnt <= clk_cnt + 1;
				end else if(clk_cnt == four_us) begin
					transmitting <= 1'b0;
					clk_cnt <= 0;
				end else clk_cnt <= clk_cnt + 1;
			end
		2'b00: // send a 0
			// low for 3 us, then high for 1 us
			if(transmitting) begin
				if(clk_cnt == 0) begin
					n64d <= 1'b0;
					clk_cnt <= clk_cnt + 1;
				end else if(clk_cnt == three_us) begin
					n64d <= 1'b1;
					clk_cnt <= clk_cnt + 1;
				end else if(clk_cnt == four_us) begin
					transmitting <= 1'b0;
					clk_cnt <= 0;
				end else clk_cnt <= clk_cnt + 1;
			end
		2'b11: // send a controller STOP bit
			// low for 1 us, then remain high
			if(transmitting) begin
				if(clk_cnt == 0) begin
					n64d <= 1'b0;
					clk_cnt <= clk_cnt + 1;
				end else if(clk_cnt == two_us) begin
					n64d <= 1'b1;
					transmitting <= 1'b0;
					clk_cnt <= 0;
				end else clk_cnt <= clk_cnt + 1;
			end
		2'b10: // send a console STOP bit
			// low for 1 us, then remain high
			if(transmitting) begin
				if(clk_cnt == 0) begin
					n64d <= 1'b0;
					clk_cnt <= clk_cnt + 1;
				end else if(clk_cnt == one_us) begin
					n64d <= 1'b1;
					transmitting <= 1'b0;
					clk_cnt <= 0;
				end else clk_cnt <= clk_cnt + 1;
			end
	endcase
end

endmodule
