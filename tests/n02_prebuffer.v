`timescale 1ns/1ps
// N02 regression: exercise real serial-handler/FIFO RTL with independently
// scheduled FIFO reads. Inject decoded RX bytes to keep 1024-frame fills fast;
// N64 command decoding and the UART RX electrical interface are outside this test.
module n02_prebuffer;
parameter N = 2;
reg clk = 0;
always #10 clk = !clk;
wire [N-1:0] request_frame;
reg [N-1:0] poll = 0;
wire wr, reset;
wire [31:0] data;
wire tx;
reg [7:0] injected_byte;
reg injected_valid = 0;
integer requests = 0, errors = 0, writes = 0;
integer i, saved_requests, saved_writes;
serial_handler #(.NUM_CONSOLES(N)) dut(clk, request_frame, 1'b1, tx, wr, data, reset);
// Use the generated frame FIFOs, including their real full flags and reset.
genvar c;
generate for(c=0;c<N;c=c+1) begin: consoles
    wire full, empty;
    wire [31:0] q;
    queue_1024 fifo(data, clk, wr, poll[c], reset, q, empty, full);
    assign request_frame[c] = !full;
end endgenerate
// Observe accepted producer writes, so duplicate or missing requests are visible.
always @(posedge clk) begin
    if(wr) writes = writes + 1;
    if(dut.serial_send_fifo_wren) begin
        if(dut.fifo_input == 8'h41) requests = requests + 1;
        if(dut.fifo_input == 8'hB0) errors = errors + 1;
    end
end
task tick;
    input integer count;
    begin repeat(count) @(negedge clk); end
endtask
task rx;
    input [7:0] value;
    begin
        injected_byte = value; injected_valid = 1; tick(1);
        injected_valid = 0; tick(4);
    end
endtask
task frame;
    begin rx(8'h41); rx(8'h12); rx(8'h34); rx(8'h56); rx(8'h78); end
endtask
task consume;
    input [N-1:0] mask;
    begin poll = mask; tick(1); poll = 0; tick(8); end
endtask
initial begin
    force dut.received = injected_valid;
    force dut.new_byte = injected_byte;
    tick(20);
    // A protocol reset establishes the actual FIFO state before each startup.
    rx(8'h52); tick(50000);
    for(i=0;i<1023;i=i+1) frame;
    if(dut.prebuffer_done !== 0 || requests != 0) $fatal(1,"premature prebuffer completion");
    // Poll only the last console before filling the first one (single-console
    // case is the original simultaneous-full positive control).
    if(N>1) consume({1'b1,{(N-1){1'b0}}});
    frame;
    if(request_frame[0] !== 0) $fatal(1,"first FIFO did not fill");
    if(N>1 && request_frame[N-1] !== 1) $fatal(1,"unequal fill not reached");
    // Rejected writes must remain atomic even though initial buffering is done.
    saved_writes = writes;
    frame; tick(8);
    if(writes != saved_writes || errors != 1) $fatal(1,"full FIFO write not rejected");
    if(requests != 0) $fatal(1,"requested while a console was full");
    consume({N{1'b1}}); tick(20);
    if(requests != 1) $fatal(1,"N02: no replenishment after unequal startup");
    // Host pause and independent faster polling must not duplicate the request.
    // The single-console control has no faster peer; leave its one slot free.
    if(N>1) repeat(3) consume({1'b1,{(N-1){1'b0}}});
    tick(50000);
    if(requests != 1) $fatal(1,"duplicate outstanding request");
    frame; tick(20);
    if(requests != 1) $fatal(1,"request ignored a full slower console");
    consume({N{1'b1}}); tick(20);
    if(requests != 2) $fatal(1,"replenishment did not continue");
    // Clear the outstanding request with a successful frame before resetting;
    // request-lock reset semantics are a separate issue from N02.
    frame; tick(50000);
    rx(8'h52); tick(50000);
    saved_requests = requests;
    frame; tick(20);
    if(dut.prebuffer_done !== 0 || requests != saved_requests)
        $fatal(1,"reset did not rearm prebuffering");
    $display("PASS N02 consoles=%0d: unequal fill, rejection, host pause, resumed polling, reset",N);
    $finish;
end
// Bound all waits so a stalled state produces a failing test run.
initial begin #100000000; $fatal(1,"watchdog"); end
endmodule
