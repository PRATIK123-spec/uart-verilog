// =============================================================================
// tb_uart.v  -  Loopback testbench: uart_tx output is wired straight into uart_rx
// -----------------------------------------------------------------------------
// For each test byte:
//   1. Give the byte to the transmitter and pulse tx_start.
//   2. Wait for the receiver to pulse rx_done.
//   3. Compare rx_data with what we sent and print PASS or FAIL.
// At the end, print a summary and finish. A VCD waveform (uart.vcd) is dumped.
// =============================================================================

`timescale 1ns / 1ps                          // Time unit 1 ns, precision 1 ps

module tb_uart;

    // ---------------- Parameters ----------------
    localparam CLK_PERIOD   = 10;             // 10 ns period = 100 MHz clock
    localparam CLKS_PER_BIT = 868;            // 100 MHz / 115200 baud
    localparam NUM_TESTS    = 8;              // How many bytes we send

    // ---------------- Testbench signals ----------------
    reg        clk = 0;                       // Clock
    reg        rst = 1;                       // Reset (start in reset)
    reg        tx_start = 0;                  // Start pulse to the transmitter
    reg  [7:0] tx_data  = 8'd0;               // Byte given to the transmitter
    wire       serial_line;                   // The single UART wire (TX -> RX)
    wire       tx_busy;                       // Transmitter busy flag
    wire       tx_done;                       // Transmitter done pulse
    wire [7:0] rx_data;                       // Byte coming out of the receiver
    wire       rx_done;                       // Receiver done pulse

    integer pass_count = 0;                   // Number of tests that passed
    integer fail_count = 0;                   // Number of tests that failed
    integer i;                                // Loop variable

    reg [7:0] test_bytes [0:NUM_TESTS-1];     // List of bytes to send

    // ---------------- Clock generator ----------------
    always #(CLK_PERIOD/2) clk = ~clk;        // Toggle every 5 ns -> 100 MHz

    // ---------------- Device(s) under test ----------------
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk      (clk),
        .rst      (rst),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (serial_line),              // TX drives the wire...
        .tx_busy  (tx_busy),
        .tx_done  (tx_done)
    );

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk      (clk),
        .rst      (rst),
        .rx       (serial_line),              // ...and RX listens to the same wire (loopback)
        .rx_data  (rx_data),
        .rx_done  (rx_done)
    );

    // ---------------- Task: send one byte and check it ----------------
    task send_and_check(input [7:0] value);
        begin
            @(posedge clk);                   // Line up with the clock
            while (tx_busy) @(posedge clk);   // Wait until the transmitter is free
            tx_data  <= value;                // Put the byte on the input
            tx_start <= 1'b1;                 // Raise start...
            @(posedge clk);
            tx_start <= 1'b0;                 // ...for exactly one clock

            @(posedge rx_done);               // Wait until the receiver has a byte
            #1;                               // Small delay so rx_data is settled

            if (rx_data === value) begin      // Compare received vs sent (=== also catches X)
                $display("[%t] PASS: sent 0x%h, received 0x%h", $time, value, rx_data);
                pass_count = pass_count + 1;
            end else begin
                $display("[%t] FAIL: sent 0x%h, received 0x%h", $time, value, rx_data);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ---------------- Main test sequence ----------------
    initial begin
        $dumpfile("uart.vcd");                // Name of the waveform file
        $dumpvars(0, tb_uart);                // Dump every signal in the testbench
        $timeformat(-9, 0, " ns", 10);        // Print %t times in nanoseconds

        // Bytes chosen to exercise different bit patterns
        test_bytes[0] = 8'h55;                // 0101_0101 alternating bits
        test_bytes[1] = 8'hAA;                // 1010_1010 alternating (opposite)
        test_bytes[2] = 8'h00;                // all zeros
        test_bytes[3] = 8'hFF;                // all ones
        test_bytes[4] = 8'hA5;                // mixed pattern
        test_bytes[5] = 8'h3C;                // 0011_1100
        test_bytes[6] = 8'h81;                // only MSB and LSB set
        test_bytes[7] = 8'h4B;                // ASCII 'K'

        repeat (5) @(posedge clk);            // Hold reset for a few clocks
        rst <= 1'b0;                          // Release reset
        repeat (5) @(posedge clk);            // Let things settle

        $display("--------------------------------------------------");
        $display(" UART loopback test: %0d bytes, CLKS_PER_BIT = %0d", NUM_TESTS, CLKS_PER_BIT);
        $display("--------------------------------------------------");

        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            send_and_check(test_bytes[i]);    // Send each byte and check it
        end

        repeat (CLKS_PER_BIT) @(posedge clk); // Let the TX stop bit finish in the waveform

        $display("--------------------------------------------------");
        $display(" SUMMARY: %0d passed, %0d failed, %0d total", pass_count, fail_count, NUM_TESTS);
        if (fail_count == 0)
            $display(" ALL TESTS PASSED");
        else
            $display(" SOME TESTS FAILED");
        $display("--------------------------------------------------");
        $finish;                              // End the simulation
    end

    // ---------------- Watchdog ----------------
    // If something hangs (e.g. rx_done never comes), stop instead of running forever.
    initial begin
        #(CLK_PERIOD * CLKS_PER_BIT * 10 * (NUM_TESTS + 2));  // Plenty of time for all frames
        $display("TIMEOUT: simulation took too long - FAIL");
        $finish;
    end

endmodule
