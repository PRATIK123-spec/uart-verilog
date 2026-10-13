@echo off
REM Compile, simulate, and open the waveform for the UART project
iverilog -g2005 -Wall -o uart_sim.vvp tb_uart.v uart_tx.v uart_rx.v || exit /b 1
vvp uart_sim.vvp || exit /b 1
start "" gtkwave uart.vcd uart.gtkw
