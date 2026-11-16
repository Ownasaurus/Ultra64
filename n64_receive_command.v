// Ownasaurus
// Designed to read a command transmitted by the n64

module n64_receive_command(
	input sys_clk,
	input trigger,
    output [7:0] command,
	input n64d,
	output reg receiving
);

// Keep partial bits private; the wrapper may act only on a completed command.
reg [7:0] byte;
reg [7:0] completed_command;

//parameter one_us = 50;
//parameter two_us = 100;
//parameter three_us = 150;
//parameter four_us = 200;
parameter zero_one_border = 25;
parameter one_two_border = 75;
parameter two_three_border = 125;
parameter three_four_border = 175;

// At 50 MHz, valid data highs last at most 3 us. A 4 us high
// discards a partial command and also provides the error recovery boundary.
parameter inter_bit_timeout = 200;
localparam idle=0, waiting_for_low=1, waiting_for_high=2, end_of_command=3, resynchronize=4;
reg [2:0] state;
// Both pulse widths and the idle recovery interval fit in eight bits.
reg [7:0] timer;
reg [3:0] position;

initial begin
    byte = 0;
    completed_command = 0; // No partial byte is ever published on failure.
    timer = 0;
    position = 0;
    state = 0;
    receiving = 0;
end

// Receiving falls only on success, preserving the existing wrapper handshake.
assign command = completed_command;

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
            // Idle is unlimited before the first bit, but bounded thereafter.
            if(!n64d) begin
                timer <= 1;
                state <= waiting_for_high;
            end else if(position != 0) begin
                if(timer >= inter_bit_timeout - 1) begin
                    // This high interval already satisfies resynchronization.
                    position <= 0;
                    byte <= 0;
                    timer <= 0;
                end else begin
                    timer <= timer + 1'b1;
                end
            end
        end
        waiting_for_high: begin
            if(n64d) begin
                // Only eight data bits followed by a 1 us console stop succeed.
                // A 2 us controller stop, early stop, or extra zero is an error.
                if(timer > zero_one_border && timer <= one_two_border) begin // low for 1us
                    if(position == 8) begin
                        completed_command <= byte;
                        state <= end_of_command;
                    end else begin
                        byte[7-position] <= 1'b1;
                        position <= position + 1'b1;
                        state <= waiting_for_low;
                    end
                end else if(timer > two_three_border && timer <= three_four_border && position < 8) begin
                    // Three-microsecond lows encode zero only within the byte.
                    byte[7-position] <= 1'b0;
                    position <= position + 1'b1;
                    state <= waiting_for_low;
                end else begin
                    // Ignore the rest of this malformed transaction until idle.
                    state <= resynchronize;
                end
                timer <= 1; // Count this first high sample toward the gap.
            end else if(timer >= three_four_border) begin
                // Do not let a stuck-low timer wrap into a valid pulse width.
                timer <= 0;
                state <= resynchronize;
            end else begin
                timer <= timer + 1'b1;
            end
        end
        end_of_command: begin
            receiving <= 1'b0;
    		state <= idle;
        end
        resynchronize: begin
            // A continuous 4 us high is required after any malformed pulse.
            // Keep receiving asserted so the wrapper cannot schedule a reply.
            if(!n64d) begin
                timer <= 0;
            end else if(timer >= inter_bit_timeout - 1) begin
                position <= 0;
                byte <= 0;
                timer <= 0;
                state <= waiting_for_low;
            end else begin
                timer <= timer + 1'b1;
            end
        end
    endcase
end

endmodule
