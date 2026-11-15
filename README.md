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

<!-- N02: document the first-full startup boundary and independent polling policy. -->
Initial host buffering completes when the first console's 1024-frame queue fills.
Consoles may begin polling independently while buffering; simultaneous fullness
is not required. Further shared frames are rejected with buffer-overrun response
`B0` while any queue is full. Once every queue has space, the device requests a
shared frame (`A`) and waits for that frame before requesting another. The host
should stop its initial burst at the full boundary and service these requests.
The slowest console limits shared replenishment; a faster console can still drain
its queue if polling rates diverge indefinitely. Reset starts initial buffering again.

<!-- N02: provide a repeatable RTL regression command without programming hardware. -->
Run `python tests/run_n02.py --tool-root <oss-cad-suite> --logs validation/N02`
to test initial buffering with 1, 2 and 64 consoles using Icarus Verilog and the
suite's ECP5 simulation models. `make` remains the FPGA bitstream build command.
