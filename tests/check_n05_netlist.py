"""N05 synthesis/placement QA: reject raw-input bypasses or first-stage fanout.

Report exact placed FF sites for review; this is not an analog MTBF calculation.
"""
import json
from pathlib import Path
import sys

work = Path(sys.argv[1])
synth = json.loads((work / "n64_replay_device.json").read_text())["modules"]["top"]
routed = json.loads((work / "n05-routed.json").read_text())["modules"]["top"]
pairs = []
for name, cell in synth["cells"].items():
    # Inspect mapped flops rather than trusting source attributes or names alone.
    if cell["type"] != "TRELLIS_FF" or not name.endswith(("line_meta_TRELLIS_FF_Q", "rx_meta_TRELLIS_FF_Q")):
        continue
    second_name = name.replace("_meta_TRELLIS_FF_Q", "_sync_TRELLIS_FF_Q")
    second = synth["cells"][second_name]
    assert second["type"] == "TRELLIS_FF"
    assert cell["connections"]["CLK"] == second["connections"]["CLK"]
    assert cell["connections"]["Q"] == second["connections"]["DI"]
    bit = cell["connections"]["Q"][0]
    sinks = [(n, port) for n, c in synth["cells"].items()
             for port, bits in c["connections"].items()
             if c["port_directions"][port] == "input" and bit in bits]
    assert sinks == [(second_name, "DI")], sinks
    for stage in (cell, second):
        assert stage["parameters"]["REGSET"] == "SET"
    pairs.append({"first": name, "second": second_name,
        "first_site": routed["cells"][name]["attributes"]["NEXTPNR_BEL"],
        "second_site": routed["cells"][second_name]["attributes"]["NEXTPNR_BEL"]})

# Default top has UART, button, one console and the physical-controller input.
assert len(pairs) == 4, pairs
for port in ("rx_uart", "button", "n64", "n64real"):
    bit = synth["ports"][port]["bits"][0]
    sinks = [(n, p) for n, c in synth["cells"].items()
             for p, bits in c["connections"].items()
             if c["port_directions"][p] == "input" and bit in bits]
    assert len(sinks) == 1 and sinks[0][1] == "DI", (port, sinks)
    assert sinks[0][0] in {pair["first"] for pair in pairs}, (port, sinks)
timing = json.loads((work / "n05-timing.json").read_text())["fmax"]
assert timing and all(clock["achieved"] >= 50 for clock in timing.values())
print(json.dumps({"pairs": pairs, "fmax": timing}, indent=2))
print("PASS: four preserved two-flop boundaries, exclusive first-stage fanout, timed at 50 MHz")
