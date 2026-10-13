# UART in Verilog: A Beginner's Explanation

This project builds a **UART transmitter** and **UART receiver** in Verilog, connects them together in a testbench ("loopback"), and checks that every byte sent comes back correctly.

| File | What it is |
|------|------------|
| `uart_tx.v` | Transmitter: turns a byte into a serial bit stream |
| `uart_rx.v` | Receiver: turns a serial bit stream back into a byte |
| `tb_uart.v` | Testbench: sends 8 bytes TX → RX and prints PASS/FAIL |
| `uart.gtkw` | GTKWave layout (which signals to show) |
| `run.bat` | One-click compile + simulate + open waveform |

To run everything: double-click `run.bat`, or in a terminal:

```
iverilog -g2005 -Wall -o uart_sim.vvp tb_uart.v uart_tx.v uart_rx.v
vvp uart_sim.vvp
gtkwave uart.vcd uart.gtkw
```

---

## 1. What is UART?

**UART** = *Universal Asynchronous Receiver/Transmitter*. It's one of the simplest ways for two chips to talk to each other. You've used it if you've ever printed to a "serial monitor" on an Arduino.

- **Serial**: bits are sent one after another on a **single wire**.
- **Asynchronous**: there is **no shared clock wire**. Both sides agree in advance on how fast bits are sent (the **baud rate**, in bits per second) and each side uses its own clock to time things.
- A full-duplex link uses two wires: one TX → RX in each direction (plus ground).

Since there's no clock wire, the receiver needs a way to know **when a byte starts**. UART solves this with a **start bit**.

### The rules (8N1)

"8N1" means **8** data bits, **N**o parity bit, **1** stop bit.

1. When nothing is being sent, the line sits at **1 (HIGH)**. This is called **idle**.
2. To begin a byte, the transmitter pulls the line **LOW for one bit time**. This is the **start bit**.
3. Then it sends the **8 data bits, least-significant bit (LSB) first**.
4. Finally it drives the line **HIGH for one bit time**. This is the **stop bit**.
5. The line can then stay idle, or a new start bit can follow right away.

So every byte takes **10 bit times** on the wire: 1 start + 8 data + 1 stop.

---

## 2. Frame diagram

Sending the byte **0x4B** = binary `0100_1011`. LSB first means the bits go out in the order `1,1,0,1,0,0,1,0`:

```
 Bit:     idle  START  D0   D1   D2   D3   D4   D5   D6   D7   STOP  idle
 Value:    1      0    1    1    0    1    0    0    1    0     1     1

         ──────┐    ┌─────────┐    ┌────┐         ┌────┐    ┌──────────────
 Line:         │    │         │    │    │         │    │    │
               └────┘         └────┘    └─────────┘    └────┘
               |<-->|
             1 bit time = 868 clock cycles = 8.68 µs
```

Where the receiver samples (the middle of each bit, marked `^`):

```
         ──────┐    ┌─────────┐    ┌────┐         ┌────┐    ┌──────────────
               │    │         │    │    │         │    │    │
               └────┘         └────┘    └─────────┘    └────┘
                 ^    ^    ^    ^    ^    ^    ^    ^    ^    ^
               start D0   D1   D2   D3   D4   D5   D6   D7  stop
             (check)
```

---

## 3. The baud counter: turning a fast clock into slow bits

Our FPGA clock is **100 MHz** (100,000,000 ticks per second). The UART speed is **115,200 baud** (bits per second). How many clock ticks fit in one bit?

```
CLKS_PER_BIT = 100,000,000 / 115,200 = 868.05  →  868
```

So each bit must be held on the line for **868 clock cycles**. Both modules have a counter called `clk_count` that counts `0, 1, 2, …, 867`. When it reaches `CLKS_PER_BIT - 1` (867), one bit time has passed. The counter resets to 0 and the FSM moves on to the next bit.

`CLKS_PER_BIT` is a **parameter**, so you can change the baud rate without touching the logic. For 9600 baud at 100 MHz, use `100_000_000 / 9600 = 10417`.

> Rounding 868.05 to 868 makes our bits 0.006% too short. UART can tolerate a few percent of mismatch, so this is fine.

---

## 4. What is an FSM?

