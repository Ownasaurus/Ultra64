"""Build the repository's all target in an isolated generated directory on Windows."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

# Explicit tool paths avoid duplicate PATH/Path entries in the Windows host.
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--tools", type=Path, required=True, help="OSS CAD Suite root")
parser.add_argument("--make", type=Path, required=True, help="GNU make executable")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
build = root / "validation/n03/generated/fpga"
build.mkdir(parents=True, exist_ok=True)

# Copy inputs only; do not modify recipes or the assigned source checkout.
for source in [*root.glob("*.v"), root / "Makefile", root / "ecp5evn.lpf"]:
    shutil.copyfile(source, build / source.name)
environment = {key: value for key, value in os.environ.items() if key.upper() != "PATH"}
environment["PATH"] = os.pathsep.join(str(path) for path in [
    args.tools / "bin", args.tools / "lib", args.make.parent, Path("C:/Windows/System32")])
environment["MSYS2_ARG_CONV_EXCL"] = "*"
# Use Make's native POSIX shell so quoted Yosys scripts stay one argument.
command = [str(args.make), f"SHELL={args.make.parent.as_posix()}/bash.exe", ".SHELLFLAGS=-c", "all"]

# Preserve complete synthesis, timing, placement/routing and packing output.
log = root / "validation/n03/build.log"
with log.open("w", encoding="utf-8") as output:
    output.write(f"cwd: {build}\ncommand: {command!r}\n")
    output.flush()
    result = subprocess.run(command, cwd=build, env=environment,
                            stdout=output, stderr=subprocess.STDOUT)
    output.write(f"\nBUILD_EXIT_CODE={result.returncode}\n")
print(log.read_text(encoding="utf-8")[-5000:])
# Check that a successful recipe actually produced the requested bitstream.
sys.exit(result.returncode or (not (build / "n64_replay_device.bit").is_file()))
