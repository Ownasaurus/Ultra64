<!-- N09: implementation record and interpretation of retained validation evidence. -->
# N09 response integrity

The worktree began clean on `N09-fix`, at source commit
`2f4bab11234cc2d5c1b452e51883447ff2831d10`. Read-only `git show` reviewed
`analysis/findings.md`, `analysis/README.md` and `analysis/validation.md` at
`ca9081a9bc9c672ddea2412f39dd6c272337b4fd`. No applicable AGENTS.md was found
in this worktree or accessible parent instruction locations. Analysis reports
were treated as evidence and were not changed.

## Finding confirmed before editing RTL

The pinned receiver clears its output on reception, fills it incrementally,
and drops busy on either timeout. A two-microsecond pulse completes at any
position. The reader unconditionally copies the receiver word when busy ends.
The actual source RTL simulation in `baseline.log` receives eight one bits,
then times out high, exposing `ff000000`. This corroborates N09 independently
of the report's Python model. The baseline test runner extracts only the pinned
receiver with read-only Git; it does not edit a checkout.

## Solution

The receiver collects payload in `working_data` and updates its committed word
only after exactly 32 bits plus a controller stop in the existing low-width
window, `75 < clocks <= 125` at 50 MHz. Extra one/zero pulses, console stops,
early stops, invalid pulse widths and high/low timeouts finish without success.
`response_valid` clears on each accepted trigger and stays stable for that poll;
busy ending with validity low is failure. The reader publishes neutral input
on failure, releasing all buttons and centering both sticks. A later successful
poll restores input. Receiver storage itself retains the last complete word.

Integrated testing exposed the input filter's delayed request stop as a short
low pulse at receiver startup. Eight clocks of bounded turnaround let that
edge settle before arming the receiver, avoiding a false framing failure. This
does not wait indefinitely for a high bus. Every modified RTL block has an
explanatory comment. No other designated issue was implemented.

## Checks and reproduction

Run from the repository root with Icarus tools on PATH:

```text
python tests/run_n09.py --baseline
python tests/run_n09.py
python tests/build_n09.py --toolchain C:/Users/Justin/AppData/Local/Temp/ultra64-n04-tools/oss-cad-suite --make C:/msys64/usr/bin/make.exe
```

- `baseline.log`: PASS, original-source reproduction.
- `response.log`: PASS, 221 integrated polls through the real requester, filter,
  receiver and reader, without substitute modules. Prefix lengths 0 through 32
  exercise high timeout, low timeout and stop termination. Each fault is followed
  by a valid reconnect. Additional cases cover neutral/all-one/mixed payloads,
  invalid final stop widths, malformed payload pulses and reply delays of
  3/7/20/100/200 clocks after arming. Continuous monitors reject partial receiver
  publication and unexpected reader publication. Only the 16 ms inter-poll delay
  is shortened by the testbench. A watchdog bounds hangs.
- `build.log`: the unchanged Makefile's forced full-build recipes were obtained
  using `make -n -B all PROJ=...`, then all three were executed with native tool
  paths. Yosys synthesis and nextpnr placement/routing returned 0. ecppack failed
  with status `3221226356` (`0xC0000374`, Windows heap corruption), without output.
  **The full bitstream build did not pass.**
- `packer-control.log`: ecppack crashes with the identical status for a minimal
  `.device LFE5UM5G-85F` configuration containing no N09 logic. An explicit
  `--db` retry also crashed. This isolates a local packer/runtime limitation;
  there is no usable bitstream or hardware validation claim.
- Earlier Make/shell attempts are preserved in `build-*-attempt.log`. The first
  could not find yosys under MSYS; a cmd shell attempt returned 0 without running
  recipes; later attempts completed synthesis/routing but could not launch the
  packer successfully. They are diagnostic evidence, not successful builds.
- `review.log`: whitespace check, scope review and tool versions.

Toolchain: local OSS CAD Suite `20261115`; Icarus 14.0 development build
`s20260301-1055-ge6b789157-dirty`; Yosys `0.71+34` (`e419c4eef`);
nextpnr `0.11.1-92-g5e2718b6`; ecppack `1.4-88-g2d12005`; GNU Make 4.4.1.

## Warnings and limits

Icarus reports inherited timescales for existing modules. Synthesis reports
limited tri-state support and undriven existing debug outputs; nextpnr ignores
the existing `BLOCK JTAGPATHS` LPF command. Verilog identifiers named `byte`
produce lexer notices. No out-of-scope source was edited to silence them.
The existing build checks timing at its reported 12 MHz default; it is not a
new certification of the nominal 50 MHz design. No board, electrical, CDC,
metastability or external protocol-conformance tests were performed. Controller
stop timing follows the repository's two-microsecond transmitter implementation.
Very early physical responses and electrical hot-plug behavior remain hardware
validation work. The Makefile's `test` target flashes hardware and was not run.
FPGA/simulator binaries are kept local under ignored paths; textual evidence is
committed with line endings and trailing whitespace normalized for Git review.

## Changed files

- `n64_receive_controller_data.v`: private payload storage and explicit validity.
- `n64_controller_reader.v`: bounded turnaround and neutral failure policy.
- `README.md`: acceptance/failure policy and regression instructions.
- `tests/n09_baseline_tb.v`, `tests/n09_response_tb.v`: source reproduction and
  integrated regression.
- `tests/run_n09.py`, `tests/build_n09.py`: reproducible simulation and native
  execution of Make's full-build recipes, with retained logs.
- `validation/N09/`: this record, generated textual evidence and artifact ignore
  rules. Analysis reports and the source checkout were not modified.
