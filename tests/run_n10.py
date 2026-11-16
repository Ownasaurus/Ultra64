"""Run N10 RTL regressions with Icarus or ModelSim; retain tool output in a log."""
import argparse
import os
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--log', type=pathlib.Path, default=ROOT / 'validation/N10/rtl.log')
parser.add_argument('--receiver-source', type=pathlib.Path, default=ROOT / 'n64_receive_command.v')
parser.add_argument('--only', choices=['receiver', 'wrapper'])
parser.add_argument('--iverilog', type=pathlib.Path,
                    help='Directory containing iverilog and vvp when absent from PATH')
parser.add_argument('--modelsim', type=pathlib.Path,
                    default=pathlib.Path('C:/lscc/diamond/3.13/modeltech/win32loem'))
args = parser.parse_args()

# Keep simulator products outside the worktree and preserve only reviewable logs.
args.log.parent.mkdir(parents=True, exist_ok=True)
with args.log.open('w', encoding='utf-8') as log, tempfile.TemporaryDirectory(prefix='n10-rtl-') as tmp:
    def run(command):
        command = [str(x) for x in command]
        result = subprocess.run(command, cwd=tmp, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=120)
        record = f"$ {subprocess.list2cmdline(command)}\n{result.stdout}\nexit={result.returncode}\n"
        log.write(record)
        log.flush()
        print(record, end='')
        if result.returncode:
            raise SystemExit(result.returncode)
        return result.stdout

    # Select an available simulator without installing or altering system tools.
    # An explicit directory also supports unpacked, task-local toolchains.
    suffix = '.exe' if os.name == 'nt' else ''
    iverilog = args.iverilog / f'iverilog{suffix}' if args.iverilog else shutil.which('iverilog')
    model = args.modelsim
    if not iverilog and not (model / 'vsim.exe').exists():
        log.write('BLOCKED: neither Icarus nor ModelSim found.\n')
        raise SystemExit('No RTL simulator available')
    for kind in ['receiver', 'wrapper']:
        if args.only and args.only != kind:
            continue
        bench = 'n10_receive_command_tb' if kind == 'receiver' else 'n10_controller_tb'
        sources = [args.receiver_source.resolve(), ROOT / f'tests/{bench}.v']
        if kind == 'wrapper':
            sources += [ROOT / f'{name}.v' for name in [
                'n64_controller', 'glitch_filter', 'n64_transmit_identity',
                'n64_transmit_controller_state', 'n64_transmit_byte', 'n64_transmit_bit']]
        if iverilog:
            # The repository is Verilog-2005 (its identifier "byte" is legal there).
            executable = pathlib.Path(tmp) / kind
            run([iverilog, '-g2005', '-s', bench, '-o', executable, *sources])
            vvp = args.iverilog / f'vvp{suffix}' if args.iverilog else shutil.which('vvp')
            output = run([vvp, executable])
        else:
            library = pathlib.Path(tmp) / kind
            run([model / 'vlib.exe', library])
            run([model / 'vlog.exe', '-work', library, *sources])
            output = run([model / 'vsim.exe', '-c', '-lib', library, bench,
                          '-do', 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'])
        # A PASS marker is required even if a simulator exits zero after $fatal.
        if f'PASS N10 {kind}' not in output:
            log.write(f'FAIL: {kind} did not reach its PASS marker.\n')
            raise SystemExit(f'{kind} did not pass')
    log.write('PASS: requested N10 RTL regressions completed.\n')
