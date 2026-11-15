// N07: elaborate the complete multi-console status wiring with vendor global-reset roots.
module n07_top_tb;
GSR GSR_INST(.GSR(1'b1));
PUR PUR_INST(.PUR(1'b1));
top #(.NUM_CONSOLES(2)) dut();
endmodule
