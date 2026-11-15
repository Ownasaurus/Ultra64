<!-- N05 change and validation record; generated command logs are evidence, not source instructions. -->
# N05 input synchronization

Verified against source `2f4bab11234cc2d5c1b452e51883447ff2831d10`, initially clean on `N05-fix`.
Read the report with read-only `git show` at analysis commit
`ca9081a9bc9c672ddea2412f39dd6c272337b4fd`. Its actual repository path is
`analysis/findings.md`. The source has direct UART pin reads in start detection,
start validation and data sampling, and a direct pin/filter-output comparison
in `glitch_filter`. The existing N64 and button instances all use that filter.
The finding is therefore verified structurally; its physical failure rate is unknown.

## Change and timing budget

`UART_RX.v` and `glitch_filter.v` each now contain an idle-high, free-running
two-flop input pipeline. Only the first flop samples the external level; its
output feeds only the second flop. UART decisions and filter counters use only
the second stage. The existing module boundaries cover UART, every generated
console input, the physical controller and the mode button without double
synchronization. Reset does not interrupt the sampling pipeline.

Yosys's supported `keep` attribute preserves both registers; `async_reg` records
intent on the nets. We do **not** assume that nextpnr interprets `async_reg` as
a placement directive. The build explicitly requests 50 MHz with `--freq 50`,
so interstage paths remain timed synchronous paths. No false-path exception is
introduced between the flops. The LPF is unchanged.

At 50 MHz, downstream logic observes each input two clocks (40 ns) later than
before. The filter still requires six consecutive differing samples. A stable
external transition reaches its output on the eighth sampling edge, about
140–160 ns after the edge, versus 100–120 ns previously. Both polarities receive
the same nominal delay. Nominal 1 us/3 us N64 pulses therefore retain their
widths; asynchronous phase quantization is at most one clock in the functional
model. Tests exercise 980–1020 ns and 2980–3020 ns pulses, well within the
unchanged 25/75/125/175-clock decoding boundaries. Turnaround responses gain
40 ns of input latency; board-level acceptance of that delay remains unmeasured.

UART start, midpoint validation and data samples all use the same delayed stream;
the two-cycle delay moves the receive timeline without accumulating a per-bit
offset. At 434 clocks/bit, the added delay is 0.46% of one bit. Regression frames
use 8500/8680/8860 ns per bit (about +/-2% versus the configured 8680 ns),
including adjacent frames. Button filtering gains the same two-clock delay;
mechanical debounce behavior is deliberately unchanged (N13 is outside scope).
UART stop framing and all other reported issues are also unchanged.

## Reproduction and results

Tools were downloaded to the host temporary directory from the public
OSS CAD Suite Windows x64 release `2026-11-15`; no tools are vendored here.
GNU Make is `C:/msys64/usr/bin/make.exe`. The runner uses temporary source copies
for builds and read-only `git show` for the baseline; it never flashes hardware.
With normal Git ownership configuration and tools available:

```powershell
python tests/run_n05.py --toolchain "$env:TEMP\N05-tools\oss-cad-suite"
```

On this host Git 2.37 ignores the supplied command-line safe-directory exception.
A temporary `GIT_CONFIG_GLOBAL` file containing only this worktree's
`safe.directory` was used; the user's global configuration was not edited.
The runner exports discovered tool directories inside MSYS because its startup
environment otherwise resets PATH. Early environment-only build attempts failed
before synthesis; the preserved logs describe the successful final run.

- `rtl-compile.log`, `rtl-simulation.log`: PASS, 72 UART frames at four phases,
  startup/short-start suppression, two-stage latency, filter latency and
  five-sample glitch rejection of both polarities; four complete N64 commands
  and four 32-bit responses through the filter with edge jitter.
- `baseline-compile.log`, `baseline-detects-N05.log`: original source compiles,
  then fails with `UART bypasses two-stage boundary` at 111 ns. Exit 1 is expected.
- `build.log`: actual `make all` PASS through Yosys synthesis, nextpnr placement
  and routing, and ecppack bitstream/SVF generation for the default one console.
- `implementation.log`: second route requests machine-readable placed netlist
  and timing data for the CDC check. PASS at 50 MHz; achieved 218.67 MHz.
- `netlist-cdc.log`: PASS. All four raw inputs have exactly one input sink,
  the corresponding first-stage FF. Each first-stage output feeds only the
  second-stage DI, both flops share a clock and have idle-high initialization.
  Exact placed sites and clock timing are preserved in this log.
- `results.json`: every command's actual and expected exit status.

Evidence text normalizes line endings and removes trailing whitespace for Git;
command output content and exit statuses are otherwise preserved.

Icarus reports inherited-timescale warnings. Synthesis reports existing limited
tri-state support and undriven `debug` outputs; nextpnr ignores the existing
unsupported `BLOCK JTAGPATHS` LPF command. These warnings are preserved and
unrelated to the new input boundary.

## Limits and changed files

The physical implementation was inspected for the default one-console design.
Placement is not forced adjacent: the UART pair, for example, is at
`X9/Y67/SLICEC.FF0` and `X12/Y56/SLICEC.FF0`; both remain connected by a timed
register-to-register path. This proves preserved structure and ordinary timing
closure, not a characterized metastability MTBF. Device-specific metastability
constants, PVT assessment, hardware edge/baud testing, a dedicated CDC tool and
all-console-count placement sweeps were unavailable/unexecuted. Functional RTL
simulation cannot model analog metastability or prove physical reliability.
No board was programmed. Generated bitstreams/netlists remain in the temporary
build directory recorded in `results.json`; textual evidence is committed here.

Changed files: `UART_RX.v`, `glitch_filter.v`, `Makefile`,
`tests/n05_inputs_tb.v`, `tests/run_n05.py`, `tests/check_n05_netlist.py`,
and this `validation/N05/` record and command logs. Comments explain each RTL,
build and test addition. Analysis reports and other RTL are unchanged.
