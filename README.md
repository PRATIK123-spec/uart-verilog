# UART Transmitter & Receiver in Verilog

A synthesizable UART (8N1) transmitter and receiver written in Verilog-2005, verified with a self-checking loopback testbench in Icarus Verilog. Default configuration is **115,200 baud on a 100 MHz clock**.

## Features

- **8N1 framing**: 1 start bit, 8 data bits (LSB first), no parity, 1 stop bit
- **Parameterized baud rate** via `CLKS_PER_BIT` (`clock_freq / baud`, e.g. 868 for 115,200 baud at 100 MHz)
- **4-state FSM** (IDLE → START → DATA → STOP) in both TX and RX
- **Mid-bit sampling** in the receiver for maximum timing margin
- **Start-bit glitch rejection**: the start bit is re-checked at its midpoint
- **2-flip-flop synchronizer** on the RX input to guard against metastability
- Handshake signals: `tx_busy`, `tx_done`, `rx_done` (single-cycle pulses)
- Self-checking testbench with PASS/FAIL summary and a timeout watchdog

## Block Diagram

```
                    +-------------------+                      +-------------------+
  tx_data[7:0] ---->|                   |                      |                   |----> rx_data[7:0]
  tx_start     ---->|     uart_tx       |  tx    serial_line   |     uart_rx       |----> rx_done
                    |  (FSM + baud ctr) |--------------------->| (sync + FSM +     |
  tx_busy     <-----|                   |                      |  baud ctr)        |
  tx_done     <-----|                   |                      |                   |
                    +-------------------+                      +-------------------+
                          ^     ^                                    ^     ^
                         clk   rst                                  clk   rst
```

### Frame format (byte `0x4B`, sent LSB first)

```
 Bit:     idle  START  D0   D1   D2   D3   D4   D5   D6   D7   STOP  idle
 Value:    1      0    1    1    0    1    0    0    1    0     1     1

         ──────┐    ┌─────────┐    ┌────┐         ┌────┐    ┌──────────────
 Line:         │    │         │    │    │         │    │    │
               └────┘         └────┘    └─────────┘    └────┘
                 ^    ^    ^    ^    ^    ^    ^    ^    ^    ^   <- RX sample points (mid-bit)
               |<-->|
             1 bit = 868 clocks = 8.68 µs
```

### FSM

```
   ┌──────┐  tx_start / falling edge  ┌───────┐  1 bit  ┌──────┐  8 bits  ┌──────┐
┌─►│ IDLE ├──────────────────────────►│ START ├────────►│ DATA ├─────────►│ STOP │
│  └──────┘                           └───────┘         └──────┘          └──┬───┘
└────────────────────────────────────────────────────────────────────────────┘
```

The receiver waits `CLKS_PER_BIT/2` clocks after the falling edge to reach the middle of the start bit, then `CLKS_PER_BIT` clocks between each subsequent sample, so every sample lands mid-bit.

## File Structure

```
uart-verilog/
├── uart_tx.v     # UART transmitter
├── uart_rx.v     # UART receiver (with 2-FF synchronizer)
├── tb_uart.v     # Self-checking loopback testbench
├── uart.gtkw     # GTKWave signal layout
├── run.bat       # One-click compile + simulate + view (Windows)
└── README.md
```

## Running the Simulation

Requires [Icarus Verilog](https://steveicarus.github.io/iverilog/) and optionally [GTKWave](https://gtkwave.sourceforge.net/).

**Windows:** double-click `run.bat`.

**Any platform:**

```bash
iverilog -g2005 -Wall -o uart_sim.vvp tb_uart.v uart_tx.v uart_rx.v
vvp uart_sim.vvp
gtkwave uart.vcd uart.gtkw      # optional: view waveform
```

The testbench connects `uart_tx` directly to `uart_rx` (loopback) and sends 8 bytes chosen to cover alternating bits, all-zeros, all-ones, and MSB/LSB edge cases: `0x55, 0xAA, 0x00, 0xFF, 0xA5, 0x3C, 0x81, 0x4B`.

## Test Results

```
--------------------------------------------------
 UART loopback test: 8 bytes, CLKS_PER_BIT = 868
--------------------------------------------------
[  82616 ns] PASS: sent 0x55, received 0x55
[ 169436 ns] PASS: sent 0xaa, received 0xaa
[ 256256 ns] PASS: sent 0x00, received 0x00
[ 343076 ns] PASS: sent 0xff, received 0xff
[ 429896 ns] PASS: sent 0xa5, received 0xa5
[ 516716 ns] PASS: sent 0x3c, received 0x3c
[ 603536 ns] PASS: sent 0x81, received 0x81
[ 690356 ns] PASS: sent 0x4b, received 0x4b
--------------------------------------------------
 SUMMARY: 8 passed, 0 failed, 8 total
 ALL TESTS PASSED
--------------------------------------------------
```

Each frame takes ~86.8 µs (10 bits × 8.68 µs), matching the expected 115,200 baud timing.

## Author

Protik Dey
