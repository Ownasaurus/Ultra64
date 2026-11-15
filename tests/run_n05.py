"""N05 validation runner: preserve command output and exit status without flashing.

Run with the OSS CAD Suite bin/lib and GNU Make on PATH. Generated build products
stay in a temporary copy; only reviewable UTF-8 evidence is kept in the worktree.
"""
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tempfile
import argparse

# An explicit tool root also avoids Windows environments with duplicate Path/PATH.
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--toolchain", type=Path, help="OSS CAD Suite root")
args = parser.parse_args()
if args.toolchain:
    os.environ["PATH"] = os.pathsep.join((str(args.toolchain / "bin"),
        str(args.toolchain / "lib"), os.environ.get("PATH", "")))

ROOT = Path(__file__).resolve().parents[1]
LOGS = ROOT / "validation" / "N05"
LOGS.mkdir(parents=True, exist_ok=True)
WORK = Path(tempfile.mkdtemp(prefix="ultra64-N05-"))
RESULTS = []


def run(label, command, cwd=WORK, expected_exit=0):
    # Keep failures as evidence and continue independent checks before failing.
    try:
        result = subprocess.run(command, cwd=cwd, text=True, capture_output=True)
        code, output = result.returncode, result.stdout + result.stderr
    except OSError as error:
        code, output = 127, str(error)
    # Normalize line endings/trailing whitespace for reviewable Git text logs.
    record = f"command: {command!r}\ncwd: {cwd}\nexit: {code}\n{output}"
    record = "\n".join(line.rstrip() for line in record.splitlines()).rstrip() + "\n"
    (LOGS / (label + ".log")).write_text(record, encoding="utf-8", newline="\n")
    RESULTS.append({"check": label, "exit": code, "expected_exit": expected_exit})
    print(label, code, flush=True)
    return code


# Copy tracked design inputs, leaving the user's source and build outputs intact.
for pattern in ("*.v", "*.lpf", "Makefile"):
    for source in ROOT.glob(pattern):
        shutil.copy2(source, WORK / source.name)
run("tools", ["yosys", "-V"])
run("iverilog-version", ["iverilog", "-V"])
run("nextpnr-version", ["nextpnr-ecp5", "--version"])
compiled = run("rtl-compile", ["iverilog", "-g2005", "-Wall", "-s", "n05_inputs_tb",
    "-o", "n05.vvp", str(ROOT / "tests" / "n05_inputs_tb.v"), "UART_RX.v",
    "glitch_filter.v", "n64_receive_command.v", "n64_receive_controller_data.v"])
if compiled == 0:
    run("rtl-simulation", ["vvp", "n05.vvp"])

# Prove that the same regression detects N05 on the assigned source, extracting
# blobs with read-only git show. No checkout or branch operation is performed.
baseline = WORK / "baseline"
baseline.mkdir()
for filename in ("UART_RX.v", "glitch_filter.v", "n64_receive_command.v", "n64_receive_controller_data.v"):
    blob = subprocess.check_output(["git", "show",
        "2f4bab11234cc2d5c1b452e51883447ff2831d10:" + filename], cwd=ROOT)
    (baseline / filename).write_bytes(blob)
baseline_compile = run("baseline-compile", ["iverilog", "-g2005", "-s", "n05_inputs_tb",
    "-o", "baseline.vvp", str(ROOT / "tests" / "n05_inputs_tb.v"), "UART_RX.v",
    "glitch_filter.v", "n64_receive_command.v", "n64_receive_controller_data.v"], cwd=baseline)
if baseline_compile == 0:
    run("baseline-detects-N05", ["vvp", "baseline.vvp"], cwd=baseline, expected_exit=1)
    assert "UART bypasses two-stage boundary" in (LOGS / "baseline-detects-N05.log").read_text(), \
        "Baseline failed for an unexpected reason"
# MSYS startup on this host resets PATH; explicitly export discovered tool folders
# inside that shell so Make runs the same binaries as the direct checks above.
if os.name == "nt":
    tool_dirs = {str(Path(shutil.which(tool)).parent).replace("\\", "/")
                 for tool in ("yosys", "nextpnr-ecp5", "ecppack") if shutil.which(tool)}
    # The Windows distribution loads shared libraries from its adjacent lib dir.
    if args.toolchain:
        tool_dirs.add(str(args.toolchain / "lib").replace("\\", "/"))
    posix_dirs = ["/" + path[0].lower() + path[2:] if path[1:2] == ":" else path
                  for path in sorted(tool_dirs)]
    run("build", ["C:/msys64/usr/bin/bash.exe", "-c",
        "export PATH=" + shlex.quote(":".join(posix_dirs)) + ':"$PATH"; exec /usr/bin/make all'])
else:
    run("build", ["make", "all"])

# Preserve an implementation netlist for programmatic CDC structure/placement QA.
# This second route requests JSON/report output absent from the production recipe.
if (WORK / "n64_replay_device.json").exists():
    run("implementation", ["nextpnr-ecp5", "--json", "n64_replay_device.json",
        "--textcfg", "n05.config", "--um5g-85k", "--package", "CABGA381",
        "--lpf", "ecp5evn.lpf", "--freq", "50", "--write", "n05-routed.json",
        "--report", "n05-timing.json"])
    if (WORK / "n05-routed.json").exists():
        run("netlist-cdc", [sys.executable, str(ROOT / "tests" / "check_n05_netlist.py"), str(WORK)])

(LOGS / "results.json").write_text(json.dumps({"temporary_build": str(WORK),
    "results": RESULTS}, indent=2) + "\n", encoding="utf-8", newline="\n")
raise SystemExit(any(item["exit"] != item["expected_exit"] for item in RESULTS))
