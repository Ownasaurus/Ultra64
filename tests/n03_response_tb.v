`timescale 1ns/1ps
// N03 exercises the real parser, producer, dequeue logic and UART transmitter.
// RX-valid/TX-done injection isolates clock alignment from UART receive timing.
module n03_response_tb;
    reg clk = 0;
    always #5 clk = !clk;
    reg request_frame = 1;
    wire tx;
    serial_handler dut(.clk(clk), .request_frame(request_frame), .rx_uart(1'b1),
        .tx_uart(tx), .queue_WrEn(), .received_frame_data(), .n64_controller_reset());
    // Verilog-2005 keeps the production signal named byte legal.
    integer kind, phase, stall, overlap, bit_index, expected_count, writes = 0, sent = 0;
    reg [7:0] expected [0:3];
    reg [7:0] injected_byte;
    reg [7:0] decoded;

    // Check actual FIFO acceptance, including ordering and duplicate writes.
    always @(posedge clk) begin
        if(dut.serial_send_fifo_wren && !dut.send_buffer_full) begin
            if(writes >= expected_count || dut.fifo_input !== expected[writes])
                $fatal(1, "unexpected enqueue index=%0d byte=%02x", writes, dut.fifo_input);
            writes = writes + 1;
        end
    end

    // Decode the physical TX waveform at the production 434 clocks per bit.
    initial forever begin
        @(negedge tx);
        repeat(217) @(posedge clk);
        if(tx !== 0) $fatal(1, "invalid UART start");
        for(bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            repeat(434) @(posedge clk);
            decoded[bit_index] = tx;
        end
        repeat(434) @(posedge clk);
        if(tx !== 1 || sent >= expected_count || decoded !== expected[sent])
            $fatal(1, "unexpected UART byte index=%0d byte=%02x", sent, decoded);
        sent = sent + 1;
    end

    initial begin
        if(!$value$plusargs("kind=%d", kind)) kind = 0;
        if(!$value$plusargs("phase=%d", phase)) phase = 0;
        if(!$value$plusargs("stall=%d", stall)) stall = 0;
        // Exercise a new receive pulse on the acknowledgement edge as well.
        if(!$value$plusargs("overlap=%d", overlap)) overlap = 0;
        expected_count = 0;
        // Phase 0: idle; 1: already in cleanup; 2: automatic request selection.
        if(phase != 0) begin
            expected[expected_count] = 8'h41;
            expected_count = expected_count + 1;
        end
        case(kind)
            0: begin expected[expected_count] = 8'h55; injected_byte = 8'haa; end
            1: begin expected[expected_count] = 8'hff; injected_byte = 8'h00; end
            2: begin expected[expected_count] = 8'hb0; injected_byte = 8'h12; end
            3: begin expected[expected_count] = 8'hfe; injected_byte = 8'h42; end
            4, 6: begin expected[expected_count] = 8'h01; injected_byte = kind == 4 ? 8'h52 : 8'h00; end
            5: begin expected[expected_count] = 8'h52; injected_byte = 0; end
            7: begin expected[expected_count] = 8'h53; injected_byte = 0; end
        endcase
        expected_count = expected_count + 1;
        // First reset/setup responses must also complete their second byte.
        if(kind == 4 || kind == 6) begin
            expected[expected_count] = kind == 4 ? 8'h52 : 8'h53;
            expected_count = expected_count + 1;
        end
        @(negedge clk);
        dut.prebuffer_done = 1;
        dut.new_data_request_lock = phase == 2 ? 0 : 1;
        if(phase == 1) begin
            dut.send_SM = dut.send_CLEANUP;
            dut.serial_send_fifo_wren = 1;
            dut.fifo_input = 8'h41;
        end
        // Seed each response-producing parser boundary without changing the RTL.
        case(kind)
            2: begin dut.state = dut.RECEIVE_A_4; request_frame = 0; end
            3: dut.state = dut.SETUP_1;
            5: dut.state = dut.RESET_2;
            6: dut.state = dut.SETUP_4;
            7: dut.state = dut.SETUP_6;
        endcase
        force dut.new_byte = injected_byte;
        // Constant forces avoid simulator-specific expression reevaluation.
        if(kind == 5 || kind == 7) force dut.received = 1'b0;
        else force dut.received = 1'b1;
        if(kind == 5 || kind == 7) force dut.done = 1'b1;
        // Overrun/automatic selection is unreachable: the reductions of the same
        // request_frame vector cannot both be all-ready and contain a full queue.
        @(posedge clk); #1;
        @(negedge clk);
        release dut.new_byte;
        release dut.received;
        release dut.done;
        if(overlap != 0) begin
            // Phase 2 acknowledges on T+2, after the automatic-write cleanup.
            @(negedge clk);
            force dut.received = 1'b1;
            @(negedge clk);
            release dut.received;
        end
        if(stall != 0) begin
            // Backpressure begins after the automatic request has been accepted.
            @(posedge clk); #1;
            force dut.send_buffer_full = 1'b1;
            repeat(8) @(posedge clk);
            #1;
            if(!dut.respond_to_serial_TX) $fatal(1, "response lost while full");
            @(negedge clk);
            release dut.send_buffer_full;
        end
        repeat(16000) @(posedge clk);
        #1;
        if(writes != expected_count || sent != expected_count || dut.respond_to_serial_TX || dut.state != dut.IDLE)
            $fatal(1, "missing response writes=%0d sent=%0d expected=%0d state=%0d", writes, sent, expected_count, dut.state);
        $display("PASS kind=%0d phase=%0d stall=%0d overlap=%0d enqueued=%0d transmitted=%0d", kind, phase, stall, overlap, writes, sent);
        $finish;
    end
endmodule

// Portable synchronous FIFO contract model: ECP5 RAM primitives are black boxes
// in the bundled Yosys simulation library. The full FPGA build uses queue_64.v.
module queue_64(input [7:0] Data, input Clock, WrEn, RdEn, Reset,
    output reg [7:0] Q = 0, output [6:0] WCNT, output Empty, Full);
    reg [7:0] memory [0:63];
    integer count = 0, read_index = 0, write_index = 0;
    assign WCNT = count;
    assign Empty = count == 0;
    assign Full = count == 64;
    always @(posedge Clock) begin
        if(Reset) begin count <= 0; read_index <= 0; write_index <= 0; end
        else begin
            if(WrEn && !Full) begin
                memory[write_index] <= Data;
                write_index <= (write_index + 1) % 64;
            end
            if(RdEn && !Empty) begin
                Q <= memory[read_index];
                read_index <= (read_index + 1) % 64;
            end
            case({WrEn && !Full, RdEn && !Empty})
                2'b10: count <= count + 1;
                2'b01: count <= count - 1;
            endcase
        end
    end
endmodule
