"""N09: compile and run real RTL regressions, retaining commands and output."""
import argparse
import pathlib
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--baseline", action="store_true", help="Reproduce against unmodified source")
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
logs = root / "validation" / "N09"
logs.mkdir(parents=True, exist_ok=True)
name = "baseline" if args.baseline else "response"
sources = ["n64_receive_controller_data.v"]
if not args.baseline:
    sources += ["n64_controller_reader.v", "glitch_filter.v", "n64_request.v",
                "n64_transmit_byte.v", "n64_transmit_bit.v"]
# Keep generated simulator binaries out of the committed validation evidence.
with tempfile.TemporaryDirectory(prefix="n09-") as temp:
    binary = str(pathlib.Path(temp) / "test.vvp")
    if args.baseline:
        # Read the pinned source without touching either checkout or analysis reports.
        gitfile = root / ".git"
        gitdir = (gitfile.read_text().strip().removeprefix("gitdir: ")
                  if gitfile.is_file() else str(gitfile))
        source = subprocess.check_output(["git", f"--git-dir={gitdir}", "show",
            "2f4bab11234cc2d5c1b452e51883447ff2831d10:n64_receive_controller_data.v"], cwd=root)
        pinned = pathlib.Path(temp) / "n64_receive_controller_data.v"
        pinned.write_bytes(source)
        sources = [str(pinned)]
    commands = [["iverilog", "-g2005", "-Wall", "-s", f"n09_{name}_tb", "-o", binary,
                 f"tests/n09_{name}_tb.v", *sources], ["vvp", binary]]
    with (logs / f"{name}.log").open("w", encoding="utf-8") as log:
        for command in commands:
            log.write("$ " + subprocess.list2cmdline(command) + "\n")
            result = subprocess.run(command, cwd=root, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT)
            print(result.stdout, end="")
            log.write(result.stdout + f"exit={result.returncode}\n")
            log.flush()
            if result.returncode:
                raise SystemExit(result.returncode)
