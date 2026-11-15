<!-- N07: preserve the assessed evidence, implemented contract and validation limits. -->
# N07 solution and validation

Assigned branch: `N07-fix`. Source checked before editing:
`2f4bab11234cc2d5c1b452e51883447ff2831d10`; initial tracked worktree was clean.
Analysis objects were read with `git show` at
`ca9081a9bc9c672ddea2412f39dd6c272337b4fd`. That commit contains
`analysis/findings.md`, `analysis/README.md` and `analysis/validation.md`;
the requested `report/analysis/findings.md` path does not exist there.
No analysis files were checked out or edited. No AGENTS.md was present in the
worktree or source tree. No other designated issues were implemented.

## Confirmation and solution

At the source commit, every poll raises RdEn, waits two states, copies Q and
triggers a response. The FIFO's rden_i is gated by !Empty and feeds both DP16KD
read enables. Therefore the wrapper's trigger can occur without an accepted read,
independently of the RAM's startup or retention value. The supplemental baseline
RTL reproduction in `baseline-trigger.log` confirms exactly
`accepted_reads=0 transmit_trigger=1` using the pinned controller source.

The controller now gates reads with nonempty/not-reset, captures acceptance at
the FIFO clock edge and requires that validity before publishing a TAS word.
An empty TAS poll leaves the bus released and latches a per-console fail-stop
fault. TAS polls remain silent until host reset; writes alone do not resume
playback. Reset cancels pending reads and clears cached/valid/fault state. A
response already started finishes with its accepted word and clears its cache
afterward. Identity and passthrough remain available. Existing passthrough
dequeue behavior is preserved when data is available.

The top level routes the fault vector to serial_handler. The new optional `U`
command snapshots aggregate status (`00` healthy, `B1` any fault). A dedicated
pending bit holds this reply across producer cleanup and full FIFO conditions.
It sends no unsolicited bytes and does not clear faults. Hosts must send one
query at a time, finish the reply, and distinguish existing automatic `A` requests.
On a fault, stop playback, reset, refill, and restart a known timeline. See the
root README for startup, simultaneous-empty-write and recovery behavior.

## Checks and evidence

Validation ran on Windows on 2026-11-15 with Python 3.12, Icarus Verilog 13.0,
Lattice Diamond 3.13 ECP5 simulation models, Yosys 0.38, nextpnr-ecp5 0.7,
Project Trellis 1.4 and GNU Make 4.4.1. Portable tool packages live only in the
ignored `.tools` directory. External model hashes and source hashes are recorded
in the simulation logs. Diamond's LUT4 `init` identifier is renamed to `INIT`
in a temporary model copy to match the existing generated netlist; its logic is
unchanged. Generated FIFOs, primitive RAM, filters, command receivers and
transmitters are otherwise real RTL, not behavioral FIFO substitutes.

| Check | Result | Evidence |
| --- | --- | --- |
| Pinned source baseline | Expected assertion failure, actual transmit trigger without read | `baseline-trigger.log` |
| Empty startup, starvation, refill without reset | Pass: silent, sticky fault, no read | `simulation.log` |
| Drain-to-empty, reset/refill recovery | Pass: one accepted frame per TAS trigger, no repeated frame | `simulation.log` |
| Empty poll concurrent with write | Pass: no write-through authorization | `simulation.log` |
| Reset at dequeue and RAM capture stages | Pass: pending response canceled, validity/cache cleared | `simulation.log` |
| Reset during accepted response | Pass: data stable until response completes, then cache cleared | `simulation.log` |
| Unequal console rates | Pass: both queues filled to 1024; A drains and faults while B stays full; B still responds correctly | `simulation.log` |
| Identity and passthrough after TAS fault | Pass | `simulation.log` |
| TAS selected during empty passthrough RAM wait | Pass: response authorization still requires an accepted frame | `simulation.log` |
| UART U query | Pass: decoded UART healthy/fault/repeated/cleared replies; either console contributes | `integration.log` |
| Query during producer cleanup/full FIFO | Pass: pending snapshot retained, eventual single reply | `integration.log` |
| Complete two-console top elaboration | Pass with vendor reset roots in simulation harness | `integration.log` |
| Required `make -B all` | Pass: synthesis, place/route, bitstream and SVF generation | `build.log` |
| Explicit 50 MHz place/route | Pass: reported post-route maximum 206.87 MHz | `timing-50mhz.log` |
| `git diff --check` | Pass | `review.log` |

