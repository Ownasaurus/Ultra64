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

<!-- N07: define starvation, observability and recovery as part of the host protocol. -->
### TAS underrun policy

A TAS poll requires a newly accepted FIFO read. Polling an empty queue releases the
N64 bus without a controller-state response and latches a fault for that console.
Later TAS polls remain silent until reset, even if the host refills the queue.
This deliberately stops a failed run instead of silently replaying cached data or
resuming at a shifted timeline. Identity requests and passthrough still work.

The optional UART command `U` (`55` hex), sent as a complete command in parser
IDLE, returns one byte: `00` means no console has latched an underrun; `B1` means
at least one has. It snapshots status when received, does not clear it, and sends
no unsolicited error bytes. Issue one query at a time and wait for its reply;
existing automatic `A` frame requests may also appear on the UART. Hosts should
check status during playback and treat `B1` as a failed run. Old hosts must treat
missing console responses as failure or adopt this query to diagnose starvation.

To recover, stop playback, send the existing `R` command, refill with fresh frames,
then restart the run from a known timeline. Reset clears every queue, fault and
cached frame and cancels dequeues still in the RAM pipeline. An already started
response finishes with its accepted frame; its cache is cleared afterward. An
empty poll concurrent with the first write still faults; that write cannot supply
the current poll. Keep console polls stopped until fresh data is buffered after
reset. Refilling alone never clears a fault. Shared replenishment and initial
prebuffer completion retain their existing behavior.

<!-- N07: make the regression requirements and non-programming command explicit. -->
### N07 regression tests

Install Icarus Verilog and provide the Lattice Diamond ECP5 Verilog simulation
library directory (`cae_library/simulation/verilog/ecp5u`):

```
make check-n07 ECP5_MODELS=/path/to/ecp5u
```

Alternatively run `python tests/run_n07.py --models /path/to/ecp5u --baseline`
to also demonstrate the assigned source commit's empty-startup failure. The
runner uses the real generated FIFOs and vendor RAM/logic models. A temporary
model copy adapts Diamond LUT4's `init` parameter name to the generated netlist's
`INIT`; the truth table is unchanged. Vendor models are not redistributed.
Logs are written to `validation/N07/simulation.log`. These tests do not program
hardware; the existing `make test` target does.
