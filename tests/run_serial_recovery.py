# N01: run parser RTL tests in a temporary directory and retain compiler/simulation logs.
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--source', default='serial_handler.v')
parser.add_argument('--baseline', action='store_true')
parser.add_argument('--default-timeout', action='store_true')
parser.add_argument('--log', default='validation/N01/regression.log')
args = parser.parse_args()
Path(args.log).parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='n01-rtl-') as scratch, open(args.log, 'w', encoding='utf-8', newline='\n') as log:
    output = str(Path(scratch) / 'serial_recovery.vvp')
    defines = (['-DPINNED_SOURCE'] if args.baseline else []) + (['-DDEFAULT_TIMEOUT'] if args.default_timeout else [])
    commands = [
        ['iverilog', '-g2005', '-Wall', *defines, '-s', 'serial_recovery_tb', '-o', output,
         args.source, 'UART_RX.v', 'UART_TX.v', 'tests/serial_recovery_tb.v'],
        ['vvp', output],
    ]
    for command in commands:
        print('$ ' + ' '.join(command), file=log, flush=True)
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        print(result.stdout, end='')
        log.write(result.stdout)
        print('exit:', result.returncode, file=log, flush=True)
        if result.returncode:
            raise SystemExit(result.returncode)