The full controller test records 1027 accepted A reads and 1026 A responses: one
accepted read is deliberately canceled by reset before response. B records one
accepted read and one response. Every TAS response trigger is checked against a
single read credit and the expected word; arbitrary startup Q values are never
treated as valid. The test drives actual console command pulses; UART tests also
decode outgoing serial bytes.

Reproduction commands (from the worktree root, with the named tools available):

```text
python tests/run_n07.py --models C:/lscc/diamond/3.13/cae_library/simulation/verilog/ecp5u --iverilog .tools/mingw64/bin/iverilog.exe --vvp .tools/mingw64/bin/vvp.exe --baseline
python tests/run_n07.py --models C:/lscc/diamond/3.13/cae_library/simulation/verilog/ecp5u --iverilog .tools/mingw64/bin/iverilog.exe --vvp .tools/mingw64/bin/vvp.exe --integration-only
make -B all
```

The exact build shell/PATH setup, nextpnr command, diagnostics, exit codes and
generated artifact hashes are in the logs. Make removes its intermediate config
after successful packing. Generated binary outputs are ignored; logs and hashes
are committed as evidence.

## Corrected validation setup and limits

The first full simulation's controller and UART suites passed, then its bare
`top` elaboration failed because the vendor library requires global GSR/PUR
simulation roots. That original failure remains in `simulation-first-run.log`.
The final runner uses `n07_top_tb.v` to supply those roots. A focused rerun is
recorded in `integration.log`; the final complete run, including the additional
mode-change authorization check, is recorded in `simulation.log`. The final
build and explicit 50 MHz timing logs also cover that final RTL.

Tool setup also encountered a mismatched C++ runtime and a LUT4 parameter-name
mismatch before usable simulation results. These were corrected locally before
the retained runs. The first build reached synthesis but could not load nextpnr;
`build-setup-attempt.log` preserves that unsuccessful attempt. Matching portable
runtime dependencies allowed the successful full build in `build.log`. No
automatic approval rejection remains outstanding.

The unmodified build uses a default 12 MHz nextpnr timing target. The additional
explicit 50 MHz run checks the frequency assumed by controller RTL. Both pass.
Existing warnings include undriven debug outputs, Verilog identifier `byte`, and
nextpnr ignoring the LPF `BLOCK JTAGPATHS` command; these are outside N07.

No board was flashed or measured, no real host interoperability was tested, and
no 64-console fit was performed. This is functional primitive-model simulation
and one-console synthesis/route, with two-console simulation/elaboration; it
does not establish electrical timing, CDC behavior or exhaustive mode/reset
interleavings. TAS word validity is checked at the response trigger; the suite
does not independently decode every N64 response bit. The existing live-mode
response mux, initial prebuffer handshake and shared replenishment policy remain
unchanged. Hosts need to adopt `U` to diagnose the latched failure explicitly.

## Changed files

- `n64_controller.v`: dequeue validity, silent fail-stop, cache/reset handling.
- `serial_handler.v`: held, queryable aggregate underrun status.
- `top.v`: per-console fault wiring.
- `tests/n07_controller_tb.v`, `tests/n07_status_tb.v`, `tests/n07_top_tb.v`,
  `tests/run_n07.py`: primitive-backed regressions and reproducible log runner.
- `Makefile`: separate `check-n07` simulation target.
- `README.md`: host contract, recovery and test instructions.
- `.gitignore`: local tools and generated artifacts; `.gitattributes`: preserve
  raw validation-log spacing without applying source whitespace rules.
- `validation/N07/`: this assessment and retained validation evidence.