An **FSM (Finite State Machine)** is a circuit that is always in exactly **one state** out of a small list. On each clock edge it looks at its inputs and decides whether to stay or move to another state. It's like a flowchart built in hardware.

Both TX and RX use the same four states:

```
          ┌──────┐   start   ┌───────┐  1 bit   ┌──────┐  8 bits  ┌──────┐
   ┌─────►│ IDLE ├──────────►│ START ├─────────►│ DATA ├─────────►│ STOP │
   │      └──────┘           └───────┘          └──────┘          └──┬───┘
   │                                                                  │
   └──────────────────────────────────────────────────────────────────┘
                                 1 bit time done
```

The states are 2-bit numbers (`IDLE=0, START=1, DATA=2, STOP=3`) given readable names with `localparam`.

### Transmitter states (`uart_tx.v`)

| State | What the line does | When it leaves |
|-------|--------------------|----------------|
| **IDLE** | Holds `tx = 1`. Clears counters. | When `tx_start = 1`: copies `tx_data` into `data_reg`, sets `tx_busy`, goes to START. |
| **START** | Holds `tx = 0` (start bit). | After 868 clocks, goes to DATA. |
| **DATA** | Outputs `data_reg[bit_index]`, holding each bit 868 clocks. `bit_index` goes 0 → 7. | After bit 7 finishes, goes to STOP. |
| **STOP** | Holds `tx = 1` (stop bit). | After 868 clocks: pulses `tx_done`, clears `tx_busy`, goes to IDLE. |

### Receiver states (`uart_rx.v`)

| State | What it does | When it leaves |
|-------|--------------|----------------|
| **IDLE** | Watches the line. | When the line goes **LOW** (possible start bit), goes to START. |
| **START** | Waits **half** a bit time (434 clocks) to reach the **middle** of the start bit, then checks the line again. | Still LOW → real start bit, go to DATA. HIGH → it was a glitch, go back to IDLE. |
| **DATA** | Waits **one full** bit time (868 clocks), which lands in the middle of the next bit, and samples it into `data_reg[bit_index]`. Repeats 8 times. | After bit 7 is sampled, goes to STOP. |
| **STOP** | Waits one more bit time to reach the middle of the stop bit. | Copies `data_reg` to `rx_data`, pulses `rx_done`, goes to IDLE. |

---

## 5. Mid-bit sampling: why and how

**Why the middle?** The edges of a bit are where things are messy. The signal is changing, the two sides' clocks might be slightly different, and the wire may have noise or slow rise times. The **middle** of the bit is the point farthest from both edges, so it's the safest place to read the value.

**How we get there:**

1. The receiver sees the falling edge at the start of the start bit.
2. It waits **CLKS_PER_BIT / 2 = 434** clocks → now it's in the **middle of the start bit**.
3. From there, every **868** clocks lands exactly in the **middle of the next bit** (D0, D1, … D7, STOP).

```
 falling edge
     │<- 434 ->│<----- 868 ----->│<----- 868 ----->│ ...
     │         ^                 ^                 ^
     │      middle of         middle of         middle of
     │       START               D0                D1
```

Because the receiver re-synchronizes on **every** start bit, small clock differences only build up over 10 bits and never across bytes. That's what makes "asynchronous" communication work.

### The 2-flip-flop synchronizer

The `rx` wire comes from another device that has its own clock, so it can change at **any** moment, including right on our clock edge. When that happens, a flip-flop can become **metastable** (stuck halfway between 0 and 1 for a short time). To protect the FSM, `rx` passes through **two flip-flops** (`rx_meta` → `rx_sync`) before it is used. The second flop gives the first one a full clock cycle to settle. This adds 2 clocks of delay, which is tiny compared to 868.

---

## 6. File walkthrough

### `uart_tx.v` (transmitter)

- **Parameter** `CLKS_PER_BIT = 868`.
- **Ports**:
  - `clk`, `rst`: clock and synchronous active-high reset.
  - `tx_start`: pulse high for one clock to send a byte.
  - `tx_data[7:0]`: the byte to send.
  - `tx`: the serial output wire.
  - `tx_busy`: 1 while sending. Don't start a new byte while it's high.
  - `tx_done`: one-clock pulse at the end of the stop bit.
