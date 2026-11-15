# N03 response retention

Reviewed `analysis/findings.md` and supporting reports using read-only `git show`
at `ca9081a9bc9c672ddea2412f39dd6c272337b4fd`. The assigned branch was
`N03-fix`, clean at `2f4bab11234cc2d5c1b452e51883447ff2831d10` before editing.
No applicable AGENTS.md was found in the worktree or accessible ancestor paths.
Analysis reports were treated as evidence and were not modified.

## Confirmation and change

The original producer selects automatic `41` using the old response flag on T.
The parser raises its pong request on T; on T+1 producer cleanup ignores the
request while AFTER_SEND clears it. The pinned-source RTL reproduction in
[baseline.json](baseline.json) fails with exactly one accepted/transmitted byte
instead of two. The accepted-byte checker requires `41` first, then `55`, so the
single accepted and transmitted byte is the automatic request. This confirms
N03 against the assigned source before relying on a fix.

`serial_handler.v` now holds the response byte and pending flag until the idle
producer has FIFO capacity and reserves a write. That reservation clears the
pending flag and advances AFTER_SEND, RESET_1 or SETUP_5. The single producer
cannot issue another write before the registered write is accepted on the next
edge. Pending responses retain priority and wait through cleanup or fullness.
Acknowledgements also advance the parser when receive-valid coincides with them.
Reset's controller-reset pulse retains its original one-cycle duration; its
transmit timeout starts after reservation. Automatic-request policy and other
issues are outside this change.

## Validation on 2026-11-15

- [baseline.json](baseline.json): pinned source compiles successfully, then the
  race regression fails as expected (exit 1, writes=1, sent=1, expected=2).
- [regression.json](regression.json): compilation and all **31 simulations pass**.
  Eight response sites cover pong, unknown command, frame overrun, invalid setup
  run, and both reset/setup bytes. They exercise idle, existing cleanup and the
  automatic-request selection edge. Seven cases add eight cycles of FIFO
  backpressure; one adds receive-valid on the acknowledgement edge. Frame
  overrun cannot coincide with automatic selection: the same request vector
  cannot both be all ready and contain a full console. Its idle/cleanup cases
  are covered. Checks require exactly the expected FIFO writes and decoded UART
  bytes, correct ordering, no duplicates, no pending response and parser IDLE.
- [build.log](build.log): the repository's `make all` recipes complete with exit
  0, using real queue_64.v/queue_1024.v, Yosys synthesis, nextpnr-ecp5 placement
  and routing, and ecppack. Generated bitstream: 1,934,682 bytes. Final reported
  clock maximum is 208.25 MHz; Make's existing target is 12 MHz. This does not
  substitute for board timing or CDC validation.
- [review.log](review.log): final whitespace/scope check and file inventory.
  CRLF is treated as a line ending; raw build output is excluded from whitespace
  checking because tool-generated banners and histograms contain trailing spaces.

Tools: Python 3.12.3; Icarus Verilog 14.0 development build
`s20260301-1055-ge6b789157-dirty`; Yosys 0.71+34 `e419c4eef`; GNU Make 4.4.1;
nextpnr/ecppack from the existing OSS CAD Suite in
`C:/Users/Justin/AppData/Local/Temp/n01-tools/oss-cad-suite`.

## Reproduction

With Icarus's bin and runtime lib directories on PATH:

```powershell
python tests/run_n03.py --baseline # expected exit 1, assertion failure
python tests/run_n03.py            # expected exit 0, 31 passes
python tests/build_n03.py --tools C:/Users/Justin/AppData/Local/Temp/n01-tools/oss-cad-suite --make C:/msys64/usr/bin/make.exe
```

The build helper copies the unchanged Makefile, LPF and current RTL to the ignored
`generated/fpga` directory. It sanitizes duplicate Windows PATH entries and uses
MSYS bash for Make's quoted scripts. Source files and repository recipes remain
in place. Simulator output and complete build output are preserved above;
generated binaries are intentionally ignored.

## Limits and setup observations

The testbench injects receive-valid/bytes and seeds parser/producer boundaries;
it runs the actual response logic, dequeue logic and production UART transmitter
at 434 clocks per bit, then decodes the TX waveform. Second-byte boundary tests
inject TX-done; first-byte reset/setup cases also run both bytes through actual
transmission. The FIFO is a documented synchronous behavioral contract model
because the bundled Yosys ECP5 RAM simulation primitive is a black box. FIFO
fullness is injected for the backpressure cases. Vendor RAM timing, full UART RX
integration, physical hardware, real host behavior and sustained saturation are
not verified. `make test` programs hardware and was not run.

Existing build warnings include tri-state support, undriven debug outputs,
Verilog identifiers matching SystemVerilog keywords, a combinational ABC network,
and ignored LPF `BLOCK JTAGPATHS`. No unrelated source fixes were made.

Initial tool setup attempts encountered SystemVerilog's reserved `byte` name,
a missing DLL search path (vvp access violation), duplicate Windows PATH entries,
and Make shell quoting problems. These were corrected in the test/build harness
and environment before the final logged runs. None was counted as source-race
evidence. Git ownership checks required elevated tool execution for repository
reads and commits; no global Git configuration was changed.

## Changed files

- `serial_handler.v`: commented response handshake and parser waits.
- `tests/n03_response_tb.v`: commented RTL regression and FIFO contract model.
- `tests/run_n03.py`: commented regression runner and pinned-source extraction.
- `tests/build_n03.py`: commented Windows build/evidence helper.
- `validation/n03/.gitignore`: exclude generated artifacts with an explanatory comment.
- `validation/n03/README.md`, `baseline.json`, `regression.json`, `build.log`,
  `review.log`: solution notes and validation evidence.
