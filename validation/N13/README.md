<!-- N13 implementation rationale and provenance for the generated validation logs. -->
# N13: mechanical mode-button debounce

Source confirmed before editing: clean branch `N13-fix`, HEAD
`2f4bab11234cc2d5c1b452e51883447ff2831d10`. Read-only `git show` of
`analysis/findings.md` and `analysis/validation.md` at
`ca9081a9bc9c672ddea2412f39dd6c272337b4fd` supplied the report evidence.
No tracked AGENTS.md or applicable ancestor instructions were found.

The original six-sample filter and top-level latch accept millisecond bounce.
The original RTL, extracted with read-only `git show`, produces **two transitions**
for low/high/low intervals of 50,000 clocks each. The new regression also fails
against that original RTL at cycle 6 of the first low interval; see `baseline.log`.

`glitch_filter` now exposes a positive `STABLE_CYCLES` parameter and sizes its
counter accordingly. Its default remains six clocks for every protocol instance.
Only the button instance selects 500,000 consecutive samples: 10 ms at 50 MHz.
Both pressing and releasing must pass this interval. Returning to the currently
accepted level cancels partial qualification. The existing latch therefore toggles
once on an accepted low and rearms only after an accepted high. The mode change
occurs one clock after filter acceptance because both blocks use nonblocking
assignments. No protocol decoder, source snapshot, CDC or build dependency fix is
included. Comments accompany the RTL, Makefile and regression additions.

## Reproduction

Use Icarus Verilog, Yosys, nextpnr-ecp5 and ecppack on PATH. `make sim-n13`
executes the regressions; `make all` synthesizes, places/routes and packs the
default one-console design. Existing `make test` programs hardware and is not a
simulation target. `IVERILOG` and `VVP` may be overridden on the Make command line.

On this Windows host, GNU Make 4.4.1 and its MSYS shell were used. After obtaining
OSS CAD Suite 20261115 under `.tools/oss-cad-suite`, these commands ran in MSYS bash:

```sh
export PATH="$PWD/.tools/oss-cad-suite/bin:$PWD/.tools/oss-cad-suite/lib:/usr/bin:/c/Windows/System32"
make sim-n13 > validation/N13/simulation.log 2>&1
make all > validation/N13/build.log 2>&1
nextpnr-ecp5 --json n64_replay_device.json --textcfg .tools/n13_50mhz.config \
  --um5g-85k --package CABGA381 --lpf ecp5evn.lpf --freq 50 \
  > validation/N13/timing-50mhz.log 2>&1
```

Each command exited **0**. Final regression execution follows the last test edit;
the build and timing check use the final RTL. For the negative control, extract
`top.v` and `glitch_filter.v` from the source commit to `.tools/baseline/` using
`git show <source-commit>:<file>` (not a checkout), then run:

```sh
iverilog -g2012 -s n13_button_tb -o .tools/baseline/button.vvp \
  .tools/baseline/top.v .tools/baseline/glitch_filter.v tests/n13_button_tb.v
vvp .tools/baseline/button.vvp +bounce-trace
vvp .tools/baseline/button.vvp
```

Compilation and the diagnostic trace exit 0; the regression exits **1**, as
expected. `baseline.log` records those commands, outputs and exit codes.

## Results and limits

- `simulation.log`: real filter RTL passes intervals 1, 6, 7 and 500,000, including
  interrupted qualification and exact press/release boundaries. An unparameterized
  instance separately checks the six-clock protocol default. The actual top-level
  button wiring passes representative press/release bounce, a release one sample
  short of acceptance, long holds and two accepted presses. Per-cycle assertions
  check both mode value and cumulative transitions. PLL and unrelated peripherals
  are stubbed; protocol and electrical behavior are outside this regression.
- `build.log`: full repository build produces a 1,934,682-byte bitstream. Warnings
  include existing undriven debug outputs, Verilog lexer/ABC messages and unsupported
  LPF `BLOCK JTAGPATHS`. The default timing report uses 12 MHz; it is not evidence
  of a 50 MHz constraint.
- `timing-50mhz.log`: separate place/route with `--freq 50` passes; reported maximum
  frequency is 226.71 MHz. One unsupported-LPF warning, zero errors. This is tool
  timing analysis, not hardware verification.
- `git diff --cached --check -- . ':!validation/N13/*.log'` passed before commit;
  raw tool logs retain their emitted CRLF and trailing spaces, which an unrestricted
  whitespace check flags. Analysis reports and other issue logic
  were not changed. No board was connected or programmed, and switch bounce was
  not measured. Ten milliseconds is an engineering debounce choice; taps shorter
  than that are intentionally ignored, and bounce containing fully stable levels
  of 10 ms or longer can still be interpreted as separate presses. Validate the
  interval against the board switch before treating it as a measured guarantee.

Tool versions: Icarus Verilog 14.0 devel (s20260301-1055-ge6b789157-dirty),
Yosys 0.71+34 (e419c4eef), nextpnr 0.11.1-92-g5e2718b6, OSS CAD Suite 20261115.
The downloaded suite archive SHA-256 is
`7fb29ea7ac61e93393c8d795c915950fd0186f33f6590bf13b19bcd838dac9d1`.
Generated bitstream SHA-256 is
`4259cb6512236bdbd2b29cb0470f6752f7f97e080b118a83f9ad27c942db5ee7`.
Tools and generated build/simulation artifacts stay ignored; the committed logs
retain validation evidence without adding binaries to the repository.
