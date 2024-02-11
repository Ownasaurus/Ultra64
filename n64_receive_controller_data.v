// Ownasaurus
// Designed to read the controller data transmitted by an n64 controller

module n64_receive_controller_data(
	input sys_clk,
	input trigger,
    output reg [31:0] controller_data,
	input n64d,
	output reg receiving
);

//localparam one_us = 50;
//localparam two_us = 100;
//localparam three_us = 150;
//localparam four_us = 200;
localparam zero_one_border = 25;
localparam one_two_border = 75;
localparam two_three_border = 125;
localparam three_four_border = 175;

localparam idle=0, waiting_for_low=1, waiting_for_high=2, end_of_command=3;
reg [1:0] state;
reg [7:0] timer; // shouldn't ever be negative for more than 256 cycles. longest possible should theoretically be 150 cycles.
reg [5:0] position;

initial begin
    controller_data = 0;
    timer = 0;
    position = 0;
    state = 0;
    receiving = 0;
end

always @(posedge sys_clk) begin
    if(trigger) begin
        receiving <= 1'b1;
    end

    case(state)
        idle: begin
            if(receiving) begin
                position <= 0;
                controller_data <= 0;
                timer <= 0;
        		state <= waiting_for_low;
    		end
        end
        waiting_for_low: begin
	    if(timer > 250) begin // we were high for too long. it's probably not plugged in?
                state <= idle;
		receiving <= 1'b0;
            end else if(!n64d) begin // we went low, so start counting at 1 again!
                timer <= 1;
                state <= waiting_for_high;
            end else begin
		timer <= timer + 1'b1;
            end
        end
        waiting_for_high: begin
            if(timer > 250) begin // we were low for too long. it's probably not plugged in...?
                state <= idle;
                receiving <= 1'b0;
            end else if(n64d) begin
                // determine the type of signal based on how long we stated low
                if(timer > zero_one_border && timer <= one_two_border) begin // low for 1us
                    if(position == 32) begin // probably a console stop bit
                        state <= end_of_command;
                    end else begin
                        controller_data[31-position] <= 1'b1;
                        timer <= 0;
                        state <= waiting_for_low;
                    end
                end else if(timer > one_two_border && timer <= two_three_border) begin // low for 2us. controller end bit detected!
                    state <= end_of_command;
                end else if(timer > two_three_border && timer <= three_four_border) begin // low for 3us
                    if(position == 32) begin // THIS SHOULD NEVER HAPPEN
                        state <= end_of_command;
                    end else begin
                        controller_data[31-position] <= 1'b0;
                        timer <= 0;
                        state <= waiting_for_low;
                    end
                end else begin // it should never be this short of this long. fail back to idle state
                    state <= idle;
                end

                position <= position + 1'b1; // it's ok if this overflows at the end of the command
            end else begin
                timer <= timer + 1'b1;
            end
        end
        end_of_command: begin
            receiving <= 1'b0;
    		state <= idle;
        end
    endcase
end

endmodule