- **Internal registers**: `state`, `clk_count` (baud counter), `bit_index` (0–7), and `data_reg`. `data_reg` is a saved copy of the byte so the user can change `tx_data` mid-frame without corrupting it.
- **One `always @(posedge clk)` block** holds the whole FSM. Reset puts `tx = 1` (idle HIGH). At the top of the non-reset branch, `tx_done <= 0` is a *default*: it only becomes 1 for the single cycle where STOP finishes.
- `tx <= data_reg[bit_index]` sends the bits **LSB first**, because `bit_index` counts up from 0.

### `uart_rx.v` (receiver)

- **Parameter** `CLKS_PER_BIT = 868`.
- **Ports**: `clk`, `rst`, `rx` (serial input), `rx_data[7:0]` (received byte), `rx_done` (one-clock pulse when `rx_data` is valid).
- **Synchronizer**: a small `always` block shifts `rx → rx_meta → rx_sync`. The FSM only ever looks at `rx_sync`.
- **FSM**: IDLE detects the falling edge. START waits half a bit and confirms the start bit (this rejects short glitches). DATA waits a full bit each time and stores `data_reg[bit_index] <= rx_sync`. STOP waits for the middle of the stop bit, then outputs the byte.
- `rx_done` pulses in the middle of the stop bit. It doesn't wait for the stop bit to end, which leaves the receiver ready in IDLE before the next start bit can arrive.

### `tb_uart.v` (testbench)

- Generates a **100 MHz clock**: `always #5 clk = ~clk;` (5 ns high, 5 ns low).
- Instantiates `uart_tx` and `uart_rx` and connects TX's output to RX's input through one wire, `serial_line`. This is the **loopback**.
- **Task `send_and_check(value)`**:
  1. Waits until `tx_busy` is 0.
  2. Puts `value` on `tx_data` and pulses `tx_start` for one clock.
  3. Waits for `@(posedge rx_done)`.
  4. Compares `rx_data === value` and prints **PASS** or **FAIL**. `===` also catches unknown `X` values.
- **Test bytes**: `0x55, 0xAA, 0x00, 0xFF, 0xA5, 0x3C, 0x81, 0x4B`. These cover alternating bits, all zeros, all ones, and edge bits (MSB/LSB only).
- Prints a **summary** (passed / failed / total).
- `$dumpfile("uart.vcd")` + `$dumpvars(0, tb_uart)` records every signal into a waveform file.
- A **watchdog** `initial` block ends the simulation with TIMEOUT if something hangs (for example, if `rx_done` never comes).

### Expected output

```
--------------------------------------------------
 UART loopback test: 8 bytes, CLKS_PER_BIT = 868
--------------------------------------------------
[  82616 ns] PASS: sent 0x55, received 0x55
[ 169436 ns] PASS: sent 0xaa, received 0xaa
...
[ 690356 ns] PASS: sent 0x4b, received 0x4b
--------------------------------------------------
 SUMMARY: 8 passed, 0 failed, 8 total
 ALL TESTS PASSED
--------------------------------------------------
```

Each byte takes about 86.8 µs (10 bits × 8.68 µs). That's why the times step by ~86,820 ns.

---

## 7. Reading the waveform in GTKWave

`uart.gtkw` opens with the signals already arranged. Things to look at:

1. **Zoom to fit** (the magnifier-with-box icon, or `Ctrl+Alt+F` / menu *Time → Zoom → Zoom Best Fit*). You'll see 8 frames on `serial_line`.
2. **Zoom into one frame.** Find the falling edge (start bit), then 8 data bits, then the HIGH stop bit.
3. **`u_tx.state` / `u_rx.state`**: watch them go 0 → 1 → 2 → 3 → 0 (IDLE → START → DATA → STOP → IDLE).
4. **`u_rx.clk_count`**: in START it ramps to 433, then in DATA it ramps to 867 repeatedly. Every time it wraps, a bit is sampled. Notice these sample points sit in the middle of TX's bits.
5. **`rx_done`**: a single thin pulse per byte. `rx_data` changes to the new byte at that moment.

Tip: right-click a bus like `rx_data` → *Data Format → Hex* or *Binary* to change how it's displayed.
