"""N02: run actual handler/generated-FIFO RTL and retain compiler/simulator logs."""
import argparse
import os
from pathlib import Path
import subprocess
import shutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--tool-root", type=Path, required=True)
parser.add_argument("--logs", type=Path, required=True)
args = parser.parse_args()
root = args.tool_root.resolve()
args.logs.mkdir(parents=True, exist_ok=True)
# Both executable and shared-library paths are needed by the Windows suite.
env = os.environ.copy()
env["PATH"] = os.pathsep.join([str(root / "bin"), str(root / "lib"), env["PATH"]])
models = root / "share/yosys/ecp5"
sources = ["tests/n02_prebuffer.v", "serial_handler.v", "UART_TX.v", "UART_RX.v",
           "queue_64.v", "queue_1024.v", "and2.v", "xor2.v", "inv.v",
           str(models / "cells_sim.v")]
# Keep compiled artifacts temporary; only readable validation evidence is retained.
import tempfile
with tempfile.TemporaryDirectory(prefix="n02-sim-") as temp:
    for count in (1, 2, 64):
        image = str(Path(temp) / f"n02-{count}.vvp")
        commands = [
            ["iverilog", "-g2005", "-s", "n02_prebuffer", "-I", str(models),
             f"-Pn02_prebuffer.N={count}", "-o", image, *sources],
            ["vvp", image],
        ]
        for stage, command in zip(("compile", "run"), commands):
            # Windows resolves executable names before applying the child env.
            command[0] = shutil.which(command[0], path=env["PATH"]) or command[0]
            result = subprocess.run(command, env=env, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True)
            log = f"Command: {command!r}\nExit: {result.returncode}\n{result.stdout}"
            (args.logs / f"fixed-{count}-{stage}.log").write_text(log, encoding="utf-8")
            print(log, end="")
            if result.returncode:
                raise SystemExit(result.returncode)
