// Ownasaurus
// Designed to read the controller data transmitted by an n64 controller

module n64_receive_controller_data(
	input sys_clk,
	input trigger,
    output reg [31:0] controller_data,
	input n64d,
	output reg receiving,
    // Result belongs to the latest attempt and stays stable until the next trigger.
    output reg response_valid
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
// Keep partial payloads private; controller_data holds the last complete response.
reg [31:0] working_data;

initial begin
    controller_data = 0;
    timer = 0;
    position = 0;
    state = 0;
    receiving = 0;
    // Start without a valid response or any partial payload.
    response_valid = 0;
    working_data = 0;
end

always @(posedge sys_clk) begin
    // Accept a new attempt only while idle; clear its previous result immediately.
    if(trigger && state == idle && !receiving) begin
        receiving <= 1'b1;
        response_valid <= 1'b0;
    end

    case(state)
        idle: begin
            if(receiving) begin
                position <= 0;
                // Clear only scratch storage so malformed replies cannot leak out.
                working_data <= 0;
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
                // Only a controller stop (2us low) after exactly 32 bits commits.
                // The 1us console stop and additional payload bits are invalid here.
                if(position == 32 && timer > one_two_border && timer <= two_three_border) begin
                    controller_data <= working_data;
                    response_valid <= 1'b1;
                    state <= end_of_command;
                end else if(position < 32 &&
                    ((timer > zero_one_border && timer <= one_two_border) ||
                     (timer > two_three_border && timer <= three_four_border))) begin
                    // Count payload bits only, retaining the existing 1us/3us windows.
                    working_data[31-position] <= (timer <= one_two_border);
                    position <= position + 1'b1;
                    timer <= 0;
                    state <= waiting_for_low;
                end else begin
                    // Early stops and malformed pulses complete with an invalid result.
                    state <= end_of_command;
                end
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
