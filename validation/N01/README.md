<!-- N01: solution and validation provenance for this task; analysis reports are unchanged. -->
# N01 fix and validation

Source: `2f4bab11234cc2d5c1b452e51883447ff2831d10`, clean `N01-fix`
worktree before edits. Report reviewed read-only with `git show
ca9081a9bc9c672ddea2412f39dd6c272337b4fd:analysis/findings.md` and its
`analysis/README.md`. No applicable AGENTS.md was found in the worktree or
its ancestor directories. No other issue is implemented.

The pinned RTL confirms the report: SETUP_2/SETUP_3 have empty invalid-field
branches, partial frame state has no deadline, and reset is decoded only in
IDLE. `baseline.log` additionally reproduces both traces using the original
source blob extracted with read-only `git show`: invalid setup remains in
SETUP_2; an interrupted frame commits `1252AA00`. The same recovery regression
against the pinned RTL with `--default-timeout` fails with **parser did not
recover** (expected negative control, `negative-control.log`).

The fix rejects unsupported mode/controller fields with the existing `FE`
setup error convention. A configurable watchdog defaults to 500,000 cycles
(10 ms at 50 MHz) between received bytes while outside IDLE, including stalled
response states. Expiry discards the partial frame, clears parser response/reset
strobes, releases an abandoned frame-request lock, and returns to IDLE without
writing a frame. Frame bytes stage separately and publish atomically only on a
complete accepted frame. A byte exactly on the expiry edge is discarded.

The README specifies the host contract: drain TX, hold the line idle high for
20 ms, discard stale replies, send reset and wait for `01 52`, then ping and
wait for `55`. This preserves unrestricted binary frame payloads. Hosts that
pause 10 ms or more within a command must restart it; the host implementation
is absent here. Timeout preserves already queued frames; explicit reset clears
them. Traffic before the quiet interval has no guaranteed resynchronization.

Validation performed with the portable Windows OSS CAD Suite release 2026-11-15:

- `python tests/run_serial_recovery.py --baseline --source <pinned-blob> --log
  validation/N01/baseline.log`: both reported source failures confirmed.
- `python tests/run_serial_recovery.py`: PASS, accelerated 20,000-cycle timeout.
- `python tests/run_serial_recovery.py --default-timeout --log
  validation/N01/default-timeout.log`: PASS, production 500,000-cycle default.
- Regressions cover all incomplete prefixes of setup/frame/power/bulk commands,
  reset/ping recovery and reply bytes, all 765 invalid constrained setup field
  values, valid setup and power/bulk transactions, every byte value in every
  frame payload position, near-deadline inter-byte delays, expiry-edge arrival,
  lost transmitter completion, and a reconnect/reset/ping plus binary frame
  through real UART_RX/UART_TX RTL. Incomplete transactions produce no writes.
- `make all` using MSYS Make with an explicit MSYS shell and Unix-style PATH:
  PASS, Yosys synthesis, nextpnr ECP5 placement/routing, and ecppack produced
  the default one-console bitstream. `build.log` retains full output, including
  unsuccessful Windows shell/PATH attempts that produced no artifacts.
- `toolchain-and-artifacts.log` records tool versions and SHA256 hashes/sizes
  of the source and generated JSON, bitstream and SVF. Generated build outputs
  were removed after recording these hashes. `git diff --check`: PASS.

Simulation substitutes only the TX FIFO with a behavioral queue and uses decoded
byte injection for exhaustive cases plus real serial-wire integration cases.
ECP5 FIFO primitives, physical FPGA/host/console behavior, noise, framing faults,
and other console counts were not dynamically tested. `make test` and `make
flash` program hardware and were not run. Existing synthesis warnings concern
tri-state support and undriven debug pins; nextpnr ignores `BLOCK JTAGPATHS`.
The placement report checks the existing 12 MHz constraint (reported achieved
frequency 215.61 MHz); it does not constitute a corrected 50 MHz timing
constraint or hardware timing validation. Simulation warns that existing RTL
modules have no timescale. These warnings and unrelated findings are unchanged.

Evidence text uses LF line endings with trailing tool-output whitespace removed.

Changed files: `serial_handler.v` (commented RTL fix), `README.md` (commented
recovery/test contract), `tests/serial_recovery_tb.v` (commented RTL regression),
`tests/run_serial_recovery.py` (commented portable runner), and this
`validation/N01/` evidence directory. No analysis reports were edited.
