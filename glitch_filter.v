// Ownasaurus
// Designed to filter a signal to eliminate any tiny glitches, faking a rising/falling edge

// Keep protocol filtering at six clocks; mechanical buttons select a longer interval.
module glitch_filter #(parameter STABLE_CYCLES = 6)(
	input sys_clk,
	input line_in,
	output line_out
);

// Size the consecutive-sample counter for the selected interval, including one clock.
localparam COUNTER_WIDTH = (STABLE_CYCLES > 1) ? $clog2(STABLE_CYCLES) : 1;
reg [COUNTER_WIDTH-1:0] sample_counter;
reg filtered_output;

initial begin
	filtered_output = 1; // arbitrary initial value of the output line
	sample_counter = 0;
end

always @(posedge sys_clk) begin
	if(filtered_output == line_in) begin // they match, so reset counter
		sample_counter <= 0;
	end else begin // the input signal has changed
		sample_counter <= sample_counter + 1'b1;
		if(sample_counter == STABLE_CYCLES - 1) begin // Accept only a full uninterrupted interval at the new level.
			filtered_output <= !filtered_output;
			sample_counter <= 0;
		end
	end
end

assign line_out = filtered_output;

endmodule
