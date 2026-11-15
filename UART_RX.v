//////////////////////////////////////////////////////////////////////
// Author:      Russell Merrick
//////////////////////////////////////////////////////////////////////
// Description: This file contains the UART Receiver.  This receiver is 
//              able to receive 8 bits of serial data, one start bit, one 
//              stop bit, and no parity bit.  When receive is complete 
//              o_RX_DV will be driven high for one clock cycle.
// 
// Parameters:  Set Parameter CLKS_PER_BIT as follows:
//              CLKS_PER_BIT = (Frequency of i_Clock)/(Frequency of UART)
//              Example: 25 MHz Clock, 115200 baud UART
//              (25000000)/(115200) = 217
//////////////////////////////////////////////////////////////////////////////

module UART_RX
  #(parameter CLKS_PER_BIT = 434)
  (
   input            i_Rst_L,
   input            i_Clock,
   input            i_RX_Serial,
   output reg       o_RX_DV,
   output reg [7:0] o_RX_Byte=8'h00,
   // N04: Pulse for one clock when the stop-bit midpoint is low.
   output reg       o_RX_Framing_Error=1'b0
   );
   
  localparam IDLE         = 3'b000;
  localparam RX_START_BIT = 3'b001;
  localparam RX_DATA_BITS = 3'b010;
  localparam RX_STOP_BIT  = 3'b011;
  localparam CLEANUP      = 3'b100;
  // N04: Require a full high bit after bad framing before accepting a start.
  localparam RX_RECOVER   = 3'b101;
  
  reg [$clog2(CLKS_PER_BIT)-1:0] r_Clock_Count;
  reg [2:0] r_Bit_Index; //8 bits total
  reg [2:0] r_SM_Main;
  
  initial begin
	o_RX_DV = 1'b0;
  end
  
  // Purpose: Control RX state machine
  always @(posedge i_Clock or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
    begin
      r_SM_Main <= 3'b000;
      o_RX_DV   <= 1'b0;
      // N04: Reset must also clear the framing-error indication.
      o_RX_Framing_Error <= 1'b0;
    end
    else
    begin
      // N04: Framing errors are events, not a level held throughout a break.
      o_RX_Framing_Error <= 1'b0;
      case (r_SM_Main)
      IDLE :
        begin
          o_RX_DV       <= 1'b0;
          r_Clock_Count <= 0;
          r_Bit_Index   <= 0;
          
          if (i_RX_Serial == 1'b0)          // Start bit detected
            r_SM_Main <= RX_START_BIT;
          else
            r_SM_Main <= IDLE;
        end
      
      // Check middle of start bit to make sure it's still low
      RX_START_BIT :
        begin
          if (r_Clock_Count == (CLKS_PER_BIT-1)/2)
          begin
            if (i_RX_Serial == 1'b0)
            begin
              r_Clock_Count <= 0;  // reset counter, found the middle
              r_SM_Main     <= RX_DATA_BITS;
            end
            else
              r_SM_Main <= IDLE;
          end
          else
          begin
            r_Clock_Count <= r_Clock_Count + 1'b1;
            r_SM_Main     <= RX_START_BIT;
          end
        end // case: RX_START_BIT
      
      
      // Wait CLKS_PER_BIT-1 clock cycles to sample serial data
      RX_DATA_BITS :
        begin
          if (r_Clock_Count < CLKS_PER_BIT-1)
          begin
            r_Clock_Count <= r_Clock_Count + 1'b1;
            r_SM_Main     <= RX_DATA_BITS;
          end
          else
          begin
            r_Clock_Count          <= 0;
            o_RX_Byte[r_Bit_Index] <= i_RX_Serial;
            
            // Check if we have received all bits
            if (r_Bit_Index < 7)
            begin
              r_Bit_Index <= r_Bit_Index + 1'b1;
              r_SM_Main   <= RX_DATA_BITS;
            end
            else
            begin
              r_Bit_Index <= 0;
              r_SM_Main   <= RX_STOP_BIT;
            end
          end
        end // case: RX_DATA_BITS
      
      
      // Receive Stop bit.  Stop bit = 1
      RX_STOP_BIT :
        begin
          // N04: This interval ends at the stop-bit midpoint, as for data bits.
          if (r_Clock_Count < CLKS_PER_BIT-1)
          begin
            r_Clock_Count <= r_Clock_Count + 1'b1;
            r_SM_Main     <= RX_STOP_BIT;
          end
          else
          begin
            // N04: Only a high stop sample can publish a received byte.
            if (i_RX_Serial == 1'b1)
            begin
              o_RX_DV   <= 1'b1;
              r_SM_Main <= CLEANUP;
            end
            else
            begin
              o_RX_DV <= 1'b0;
              o_RX_Framing_Error <= 1'b1;
              r_SM_Main <= RX_RECOVER;
            end
            r_Clock_Count <= 0;
          end
        end // case: RX_STOP_BIT

      // N04: A held-low break cannot generate bytes or repeated errors. Any
      // low sample restarts the consecutive-high idle qualification interval.
      RX_RECOVER :
        begin
          o_RX_DV <= 1'b0;
          if (i_RX_Serial == 1'b0)
            r_Clock_Count <= 0;
          else if (r_Clock_Count == CLKS_PER_BIT-1)
          begin
            r_Clock_Count <= 0;
            r_SM_Main <= IDLE;
          end
          else
            r_Clock_Count <= r_Clock_Count + 1'b1;
        end
      
      
      // Stay here 1 clock
      CLEANUP :
        begin
          r_SM_Main <= IDLE;
          o_RX_DV   <= 1'b0;
        end
      
      
      default :
        r_SM_Main <= IDLE;
      
    endcase
    end // else: !if(~i_Rst_L)
  end // always @ (posedge i_Clock or negedge i_Rst_L)
  
endmodule // UART_RX
