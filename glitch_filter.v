// Ownasaurus
// Designed to filter a signal to eliminate any tiny glitches, faking a rising/falling edge

module glitch_filter(
	input sys_clk,
	input line_in,
	output line_out
);

reg [3:0] sample_counter;
reg filtered_output;

// N05: Synchronize before comparing or counting, for every N64/button caller.
// Yosys keep preserves the two flops; async_reg documents the CDC boundary.
// Both stages start at the idle/pull-up level, like the filter output.
(* async_reg = "true", keep = 1 *) reg line_meta = 1'b1;
(* async_reg = "true", keep = 1 *) reg line_sync = 1'b1;
always @(posedge sys_clk) begin
	line_meta <= line_in;
	line_sync <= line_meta;
end

initial begin
	filtered_output = 1; // arbitrary initial value of the output line
	sample_counter = 0;
end

always @(posedge sys_clk) begin
	if(filtered_output == line_sync) begin // N05: Count only synchronized samples.
		sample_counter <= 0;
	end else begin // the input signal has changed
		sample_counter <= sample_counter + 1'b1;
		if(sample_counter == 5) begin // they don't match, and it's been a a few samples. so let the change go through
			filtered_output <= !filtered_output;
			sample_counter <= 0;
		end
	end
end

assign line_out = filtered_output;

endmodule
