// =============================================================================
// uart_rx.v  -  Simple UART Receiver (8N1: 8 data bits, No parity, 1 stop bit)
// -----------------------------------------------------------------------------
// How it works:
//   * The line idles HIGH. A falling edge (HIGH -> LOW) means a start bit begins.
//   * We wait HALF a bit time to reach the MIDDLE of the start bit and check
//     that it is still LOW (if not, it was just a glitch -> go back to IDLE).
//   * From the middle of the start bit, waiting ONE full bit time lands us in
//     the middle of each data bit. We sample there, where the signal is most stable.
//   * After 8 data bits we sample the stop bit, then pulse rx_done.
//
// CLKS_PER_BIT = clock frequency / baud rate
//              = 100_000_000 / 115_200 = 868 (rounded)
// =============================================================================

`timescale 1ns / 1ps                          // Time unit 1 ns, precision 1 ps

module uart_rx #(
    parameter CLKS_PER_BIT = 868              // Number of clock cycles per UART bit
)(
    input  wire       clk,                    // System clock (100 MHz)
    input  wire       rst,                    // Synchronous reset, active high
    input  wire       rx,                     // Serial input line (idles HIGH)
    output reg  [7:0] rx_data,                // The byte that was received
    output reg        rx_done                 // 1-clock pulse when rx_data is valid
);

    // ---------------- FSM state encoding ----------------
    localparam IDLE  = 2'd0;                  // Waiting for a start bit
    localparam START = 2'd1;                  // Checking the middle of the start bit
    localparam DATA  = 2'd2;                  // Sampling the 8 data bits
    localparam STOP  = 2'd3;                  // Sampling the stop bit

    reg [1:0]  state;                         // Current FSM state
    reg [15:0] clk_count;                     // Baud counter (clocks inside one bit)
    reg [2:0]  bit_index;                     // Which data bit (0..7) we are receiving
    reg [7:0]  data_reg;                      // Shift/collect register for incoming bits

    // ---------------- Input synchronizer ----------------
    // rx comes from outside our clock domain, so pass it through 2 flip-flops
    // to avoid metastability. Use rx_sync everywhere instead of rx.
    reg rx_meta;                              // First flip-flop (may go metastable)
    reg rx_sync;                              // Second flip-flop (safe to use)
    always @(posedge clk) begin
        rx_meta <= rx;                        // Stage 1
        rx_sync <= rx_meta;                   // Stage 2
    end

    // ---------------- Main FSM ----------------
    always @(posedge clk) begin
        if (rst) begin                        // Reset: go back to a known, safe state
            state     <= IDLE;
            clk_count <= 0;
            bit_index <= 0;
            data_reg  <= 8'd0;
            rx_data   <= 8'd0;
            rx_done   <= 1'b0;
        end else begin
            rx_done <= 1'b0;                  // Default: rx_done is only a 1-clock pulse

            case (state)
                // -------------------------------------------------------------
                IDLE: begin
                    clk_count <= 0;           // Clear the baud counter
                    bit_index <= 0;           // Start from data bit 0
                    if (rx_sync == 1'b0) begin // Line went LOW -> start bit detected
                        state <= START;
                    end
                end

                // -------------------------------------------------------------
                START: begin
                    if (clk_count < (CLKS_PER_BIT / 2) - 1) begin
                        clk_count <= clk_count + 1;   // Wait half a bit time
                    end else begin
                        clk_count <= 0;               // We are now in the MIDDLE of the start bit
                        if (rx_sync == 1'b0) begin
                            state <= DATA;            // Still LOW: real start bit, go read data
                        end else begin
                            state <= IDLE;            // HIGH again: it was a glitch, ignore it
                        end
                    end
                end

                // -------------------------------------------------------------
                DATA: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;   // Wait one full bit time
                    end else begin
                        clk_count <= 0;               // Now in the MIDDLE of a data bit
                        data_reg[bit_index] <= rx_sync; // Sample it (LSB arrives first)
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1; // Next data bit
                        end else begin
                            bit_index <= 0;           // All 8 bits received
                            state     <= STOP;        // Go check the stop bit
                        end
                    end
                end

                // -------------------------------------------------------------
                STOP: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;   // Wait one full bit time
                    end else begin
                        clk_count <= 0;               // Now in the MIDDLE of the stop bit
                        rx_data   <= data_reg;        // Output the received byte
                        rx_done   <= 1'b1;            // Tell the user a byte is ready
                        state     <= IDLE;            // Wait for the next start bit
                    end
                end

                // -------------------------------------------------------------
                default: state <= IDLE;       // Safety: recover from any illegal state
            endcase
        end
    end

endmodule
