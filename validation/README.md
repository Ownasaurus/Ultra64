# N12 validation evidence

These files document only N12: stale incremental artifacts after constraint or
Makefile recipe edits. Scheduling fixtures are dummy files, not FPGA artifacts.

Source: `2f4bab11234cc2d5c1b452e51883447ff2831d10`, branch `N12-fix`.
Before editing, every tracked source file was compared byte-for-byte with that
commit. No repository AGENTS.md or ancestor AGENTS.md was found. The analysis
commit `ca9081a9bc9c672ddea2412f39dd6c272337b4fd` stores the report at
`analysis/findings.md`; `report/analysis/findings.md` does not exist there.
Reports were read with `git show` and were not modified.

The Makefile now tracks itself at synthesis, placement and packing, and tracks
`ecp5evn.lpf` at placement. JSON and placement configuration remain the first
prerequisites so `$<` still passes the intended input. An LPF edit rebuilds
placement and packing; a Makefile edit conservatively rebuilds all three stages.
Comments beside each dependency change explain its purpose.

## Checks and reproduction

- `n12-before.json`: four GNU Make 4.4.1 dry runs against an isolated pinned
  source copy reproduce N12 before edits. LPF and Makefile changes are ignored;
  the RTL positive control schedules all stages.
- `n12-pinned-regression.json` and `n12-pinned-regression.txt`: the new regression
  suite run against the unchanged pinned source fails as expected, demonstrating
  that the assertions detect the original dependency omissions.
- `n12-after.json`: all 28 scheduling invocations pass on the fixed Makefile.
  They cover current outputs, LPF-only, Makefile-only and RTL-only changes for
  `all`, `flash` and `test`, using both `-W` and actual edits with newer timestamps,
  plus direct artifact requests. Tests assert stage order and JSON/config inputs.
  Programming commands are printed only; no hardware is programmed.
- `n12-build.json`: an actual clean `make all` was attempted in an isolated copy.
  It exits 2 because `yosys` is unavailable (recipe error 127). `yosys`,
  `nextpnr-ecp5`, `ecppack` and `openFPGALoader` are absent from PATH; searches in
  the local MSYS, Lattice and project directories found no matching FPGA tools.
- `git diff --check` passes.

Run the regression suite from the repository root:

```powershell
python tests/test_make_dependencies.py --make C:/msys64/usr/bin/make.exe --log validation/n12-after.json
```

The suite uses Python's standard library and GNU Make; it does not require FPGA
tools. Use `--source PATH` to evaluate another isolated source copy. Existing
`make test` remains the repository's volatile hardware programming target.

## Limits

The required build was attempted but could not finish. Real LPF-only and
recipe-only incremental toolchain builds, generated pin mapping/options, timing,
and hardware programming remain unverified because the FPGA toolchain is absent.
No successful hardware build or programming result is claimed. Dependencies on
command-line overrides, environment variables, tool versions or external config
files beyond this Makefile and its consumed LPF are outside this fix.
