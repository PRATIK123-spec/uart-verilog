// =============================================================================
// uart_tx.v  -  Simple UART Transmitter (8N1: 8 data bits, No parity, 1 stop bit)
// -----------------------------------------------------------------------------
// How to use:
//   1. Put the byte you want to send on tx_data.
//   2. Pulse tx_start high for ONE clock cycle (only while tx_busy is 0).
//   3. The module sends: start bit (0), 8 data bits (LSB first), stop bit (1).
//   4. tx_done pulses high for one clock when the whole frame is finished.
//
// CLKS_PER_BIT = clock frequency / baud rate
//              = 100_000_000 / 115_200 = 868 (rounded)
// =============================================================================

`timescale 1ns / 1ps                          // Time unit 1 ns, precision 1 ps

module uart_tx #(
    parameter CLKS_PER_BIT = 868              // Number of clock cycles per UART bit
)(
    input  wire       clk,                    // System clock (100 MHz)
    input  wire       rst,                    // Synchronous reset, active high
    input  wire       tx_start,               // Pulse high for 1 clock to start sending
    input  wire [7:0] tx_data,                // Byte to send
    output reg        tx,                     // Serial output line (idles HIGH)
    output reg        tx_busy,                // 1 while a frame is being sent
    output reg        tx_done                 // 1-clock pulse when frame is finished
);

    // ---------------- FSM state encoding ----------------
    localparam IDLE  = 2'd0;                  // Waiting for tx_start
    localparam START = 2'd1;                  // Sending the start bit (0)
    localparam DATA  = 2'd2;                  // Sending the 8 data bits
    localparam STOP  = 2'd3;                  // Sending the stop bit (1)

    reg [1:0]  state;                         // Current FSM state
    reg [15:0] clk_count;                     // Counts clocks inside one bit period (baud counter)
    reg [2:0]  bit_index;                     // Which data bit (0..7) we are sending
    reg [7:0]  data_reg;                      // Local copy of the byte, so tx_data may change

    always @(posedge clk) begin
        if (rst) begin                        // Reset: go back to a known, safe state
            state     <= IDLE;
            tx        <= 1'b1;                // Line must idle HIGH
            tx_busy   <= 1'b0;
            tx_done   <= 1'b0;
            clk_count <= 0;
            bit_index <= 0;
            data_reg  <= 8'd0;
        end else begin
            tx_done <= 1'b0;                  // Default: tx_done is only a 1-clock pulse

            case (state)
                // -------------------------------------------------------------
                IDLE: begin
                    tx        <= 1'b1;        // Keep the line HIGH while idle
                    tx_busy   <= 1'b0;        // Not busy
                    clk_count <= 0;           // Clear the baud counter
                    bit_index <= 0;           // Start from data bit 0
                    if (tx_start) begin       // Request to send?
                        data_reg <= tx_data;  // Latch the byte to send
                        tx_busy  <= 1'b1;     // Now we are busy
                        state    <= START;    // Go send the start bit
                    end
                end

                // -------------------------------------------------------------
                START: begin
                    tx <= 1'b0;               // Start bit is always LOW
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;   // Hold the start bit for one full bit time
                    end else begin
                        clk_count <= 0;       // Bit time finished: reset counter
                        state     <= DATA;    // Move on to the data bits
                    end
                end

                // -------------------------------------------------------------
                DATA: begin
                    tx <= data_reg[bit_index];        // Output current data bit (LSB first)
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;   // Hold this bit for one full bit time
                    end else begin
                        clk_count <= 0;               // Bit time finished
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1; // Go to the next data bit
                        end else begin
                            bit_index <= 0;           // All 8 bits sent
                            state     <= STOP;        // Go send the stop bit
                        end
                    end
                end

                // -------------------------------------------------------------
                STOP: begin
                    tx <= 1'b1;               // Stop bit is always HIGH
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;   // Hold the stop bit for one full bit time
                    end else begin
                        clk_count <= 0;       // Frame finished
                        tx_done   <= 1'b1;    // Tell the user we are done (1-clock pulse)
                        tx_busy   <= 1'b0;    // No longer busy
                        state     <= IDLE;    // Wait for the next byte
                    end
                end

                // -------------------------------------------------------------
                default: state <= IDLE;       // Safety: recover from any illegal state
            endcase
        end
    end

endmodule
