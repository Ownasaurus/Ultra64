"""Run N03 RTL regressions; tool binaries must be on PATH."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

# Keep generated simulation artifacts separate from the preserved text evidence.
ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--baseline", action="store_true", help="test pinned source without editing it")
args = parser.parse_args()
build = ROOT / "validation" / "n03" / "generated"
build.mkdir(parents=True, exist_ok=True)
records = []


def run(command):
    """Preserve exact commands, exit codes and combined output."""
    result = subprocess.run([str(x) for x in command], cwd=ROOT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    records.append({"command": [str(x) for x in command], "exit_code": result.returncode,
                    "output": result.stdout})
    print(result.stdout, end="")
    return result.returncode


# Extract only the requested blob; the assigned checkout and analysis stay intact.
source = ROOT / "serial_handler.v"
if args.baseline:
    source = build / "baseline_serial_handler.v"
    source.write_bytes(subprocess.check_output([
        "git", "show", "2f4bab11234cc2d5c1b452e51883447ff2831d10:serial_handler.v"], cwd=ROOT))
simulation = build / ("baseline.vvp" if args.baseline else "fixed.vvp")
# The production RTL uses byte as an identifier, so compile as Verilog-2005.
failed = run(["iverilog", "-g2005", "-s", "n03_response_tb", "-o", simulation,
              ROOT / "tests/n03_response_tb.v", source, ROOT / "UART_TX.v", ROOT / "UART_RX.v"])
if not failed:
    if args.baseline:
        # A failing original-source ping on the automatic-request edge proves N03.
        failed = run(["vvp", simulation, "+kind=0", "+phase=2", "+stall=0"])
    else:
        for kind in range(8):
            for phase in range(3):
                # Overrun cannot coincide with all consoles requesting data.
                if kind == 2 and phase == 2:
                    continue
                failed |= run(["vvp", simulation, f"+kind={kind}", f"+phase={phase}", "+stall=0"])
            if kind != 2:
                failed |= run(["vvp", simulation, f"+kind={kind}", "+phase=2", "+stall=1"])
        # A coincident RX pulse must not swallow the producer's acknowledgement.
        failed |= run(["vvp", simulation, "+kind=0", "+phase=2", "+overlap=1"])
log = ROOT / "validation/n03" / ("baseline.json" if args.baseline else "regression.json")
log.write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")
sys.exit(bool(failed))
