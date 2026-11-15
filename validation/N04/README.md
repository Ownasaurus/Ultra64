<!-- N04: Record source verification, the scoped framing fix, and its validation. -->
# N04 solution and validation

Source: `2f4bab11234cc2d5c1b452e51883447ff2831d10`.
Analysis evidence read with `git show` at
`ca9081a9bc9c672ddea2412f39dd6c272337b4fd:analysis/findings.md`.
Task branch: `N04-fix`. The worktree was clean at the source commit before editing.
No applicable `AGENTS.md` was found in the worktree or accessible parent paths.

The finding is confirmed: the source's `RX_STOP_BIT` asserts `o_RX_DV`
unconditionally after waiting one bit period from the last data sample. This is
the stop-bit midpoint, despite the original comment describing its finish.
An RTL simulation of the pinned receiver accepts two zero bytes during a
10,000-clock break. See [baseline.log](baseline.log); its simulation exit 1 is
the expected regression failure, while compilation succeeds.

## Solution

`UART_RX.v` now checks that midpoint for a high level before asserting receive
valid. A low stop sample discards the byte and emits one clock of
`o_RX_Framing_Error`, mutually exclusive with receive valid. The receiver then
waits for `CLKS_PER_BIT` consecutive high samples. Any low sample restarts this
qualification. A sustained break produces one error and no bytes; a shorter
high glitch cannot rearm reception. Normal back-to-back valid reception retains
its timing. Reset clears the framing-error output.

`serial_handler.v` connects that error to a priority abort of its current
transaction: return to IDLE, clear partial frame data, and lower queue-write,
response-request and controller-reset controls. Frames already committed to a
console queue remain committed. After an error, the host must provide at least
one high bit period and restart a complete command. This abort applies only to
UART framing errors; general command timeout/recovery behavior is outside N04.
The new error is an internal module signal, with no new host protocol response.

## Checks

Run `make sim-test` (or `python tests/run_n04.py`) with Python, Icarus Verilog
and `vvp` on PATH. Existing source uses `byte` as a Verilog identifier, so the
tests compile as Verilog 2005 rather than SystemVerilog.

- [regression.log](regression.log): `make sim-test`, exit 0. All 256 possible
  bytes with good stops, all 256 with bad stops, extended breaks, short high
  glitches, exactly one full high bit of recovery, reset during recovery, and
  back-to-back valid reception at divisors 8, 9 and production 434.
- Parser integration: malformed byte at each of the five positions in a frame
  command; naturally reached setup, power and bulk waiting states; framing-error
  abort at every numeric parser state 0 through 18. The latter uses a testbench
  state deposit immediately before the parser consumes a real receiver error,
  covering even transient states and unused SETUP_7. Receiver events are never
  forced. No bad byte asserts receive-valid or writes controller data; 31 fresh
  complete transactions subsequently write exactly the expected `12345678`.
- [build.log](build.log): the Makefile's complete `make all` synthesis, ECP5
  placement/routing and `ecppack` bitstream generation, exit 0. MSYS GNU Make
  needed an explicit Unix-style PATH to the portable suite. This invocation
  uses the repository's recipes and constraints. [artifacts.log](artifacts.log)
  records generated file sizes and SHA256 hashes. Generated JSON/bitstream/SVF
  files are kept in the task temporary directory, rather than committed.
- [review.log](review.log): source/branch verification and `git diff --check`.
- [toolchain.log](toolchain.log): tool versions, download URL and archive hash.
  Portable OSS CAD Suite 2026-11-15 was extracted in a task-specific temporary
  directory; no tool installation or global Git configuration was changed.

Initial attempts are also preserved: `regression-initial.log` predates the added
natural protocol-prefix coverage. `build-initial.log` records a shell PATH
failure. `build-shell-attempt.log` records an ineffective cmd.exe shell override:
its exit 0 did **not** execute the tools and is not treated as build success.
Only `build.log` contains the actual completed toolchain run.
Log text is normalized to UTF-8 with trailing line whitespace removed.

## Limitations and warnings

The parser simulation substitutes a small synchronous behavioral model for the
outgoing vendor TX FIFO. It checks the actual production receiver, transmitter,
parser, and controller queue-write interface, not vendor FIFO timing or physical
controller queues. The FPGA build uses the real vendor FIFO netlists.

Icarus warns about the existing production modules lacking timescales; stimulus
uses explicit testbench timescales and RTL timing depends on clock edges.
The build logs include warnings about existing tri-state constructs, undriven
debug outputs, `byte` identifiers and the unsupported LPF `BLOCK JTAGPATHS`
command. The existing build reports timing against 12 MHz (228.10 MHz achieved);
this does not independently establish the intended 50 MHz board timing.
No board was programmed. Hardware behavior, metastability, electrical noise and
baud mismatch tolerance were not measured. No other reported issue was fixed.

## Changed files

- `UART_RX.v`: validate stop sample, error pulse, break recovery.
- `serial_handler.v`: abort partial commands on framing error.
- `Makefile`: add the independent `sim-test` target; retain `all` as default.
- `tests/uart_break_tb.v`: reproducer compatible with the original interface.
- `tests/uart_framing_tb.v`: exhaustive byte/framing and recovery regressions.
- `tests/serial_framing_tb.v`: parser integration and state coverage.
- `tests/queue_64_model.v`: simulation-only outgoing FIFO model.
- `tests/run_n04.py`: portable regression runner using temporary binaries.
- `validation/N04/README.md` and the adjacent `.log` files: solution, validation
  results, build failures/retries, tool provenance and artifact hashes.
