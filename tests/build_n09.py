"""N09: run the repository's full Make build on Windows and retain its log."""
import argparse
import os
import pathlib
import subprocess
import shlex

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--toolchain", type=pathlib.Path, required=True)
parser.add_argument("--make", default="make")
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
evidence = root / "validation" / "N09"
artifacts = evidence / "artifacts"
artifacts.mkdir(parents=True, exist_ok=True)
env = os.environ.copy()
env["PATH"] = os.pathsep.join([str(args.toolchain / "bin"),
                              str(args.toolchain / "lib"), env["PATH"]])
# MSYS Make's native subprocess environment fails to launch ecppack here. Ask Make
# for its exact full-build recipes, then execute all three with native DLL paths.
command = [args.make, "-n", "-B", "all", "PROJ=validation/N09/artifacts/n64_replay_device"]
with (evidence / "build.log").open("w", encoding="utf-8") as log:
    log.write("$ " + subprocess.list2cmdline(command) + "\n")
    planned = subprocess.run(command, cwd=root, env=env, text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log.write(planned.stdout + f"exit={planned.returncode}\n")
    if planned.returncode:
        raise SystemExit(planned.returncode)
    recipes = [shlex.split(line) for line in planned.stdout.splitlines()
               if line.startswith(("yosys ", "nextpnr-ecp5 ", "ecppack "))]
    if [recipe[0] for recipe in recipes] != ["yosys", "nextpnr-ecp5", "ecppack"]:
        raise SystemExit("Unexpected Make recipes; inspect the log")
    for recipe in recipes:
        recipe[0] = str(args.toolchain / "bin" / (recipe[0] + ".exe"))
        log.write("$ " + subprocess.list2cmdline(recipe) + "\n")
        log.flush()
        result = subprocess.run(recipe, cwd=root, env=env, stdout=log,
                                stderr=subprocess.STDOUT)
        log.write(f"exit={result.returncode}\n")
        if result.returncode:
            raise SystemExit(result.returncode)
# Require real artifacts so a shell invocation that merely exits cannot pass.
for suffix in ("json", "bit", "svf"):
    artifact = artifacts / f"n64_replay_device.{suffix}"
    if not artifact.exists() or artifact.stat().st_size == 0:
        raise SystemExit(f"Missing build output: {artifact}")
print(f"Full Make recipe build passed; log: {evidence / 'build.log'}")
