# Ultra64
So you want to control 64 N64s at once? No? But Grav does.

Contains modules for both reading N64 controllers and writing N64 controller data to a console

Synthesizes using prjtrellis (yosys + nextpnr for EPC5) for use on an LFE5UM5G-85F-EVN

Modify Makefile to contain the path to your trellis install
make to build
make flash for flashing the firmware onto the chip
Requires openocd for flashing

Supports TAS playback using the same serial protocol as the TAStm32
Also supports controller passthrough

