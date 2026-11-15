// N01 regression: exercise actual parser RTL, with a behavioral TX FIFO only.
// The FIFO substitute isolates vendor primitives; UART_RX and UART_TX are real RTL.
`timescale 1ns/1ps
module queue_64(input Clock, input [7:0] Data, input RdEn, Reset, WrEn,
                output Empty, Full, output reg [7:0] Q, output [6:0] WCNT);
    reg [7:0] mem [0:63];
    integer rd=0, wr=0, count=0;
    assign Empty=(count==0);
    assign Full=(count==64);
    assign WCNT=count;
    always @(posedge Clock) begin
        if (Reset) begin rd<=0; wr<=0; count<=0; end
        else begin
            if (WrEn && !Full) begin mem[wr]<=Data; wr<=(wr+1)%64; end
            if (RdEn && !Empty) begin Q<=mem[rd]; rd<=(rd+1)%64; end
            case ({WrEn && !Full, RdEn && !Empty})
                2'b10: count<=count+1;
                2'b01: count<=count-1;
            endcase
        end
    end
endmodule

module serial_recovery_tb;
    reg clk=0, rx=1;
    reg request_frame=1;
    wire tx, write_frame, reset;
    wire [31:0] frame;
    integer writes=0, resets=0, replies=0;
    reg [7:0] response [0:8191];
    // N01: also run against the unmodified production parameter default.
`ifdef DEFAULT_TIMEOUT
    localparam TIMEOUT=500000;
`else
    localparam TIMEOUT=20000;
`endif
`ifdef DEFAULT_TIMEOUT
    serial_handler dut(clk, request_frame, rx, tx, write_frame, frame, reset);
`elsif PINNED_SOURCE
    serial_handler dut(clk, request_frame, rx, tx, write_frame, frame, reset);
