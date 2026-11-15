<!-- N02: retain the source assessment, validation procedure and practical limits. -->
# N02 validation

Source: `2f4bab11234cc2d5c1b452e51883447ff2831d10`; assigned branch: `N02-fix`.
The initial checkout was clean and HEAD matched that source. No applicable
AGENTS.md was found in this worktree or its ancestor directories. The finding and
related overview/validation reports were read using read-only `git show` at
`ca9081a9bc9c672ddea2412f39dd6c272337b4fd`. They were not modified.

The source confirms that each request bit is `!queue_full`, all request bits must
be one to accept a shared write, but the original startup latch requires all bits
to be zero. At occupancies 1024/1023, neither predicate is true. After a poll frees
the full queue, automatic requests remain disabled. `baseline.log` reproduces
this failure using the unchanged serial handler and real generated FIFO RTL.

The fix latches startup completion when any queue fills, matching the existing
shared-write capacity boundary. It preserves atomic shared writes, the all-space
request gate, and the one-outstanding-request lock. Independent polling can now
release that gate without simultaneous fullness. This requires no protocol or
controller-interface changes. It does not promise equal playback positions or
protect a fast consumer from indefinitely slower peers.

Regression command (from repository root):

```text
python tests/run_n02.py --tool-root C:/Users/Justin/AppData/Local/Temp/n01-tools/oss-cad-suite --logs validation/N02
```

The test fills 1023 frames, polls only the last console, fills the first queue,
rejects another frame atomically, pauses the host, polls, checks a single request,
polls the faster peer repeatedly, resumes host writes, checks continued requests,
and checks reset rearms startup. N=1 is the simultaneous-full control; N=2 and
N=64 exercise unequal queues. The actual serial handler, generated frame/send
FIFOs, UART TX and Yosys ECP5 primitive models run. RX bytes are injected at the
decoded interface and polls drive FIFO reads directly. Producer FIFO writes are
counted; this test does not decode UART output or exercise N64 wire commands.

`fixed-*-compile.log` and `fixed-*-run.log` retain commands and exit statuses.
The baseline was compiled with the same sources/models and N=2, before changing
serial_handler.v; the later test correction only skips the faster-peer polls
for N=1. `baseline-compile.log` records an initial duplicate-model compilation
error; removing duplicate VHI/VLO/flip-flop models corrected that harness setup.
An initial runner failure to resolve Windows executables was corrected by
resolving each tool's full path. An initial N=1 assertion assumed a second slow
peer; it was corrected before the final runs. None required product changes.

Build command executed through MSYS2 Bash with the suite bin/lib on PATH:

```sh
export PATH=/c/Users/Justin/AppData/Local/Temp/n01-tools/oss-cad-suite/bin:/c/Users/Justin/AppData/Local/Temp/n01-tools/oss-cad-suite/lib:/usr/bin:$PATH
make -B all
```

`build-final.log`: exit 0; synthesis, place/route and ecppack all completed for
the repository default NUM_CONSOLES=1. `artifact-hashes.log` preserves SHA256
of resulting JSON, bitstream and SVF; generated binaries are not committed.
Tool versions are retained in `tool-versions.log`.

Earlier build logs are retained for transparency: `build.log` failed to find
yosys from the shell; `build-msys.log` reached packing but returned 127;
`build-cmd.log` was an incremental no-op; `build-forced.log` used an incompatible
cmd.exe invocation and did not execute the recipes. Only `build-final.log`
establishes a successful complete build.

Existing warnings include undriven debug outputs, Verilog keyword lexer warnings
and unsupported LPF BLOCK JTAGPATHS. Nextpnr reports about 209.51 MHz maximum for
the internal clock but tests against 12 MHz; this build is not proof of 50 MHz
timing closure. No board, physical consoles or external host were available.
No full 64-console physical implementation, CDC or electrical validation is
claimed. Host handling of B0 remains external. Reset coverage uses a completed
frame transaction; pending-request reset behavior is outside N02. Other reported
issues were left unchanged. Final diff whitespace check is recorded separately.

Log line endings and trailing spaces were normalized for Git whitespace checks; diagnostic content is retained.
