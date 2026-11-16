<!-- N08: implementation rationale, reproducible validation and scope limits. -->
# N08 validation

Confirmed against source `2f4bab11234cc2d5c1b452e51883447ff2831d10` on branch
`N08-fix`, using read-only Git object reads of the report at
`ca9081a9bc9c672ddea2412f39dd6c272337b4fd`. The initial worktree was clean.
No repository AGENTS.md was found; README.md specifies `make` for the build.
Report contents were assessed as evidence. No other finding is implemented.

## Finding and solution

The original transmitter selects each byte from live `data` separately. The
controller's input is the live `input_mode ? tas_input : real_controller_data`
mux. A physical update or mode change can therefore combine source words.
The RTL negative control reproduces the exact reported example: source
`80000000` changes to `00000100`, producing `80000100`.

`response_data` now captures all 32 bits on a rising clock edge with `trigger`
asserted while idle and not already transmitting. Every byte comes from that
snapshot. A subsequent source/mode change takes effect at the next accepted
transaction. Capture precedes the existing first-byte launch by one clock;
the serializer's handshake and wire timing are unchanged. Busy triggers do
not overwrite the snapshot. All RTL changes include explanatory comments.

## Validation results

Executed 2026-11-15:

- `python tests/run_n08.py --tool-bin <temporary-toolchain>/ucrt64/bin`: PASS.
- Pinned-source compilation: exit 0; simulation: expected exit 1 with
  `expected=80000000 actual=80000100` (baseline-*.log).
- Fixed compilation and simulation: exit 0, **52 decoded responses**
  (fixed-*.log). Decode uses actual low pulse widths, checks all 32 bits,
  the existing stop pulse, response completion and idle return.
- Stimuli cover physical publication and both mode-switch directions immediately
  after acceptance, during each of four bytes, and before selection of bytes
  2, 3 and 4. Each case verifies the next response uses the updated source.
  Continuous source/mode changes and a busy trigger also preserve the snapshot.
- Fresh `make all`: exit 0; Yosys ECP5 synthesis, nextpnr placement/routing and
  ecppack bitstream/SVF generation succeeded (build.log). Yosys CHECK reports
  zero problems. Nonempty JSON, BIT and SVF artifacts were verified and hashed.
  Make removes the placement config as an intermediate after packaging.
- `git diff --check`: PASS for the implementation before staging.

Builds and baseline extractions use fresh temporary directories; generated
binaries are not committed. Full command/output/exit-code logs, tool versions,
build input hashes and output artifact hashes are retained here. The temporary
MSYS2 packages and hashes are recorded in toolchain-packages.log. Initial
nextpnr runtime DLL problems were resolved using matching temporary compiler,
Python, Qt and ICU runtimes; no system installation was changed.

## Reproduction and limitations

On Linux, put Icarus Verilog, vvp, Yosys, nextpnr-ecp5, ecppack and GNU Make on
PATH, then run `python3 tests/run_n08.py`. On this Windows host, the runner uses
`--tool-bin` for the temporary UCRT64 tool directory and the existing MSYS2
installation at `C:/msys64`. Git must trust this worktree; this run used a
separate temporary GIT_CONFIG_GLOBAL containing only its safe.directory entry.

The build uses the unchanged default one-console configuration. nextpnr reports
199.88 MHz maximum frequency and PASS at the recipe's default 12 MHz check;
this is not a dedicated 50 MHz constraint or a board timing measurement.
Warnings retained in the logs include inherited simulation timescales, Yosys
tri-state support and undriven debug outputs, and ignored LPF `BLOCK JTAGPATHS`.
No hardware was available, and no flashing was attempted. `make test` programs
volatile FPGA memory and is not an automated regression target.

The regression instantiates the three production serializer modules and an
identical live source mux. It does not simulate the full controller/FIFO/reader
or mechanical switch. It establishes serialization coherence for the word
present at acceptance, not validity of the physical sample, FIFO underrun
policy, synchronization or debounce behavior (separate findings).

## Changed files

- `n64_transmit_controller_state.v`: transaction snapshot and byte sources.
- `tests/n08_snapshot_tb.v`: waveform regression and original-source control.
- `tests/run_n08.py`: repeatable regression/build driver and log preservation.
- `validation/n08/README.md`: this rationale, results and limitations.
- `validation/n08/*.log`: compilation, simulation, build and tool provenance,
  plus source/artifact/package hashes.
