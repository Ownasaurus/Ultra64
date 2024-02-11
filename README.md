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

