// N04: Simulation-only synchronous TX FIFO. The vendor FIFO is outside this
// regression's scope; tests use production UART_RX, UART_TX and parser directly.
module queue_64(input [7:0] Data, input Clock, WrEn, RdEn, Reset,
                output reg [7:0] Q=0, output [6:0] WCNT,
                output Empty, Full);
  reg [7:0] memory[0:63];
  reg [5:0] wr=0, rd=0;
  reg [6:0] count=0;
  wire push=WrEn && !Full, pop=RdEn && !Empty;
  assign Empty=(count==0);
  assign Full=(count==64);
  assign WCNT=count;
  always @(posedge Clock) begin
    if(Reset) begin wr<=0; rd<=0; count<=0; Q<=0; end
    else begin
      if(push) begin memory[wr]<=Data; wr<=wr+1'b1; end
      if(pop) begin Q<=memory[rd]; rd<=rd+1'b1; end
      case({push,pop})
        2'b10: count<=count+1'b1;
        2'b01: count<=count-1'b1;
      endcase
    end
  end
endmodule
