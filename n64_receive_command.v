// Ownasaurus
// Designed to read a command transmitted by the n64

module n64_receive_command(
	input sys_clk,
	input trigger,
    output [7:0] command,
	input n64d,
	output reg receiving
);

reg [7:0] byte; // note backwards bit order

//parameter one_us = 50;
//parameter two_us = 100;
//parameter three_us = 150;
//parameter four_us = 200;
parameter zero_one_border = 25;
parameter one_two_border = 75;
parameter two_three_border = 125;
parameter three_four_border = 175;

localparam idle=0, waiting_for_low=1, waiting_for_high=2, end_of_command=3, console_off=4;
reg [2:0] state;
reg [7:0] timer; // shouldn't ever be negative for more than 256 cycles. longest possible should theoretically be 150 cycles.
reg [3:0] position;

initial begin
    byte = 0;
    timer = 0;
    position = 0;
    state = 0;
    receiving = 0;
end

assign command = byte;

always @(posedge sys_clk) begin
    if(trigger) begin
        receiving <= 1'b1;
    end

    case(state)
        idle: begin
            if(receiving) begin
                position <= 0;
                byte <= 0;
                timer <= 0;
        		state <= waiting_for_low;
    		end
        end
        waiting_for_low: begin
            // ok to idle here for long periods of time
            if(!n64d) begin // we went low, so start counting!
                timer <= timer + 1'b1;
                state <= waiting_for_high;
            end
        end
        waiting_for_high: begin
            if(timer > 250) begin // we were low for too long. it's probably not plugged in...?
                state <= console_off;
            end else if(n64d) begin
                // determine the type of signal based on how long we stated low
                if(timer > zero_one_border && timer <= one_two_border) begin // low for 1us
                    if(position == 8) begin // probably a console stop bit
                        state <= end_of_command;
                    end else begin
                        byte[7-position] <= 1'b1;
                        timer <= 0;
                        state <= waiting_for_low;
                    end
                end else if(timer > one_two_border && timer <= two_three_border) begin // low for 2us. controller end bit detected!
                    state <= end_of_command;
                end else if(timer > two_three_border && timer <= three_four_border) begin // low for 3us
                    if(position == 8) begin // THIS SHOULD NEVER HAPPEN
                        state <= end_of_command;
                    end else begin
                        byte[7-position] <= 1'b0;
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
        console_off: begin
            if(n64d) begin
                position <= 0;
                byte <= 0;
                timer <= 0;
                state <= waiting_for_low;
            end
        end
    endcase
end

endmodule