`else
    serial_handler #(.RX_TIMEOUT_CLKS(TIMEOUT)) dut(clk, request_frame, rx, tx, write_frame, frame, reset);
`endif
    always #10 clk=~clk;
    // Observe the public queue interface and actual serialized reply bytes.
    wire reply_valid;
    wire [7:0] reply_byte;
    UART_RX monitor(1'b1, clk, tx, reply_valid, reply_byte);
    always @(posedge clk) begin
        if(write_frame) writes=writes+1;
        if(reset) resets=resets+1;
        if(reply_valid) begin response[replies]=reply_byte; replies=replies+1; end
    end
    task cycles;
        input integer n;
        begin repeat(n) @(negedge clk); end
    endtask
    // Fast directed tests inject decoded bytes while preserving parser clock semantics.
    reg [7:0] injected;
    task put;
        input [7:0] value;
        begin
            @(negedge clk); injected=value;
            force dut.new_byte=injected; force dut.received=1'b1;
            @(negedge clk); force dut.received=1'b0;
            cycles(3);
        end
    endtask
    task quiet;
        begin cycles(TIMEOUT+10); end
    endtask
    task recover;
        integer before_reset, before_reply;
        begin
            quiet;
            if(dut.state !== 0 || write_frame !== 0) $fatal(1,"parser did not recover");
            before_reset=resets; before_reply=replies;
            put(8'h52); cycles(10000);
            put(8'haa); cycles(10000);
            if(resets != before_reset+1 || replies != before_reply+3 ||
               response[before_reply] !== 8'h01 || response[before_reply+1] !== 8'h52 ||
               response[before_reply+2] !== 8'h55) $fatal(1,"reset/ping recovery failed");
        end
    endtask
    task uart_put;
        input [7:0] value;
        integer bitno;
        begin
            rx=0; cycles(434);
            for(bitno=0; bitno<8; bitno=bitno+1) begin rx=value[bitno]; cycles(434); end
            rx=1; cycles(434);
        end
    endtask
    integer n, j, fieldno, value, before_writes, before_reply;
    reg [7:0] setup_bytes [0:4];
    reg [7:0] frame_bytes [0:4];
    initial begin
        setup_bytes[0]=8'h53; setup_bytes[1]=8'h41; setup_bytes[2]=8'h4d;
        setup_bytes[3]=8'h80; setup_bytes[4]=0;
        frame_bytes[0]=8'h41; frame_bytes[1]=8'h12; frame_bytes[2]=8'h52;
        frame_bytes[3]=8'haa; frame_bytes[4]=0;
        cycles(10);
`ifdef PINNED_SOURCE
        // Reproduce both report traces against the immutable source before editing it.
        put(8'h53); put(8'h41); put(0); put(8'h52); put(8'haa); quiet;
        if(dut.state !== 5 || writes != 0 || resets != 0) $fatal(1,"setup trace differs");
        $display("CONFIRMED pinned source: 53 41 00 52 AA remains SETUP_2 after idle");
        // Test-only state initialization separates the two independent source traces.
        force dut.state=0; cycles(1); release dut.state;
        put(8'h41); put(8'h12); quiet; put(8'h52); put(8'haa); put(0); cycles(10);
        if(writes != 1 || frame !== 32'h1252aa00) $fatal(1,"partial frame trace differs");
        $display("CONFIRMED pinned source: interrupted frame commits 1252AA00");
`else
        // Truncate every multi-byte command at each incomplete byte boundary.
        for(n=1; n<5; n=n+1) begin
            before_writes=writes;
            for(j=0; j<n; j=j+1) put(setup_bytes[j]);
            recover;
            if(writes != before_writes) $fatal(1,"truncated setup wrote frame");
            for(j=0; j<n; j=j+1) put(frame_bytes[j]);
            recover;
            if(writes != before_writes || frame !== 0) $fatal(1,"partial frame published");
        end
        put(8'h50); recover;
        put(8'h51); recover;
        put(8'h51); put(0); recover;
        $display("PASS every incomplete setup/frame/power/bulk prefix recovers without writes");
        // Exhaust all unsupported values in the three constrained setup fields.
        for(fieldno=1; fieldno<=3; fieldno=fieldno+1)
            for(value=0; value<256; value=value+1)
                if(value != setup_bytes[fieldno]) begin
                    before_reply=replies;
                    for(j=0; j<fieldno; j=j+1) put(setup_bytes[j]);
                    put(value); cycles(10000);
                    if(dut.state !== 0 || replies != before_reply+1 ||
                       response[before_reply] !== 8'hfe) $fatal(1,"setup rejection failed");
                end
        recover;
        // N01: valid setup and ignored settings still preserve the original handshake.
        before_reply=replies;
        for(j=0; j<5; j=j+1) put(setup_bytes[j]);
        cycles(10000);
        if(replies != before_reply+2 || response[before_reply] !== 1 ||
           response[before_reply+1] !== 8'h53) $fatal(1,"valid setup response changed");
        put(8'h50); put(8'h52); put(8'h51); put(8'haa); put(8'h52);
        if(dut.state !== 0) $fatal(1,"valid power/bulk parser changed");
        $display("PASS all 765 unsupported setup field values return FE");
        // Timer restarts after each byte; a full frame may span more than one timeout.
        before_writes=writes;
        for(j=0; j<5; j=j+1) begin put(frame_bytes[j]); cycles(TIMEOUT-20); end
        if(writes != before_writes+1 || frame !== 32'h1252aa00) $fatal(1,"legal payload changed");
        // Exercise every byte value, including all command opcodes, in every payload lane.
        for(value=0; value<256; value=value+1) begin
            put(8'h41); put(value); put(value); put(value); put(value); cycles(5);
            if(frame !== {4{injected}}) $fatal(1,"binary frame corrupted");
        end
        if(writes != before_writes+257) $fatal(1,"frame write count differs");
        $display("PASS arbitrary binary frames and near-limit inter-byte gaps");
        // At expiry the incoming byte is discarded, never used to complete old data.
        before_writes=writes;
        put(8'h41); put(8'h12); put(8'h34); put(8'h56);
        // put() returns three silent cycles after acceptance; its next injection
        // waits one more edge, aligning this byte exactly with timeout expiry.
        cycles(TIMEOUT-5);
        put(8'h78); cycles(5);
        if(writes != before_writes) $fatal(1,"expiry committed partial frame");
        recover;
        // The response wait is bounded even if the transmitter never reports done.
        force dut.done=0;
        for(j=0; j<5; j=j+1) put(setup_bytes[j]);
        quiet;
        if(dut.state !== 0) $fatal(1,"setup response wait unbounded");
        release dut.done;
        recover;
        // Full UART integration: reconnect after partial frame, wait, reset and ping.
        release dut.new_byte; release dut.received;
        before_writes=writes; before_reply=replies;
        uart_put(8'h41); uart_put(8'h12); quiet;
        uart_put(8'h52); cycles(10000); uart_put(8'haa); cycles(10000);
        if(writes != before_writes || replies != before_reply+3 ||
           response[before_reply] !== 1 || response[before_reply+1] !== 8'h52 ||
           response[before_reply+2] !== 8'h55) $fatal(1,"UART reconnect recovery failed");
        uart_put(8'h41); uart_put(8'h52); uart_put(8'haa); uart_put(0); uart_put(8'hff); cycles(10);
        if(writes != before_writes+1 || frame !== 32'h52aa00ff) $fatal(1,"UART binary payload failed");
        $display("PASS timeout boundary, lost TX completion and real UART reconnect/payload");
`endif
        $display("PASS serial recovery regression");
        $finish;
    end
    // Detect stalled tests independently of the parser watchdog.
    initial begin #1000000000; $fatal(1,"testbench timeout"); end
endmodule
