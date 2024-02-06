PROJ=n64_replay_device
TRELLIS?=/usr/share/trellis

all: ${PROJ}.bit

${PROJ}.json: top.v pll.v glitch_filter.v n64_controller.v n64_receive_command.v n64_transmit_controller_state.v n64_transmit_identity.v n64_transmit_byte.v n64_transmit_bit.v UART_TX.v UART_RX.v n64_controller_reader.v n64_receive_controller_data.v n64_request.v and2.v xor2.v vlo.v vhi.v serial_handler.v queue_64.v queue_1024.v inv.v
	yosys -p "synth_ecp5 -json $@ -top top" top.v pll.v glitch_filter.v n64_controller.v n64_receive_command.v n64_transmit_controller_state.v n64_transmit_identity.v n64_transmit_byte.v n64_transmit_bit.v UART_TX.v UART_RX.v n64_controller_reader.v n64_receive_controller_data.v n64_request.v and2.v xor2.v vlo.v vhi.v serial_handler.v queue_64.v queue_1024.v inv.v

%_out.config: %.json
	nextpnr-ecp5 --json $< --textcfg $@ --um5g-85k --package CABGA381 --lpf ecp5evn.lpf

%.bit: %_out.config
	ecppack --svf ${PROJ}.svf $< $@

${PROJ}.svf : ${PROJ}.bit

flash: ${PROJ}.svf
	openocd -f ${TRELLIS}/misc/openocd/ecp5-evn.cfg -c "transport select jtag; init; svf $<; exit"

clean:
	rm -f *.svf *.bit *.config *.json

.PHONY: prog clean
