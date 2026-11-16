"""N12 regression: evaluate GNU Make scheduling without running FPGA tools.

Run: python tests/test_make_dependencies.py --make /path/to/make --log results.json
Fixtures contain dummy outputs; these checks establish dependencies, not FPGA validity.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


# Accept an alternate source tree so the same assertions can check the pinned source.
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--make", default=os.environ.get("MAKE", "make"))
parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument("--log", type=Path)
options = parser.parse_args()
records = []
project = "n64_replay_device"
tools = ("yosys", "nextpnr-ecp5", "ecppack", "openFPGALoader")


class MakeDependencies(unittest.TestCase):
    # Separate timestamps avoid dependence on filesystem timestamp resolution.
    def fixture(self, directory):
        root = Path(directory)
        old = int(time.time()) - 1000
        for source in [options.source / "Makefile", *options.source.glob("*.v"),
                       options.source / "ecp5evn.lpf"]:
            target = root / source.name
            shutil.copyfile(source, target)
            os.utime(target, (old, old))
        for suffix in (".json", "_out.config", ".bit"):
            target = root / (project + suffix)
            target.write_text("Scheduling fixture only; not an FPGA artifact.\n")
            os.utime(target, (old + 100, old + 100))
        return root, old + 200

    def check_schedule(self, target, changed, mode, expected):
        with tempfile.TemporaryDirectory(prefix="n12-make-") as directory:
            root, newer = self.fixture(directory)
            command = [options.make, "-n", "-r", "--no-print-directory"]
            if changed and mode == "assume-new":
                command += ["-W", changed]
            elif changed:
                # Exercise a real edit as well as Make's -W dependency evaluation.
                with (root / changed).open("a") as stream:
                    stream.write("\n// N12 timestamp fixture\n" if changed.endswith(".v")
                                 else "\n# N12 timestamp fixture\n")
                os.utime(root / changed, (newer, newer))
            command.append(target)
            result = subprocess.run(command, cwd=root, capture_output=True, text=True)
            records.append(dict(command=command, changed=changed, mode=mode,
                                returncode=result.returncode, stdout=result.stdout,
                                stderr=result.stderr))
            self.assertEqual(result.returncode, 0, result.stderr)
            lines = result.stdout.splitlines()
            actual = [line.split()[0] for line in lines
                      if line.split() and line.split()[0] in tools]
            self.assertEqual(actual, expected, result.stdout)
            # Guard $<: added prerequisites must not replace the actual stage input.
            if "nextpnr-ecp5" in actual:
                self.assertIn("--json " + project + ".json --textcfg " + project
                              + "_out.config", result.stdout)
                self.assertIn("--lpf ecp5evn.lpf", result.stdout)
            if "ecppack" in actual:
                self.assertIn(project + "_out.config " + project + ".bit", result.stdout)

    def test_incremental_builds_and_programming_targets(self):
        # Both programming targets must rebuild stale artifacts before programming.
        for target in ("all", "flash", "test"):
            programming = ["openFPGALoader"] if target != "all" else []
            for mode in ("assume-new", "edit"):
                for changed, stages in (
                    (None, []),
                    ("ecp5evn.lpf", ["nextpnr-ecp5", "ecppack"]),
                    ("Makefile", ["yosys", "nextpnr-ecp5", "ecppack"]),
                    ("top.v", ["yosys", "nextpnr-ecp5", "ecppack"]),
                ):
                    with self.subTest(target=target, changed=changed, mode=mode):
                        self.check_schedule(target, changed, mode, stages + programming)

    def test_direct_artifact_targets(self):
        # Check each stage's own recipe dependency, including already-current inputs.
        for suffix, stages in (
            (".json", ["yosys"]),
            ("_out.config", ["yosys", "nextpnr-ecp5"]),
            (".bit", ["yosys", "nextpnr-ecp5", "ecppack"]),
        ):
            with self.subTest(suffix=suffix):
                self.check_schedule(project + suffix, "Makefile", "edit", stages)
        # Constraints should not force an otherwise-current synthesis to run again.
        self.check_schedule(project + ".json", "ecp5evn.lpf", "edit", [])


# Preserve exact Make output even if an assertion fails; use LF for portable logs.
if __name__ == "__main__":
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(MakeDependencies))
    if options.log:
        options.log.write_text(json.dumps({"source": str(options.source.resolve()),
                                          "successful": result.wasSuccessful(),
                                          "runs": records}, indent=2) + "\n", newline="\n")
    raise SystemExit(0 if result.wasSuccessful() else 1)
