PROJ=n64_replay_device
TRELLIS?=/usr/local/share/trellis

all: ${PROJ}.bit

# Recipe edits must invalidate synthesis as well as the downstream artifacts.
${PROJ}.json: top.v pll.v glitch_filter.v n64_controller.v n64_receive_command.v n64_transmit_controller_state.v n64_transmit_identity.v n64_transmit_byte.v n64_transmit_bit.v UART_TX.v UART_RX.v n64_controller_reader.v n64_receive_controller_data.v n64_request.v and2.v xor2.v vlo.v vhi.v serial_handler.v queue_64.v queue_1024.v inv.v Makefile
	yosys -p "synth_ecp5 -json $@ -top top" top.v pll.v glitch_filter.v n64_controller.v n64_receive_command.v n64_transmit_controller_state.v n64_transmit_identity.v n64_transmit_byte.v n64_transmit_bit.v UART_TX.v UART_RX.v n64_controller_reader.v n64_receive_controller_data.v n64_request.v and2.v xor2.v vlo.v vhi.v serial_handler.v queue_64.v queue_1024.v inv.v

# Track consumed constraints and recipe edits; keep JSON first for $<.
%_out.config: %.json ecp5evn.lpf Makefile
	nextpnr-ecp5 --json $< --textcfg $@ --um5g-85k --package CABGA381 --lpf ecp5evn.lpf

# Packing options live in Makefile; keep the placement configuration first for $<.
%.bit: %_out.config Makefile
	ecppack --svf ${PROJ}.svf $< $@

${PROJ}.svf : ${PROJ}.bit

flash: ${PROJ}.bit
	openFPGALoader -b ecp5_evn -f $<

test: ${PROJ}.bit
	openFPGALoader -b ecp5_evn $<

clean:
	rm -f *.svf *.bit *.config *.json

.PHONY: prog clean
