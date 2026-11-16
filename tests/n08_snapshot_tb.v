// N08 regression: exercise the production serializer and decode its wire pulses.
// The mux matches n64_controller.input_data; no vendor FIFO model is required.
`timescale 1ns/1ps
module n08_snapshot_tb;
    reg clk = 0;
    always #10 clk = !clk;
    reg trigger = 0;
    reg mode = 0;
    reg [31:0] physical = 0;
    reg [31:0] tas = 0;
    wire [31:0] selected = mode ? tas : physical;
    wire line_out, busy;
    n64_transmit_controller_state dut(clk, trigger, selected, line_out, busy);
    integer cases = 0;
    integer kind, point;
    reg [31:0] expected;

    // Decode all 32 data pulses and the existing stop pulse, MSB first.
    task decode;
        input [31:0] wanted;
        reg [31:0] actual;
        integer bit_index;
        time started, width;
        begin
            actual = 0;
            for(bit_index = 31; bit_index >= 0; bit_index = bit_index - 1) begin
                @(negedge line_out); started = $time;
                @(posedge line_out); width = $time - started;
                if(width == 1000) actual[bit_index] = 1;
                else if(width == 3000) actual[bit_index] = 0;
                else $fatal(1, "Invalid data pulse width %0t", width);
            end
            @(negedge line_out); started = $time;
            @(posedge line_out);
            if($time - started != 2000) $fatal(1, "Invalid stop pulse");
            wait(!busy);
            if(actual !== wanted)
                $fatal(1, "kind=%0d point=%0d expected=%08h actual=%08h", kind, point, wanted, actual);
            repeat(10) @(negedge clk);
            if(line_out !== 1 || busy !== 0) $fatal(1, "Response did not return idle");
            cases = cases + 1;
            $display("PASS response %0d kind=%0d point=%0d data=%08h", cases, kind, point, actual);
        end
    endtask

    // Point 0 changes immediately after acceptance (before first byte load).
    // Points 1..4 change during each byte; points 5..7 change just before
    // the serializer selects bytes 2..4, using state only to place the stimulus.
    task disturb;
        input integer source_kind;
        input integer change_point;
        integer target_state;
        begin
            if(change_point >= 1 && change_point <= 4) begin
                target_state = change_point * 2;
                wait(dut.state == target_state);
                repeat(100) @(negedge clk);
            end else if(change_point >= 5) begin
                target_state = (change_point - 4) * 2;
                wait(dut.state == target_state && dut.byte_transmitting);
                wait(!dut.byte_transmitting);
                @(negedge clk);
            end
            if(source_kind == 0) physical = 32'h00000100;
            else mode = !mode;
        end
    endtask

    // Each disturbed response is followed by a fresh transaction to verify
    // that source/mode changes take effect on the next accepted idle trigger.
    task poll;
        input integer mutate;
        begin
            @(negedge clk);
            expected = selected;
            trigger = 1;
            @(negedge clk); trigger = 0;
            fork
                decode(expected);
                begin
                    if(mutate) disturb(kind, point);
                end
            join
        end
    endtask

    initial begin
        repeat(5) @(negedge clk);
        for(kind = 0; kind < 3; kind = kind + 1) begin
            // Start at the reported mixed-byte case for the pinned-source negative control.
            for(point = ($test$plusargs("baseline") ? 1 : 0); point < 8; point = point + 1) begin
                physical = (kind == 0) ? 32'h80000000 : 32'hA5C35A96;
                tas = 32'h3C69F00F;
                mode = (kind == 2);
                poll(1);
                poll(0);
            end
        end
        // Continuous changes throughout a response also must not alter it.
        physical = 32'hDEADBEEF; tas = 32'h01234567; mode = 0;
        fork
            poll(0);
            begin
                wait(busy);
                while(busy) begin
                    @(negedge clk);
                    physical = physical + 32'h01010101;
                    tas = tas ^ 32'hFEDCBA98;
                    mode = !mode;
                end
            end
        join
        poll(0);
        // A trigger while busy must not overwrite the accepted response word.
        physical = 32'h12345678; mode = 0;
        fork
            poll(0);
            begin
                wait(busy);
                repeat(100) @(negedge clk);
                physical = 32'h87654321;
                trigger = 1;
                @(negedge clk); trigger = 0;
            end
        join
        poll(0);
        $display("PASS N08: %0d decoded responses", cases);
        $finish;
    end

    // Bound hangs caused by missing pulses or an incomplete transaction.
    initial begin
        #10000000;
        $fatal(1, "N08 regression timeout");
    end
endmodule
