# Ultra64
So you want to control 64 N64s at once? No? But Grav does.

Change NUM_CONSOLES=1 to NUM_CONSOLES=N where 1 <= N <= 64, depending on how many consoles are plugged in. You can find the pin mappings in ecp5evn.lpf.

Contains modules for both reading N64 controllers and writing N64 controller data to a console

Synthesizes using prjtrellis (yosys + nextpnr for EPC5) for use on an LFE5UM5G-85F-EVN

Modify Makefile to contain the path to your trellis install
make to build
make flash for flashing the firmware onto the SPI flash for permanant memory
make test for flashing the bitstream in volatile memory
Requires openFPGALoader for flashing

Supports TAS playback using the same serial protocol as the TAStm32
Also supports controller passthrough

<!-- N01: document bounded parser recovery without reserving binary payload bytes. -->

UART recovery: commands use 115200 baud, 8N1 at the nominal 50 MHz clock.
Setup is `53 41 4D 80 xx` (hex); the final settings byte is ignored for N64.
Unsupported run, mode or controller fields return `FE` and abandon setup.
A transaction that waits 500,000 clocks (10 ms) without a received byte is
abandoned silently, including a stalled setup response. Only a complete accepted
`41` plus four-byte frame updates the frame output and writes the console queues.
All 256 byte values remain valid in each frame payload position, including `52`
and `AA`. Keep inter-byte receive intervals below 10 ms during a transaction.
A byte coincident with timeout expiry is discarded.

After an interrupted command or reconnect, stop sending and allow pending host
TX to drain, leave RX idle high for at least 20 ms, and discard stale replies.
Then send `52`, wait for `01 52`, send `AA`, and wait for `55` before starting a
new transaction. Retry this sequence after another quiet interval if replies
are missing. The quiet interval defines the new command boundary; sending reset
inside an unfinished binary frame cannot resynchronize it. Timeout alone does
not clear previously queued frames; reset does. Continuous traffic, serial noise
and physical UART framing faults are outside this recovery guarantee.

<!-- N01: provide a hardware-free regression entry point; make test programs hardware. -->
Run `python tests/run_serial_recovery.py` with Icarus Verilog (`iverilog`, `vvp`)
on PATH for parser recovery regression tests. Add `--default-timeout` to test
the production timeout instead of the accelerated test setting. Logs are written
to `validation/N01/`; the TX FIFO is a behavioral test substitute, while both
UART modules and the parser use repository RTL. `make` remains the FPGA build;
`make test` still programs the board and is not a simulation target.
