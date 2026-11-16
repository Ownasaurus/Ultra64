# N10 fix and validation

Validated on 2026-11-15 in the isolated `N10-fix` worktree. Initial HEAD was
`2f4bab11234cc2d5c1b452e51883447ff2831d10`, with a clean working tree.
The finding and related validation/overview were read with read-only `git show`
at analysis commit `ca9081a9bc9c672ddea2412f39dd6c272337b4fd`.
No applicable AGENTS.md was found in the worktree or its ancestor directories.
Only N10 is changed; analysis reports, wrapper, Makefile and other issue areas
remain untouched.

## Confirmation and solution

The original receiver never counts high time in `waiting_for_low`; its partial
byte and position survive indefinitely. It also accepts two-microsecond pulses
at any position and accepts a ninth zero as termination. The wrapper responds
when `receiving` falls, without an independent validity signal.

The new wrapper regression, compiled with the original receiver extracted by
`git show 2f4bab11234cc2d5c1b452e51883447ff2831d10:n64_receive_command.v`,
fails on the exact seven-zero-prefix, 1000-clock-high-gap, new-poll sequence.
[baseline-wrapper.log](baseline-wrapper.log) records the unsolicited response
while the console is still transmitting (exit 1, expected negative control).
All other RTL in that run is unchanged from the assigned source.

`n64_receive_command.v` now implements these rules, with explanatory comments:

- Idle before the first bit remains unlimited. Once a bit has arrived, 200
  consecutive high samples (4 us at 50 MHz) discard the incomplete byte,
  including eight data bits without a stop.
- Exactly eight data bits and a console stop low in the existing one-microsecond
  acceptance window (26 through 75 clocks) are required for success. A controller
  stop (76 through 125 clocks), ninth zero, invalid pulse or stuck low fails.
  A one-microsecond pulse before bit eight is indistinguishable from data;
  it remains data, and a subsequent timeout discards the incomplete command.
- Malformed pulses enter resynchronization. All subsequent traffic is ignored
  until 200 continuous high samples; any low restarts that recovery interval.
  A partial-byte high timeout already satisfies this idle boundary.
- Partial data stays private. Only a valid stop publishes `command` and lowers
  `receiving`. Errors keep listening with `receiving` asserted, so the existing
  wrapper never schedules an error response and needs no interface change.

The pulse and gap counters are eight bits; the timing parameters retain the
existing 50 MHz assumptions and the new timeout defaults to 200 clocks.

## Checks and reproduction

The portable regression command is `python tests/run_n10.py` with Icarus on
PATH. This host used the explicit temporary tool directory:

```powershell
python tests/run_n10.py --iverilog "$env:TEMP/n10-fpga-tools/ucrt64/bin"
python tests/run_n10.py --iverilog "$env:TEMP/n10-fpga-tools/ucrt64/bin" --receiver-source "$env:TEMP/n10-original-receiver.v" --only wrapper --log validation/N10/baseline-wrapper.log
python tests/build_n10.py --tool-bin "$env:TEMP/n10-fpga-tools/ucrt64/bin" --make C:/msys64/usr/bin/make.exe --timing-mhz 50
```

The negative control requires extracting the original receiver first; the runner
never changes the checkout. The build helper copies build inputs to temporary
space and runs the repository's unmodified `make all`, followed by an explicit
50 MHz nextpnr check with the same device, package and pin constraints.

| Check | Result | Evidence |
| --- | --- | --- |
| Original receiver with interrupted-prefix wrapper test | Expected failure, exit 1 | [baseline-wrapper.log](baseline-wrapper.log) |
| Receiver RTL | PASS: 427 checks, 345 valid completions | [rtl.log](rtl.log) |
| Filter/wrapper/real transmitters | PASS: 45 identity and 10 poll responses; no premature response | [rtl.log](rtl.log) |
| Native `make all`: Yosys, nextpnr, ecppack | PASS, exit 0; bitstream hash recorded | [build.log](build.log) |
| Explicit 50 MHz place and route | PASS, exit 0; routed maximum 188.57 MHz | [build.log](build.log) |
| Git whitespace check | PASS: `git diff --check` | [review.log](review.log) |

Receiver tests cover every truncation position 0 through 8, early/malformed
stops, invalid widths 25/76/100/125/176/1000 clocks, residual traffic during
recovery, a ninth zero, valid width endpoints 26/75/126/175, exact high-gap
boundaries 199/200, unlimited initial idle and all 256 command byte values.
The wrapper tests exercise every truncation position, malformed widths
76/125/176/1000, the exact reported prefix sequence and recovery to 00/01/FF.
Their FIFO stub supplies stable data; the filter, receiver, wrapper and all
transmitters are real RTL. The tests assert response scheduling and absence of
premature output; they do not decode every transmitted response bit.

Tool versions are preserved in [tool-versions.log](tool-versions.log).
Captured logs use LF line endings with trailing padding removed; all tool
messages are retained. Official
MSYS2 packages were unpacked only into a temporary tool directory; URLs and
SHA256 hashes appear in [tools.json](tools.json). No system installation or
hardware programming was performed. The first ModelSim attempt could compile
but could not simulate because its license expired; that failure is retained in
[modelsim-unavailable.log](modelsim-unavailable.log). The first FPGA build
passed synthesis but lacked a nextpnr runtime dependency; its full log is
[build-missing-runtime.log](build-missing-runtime.log). After supplying the
temporary dependency, the complete build and explicit timing check passed.

## Limits and changed files

The native build uses a 12 MHz timing target, so the additional 50 MHz run checks
the receiver's intended clock. Build warnings concern existing tri-state support,
undriven debug outputs, Verilog `byte` identifiers, and the unsupported LPF
`BLOCK JTAGPATHS` command. No hardware, real console, electrical contention,
metastability, or analog pulse-tolerance measurement was performed. The default
one-console configuration was built. Other reported issues are outside this fix.
Recovery deliberately drops traffic until a full idle boundary; it does not
attempt to salvage a malformed command's suffix.

Changed implementation: `n64_receive_command.v` only. Added regressions:
`tests/n10_receive_command_tb.v`, `tests/n10_controller_tb.v`, and
`tests/run_n10.py`. Added build/evidence helper: `tests/build_n10.py`.
Added documentation and preserved logs: this `validation/N10/` directory.
