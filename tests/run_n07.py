"""N07: run RTL regressions with installed ECP5 models and retain command/output evidence."""
import argparse
import hashlib
import re
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--models', type=Path, required=True,
                    help='Lattice Diamond cae_library/simulation/verilog/ecp5u directory')
parser.add_argument('--iverilog', default='iverilog')
parser.add_argument('--vvp', default='vvp')
parser.add_argument('--baseline', action='store_true', help='also prove the pinned source fails')
parser.add_argument('--integration-only', action='store_true',
                    help='rerun only UART status and complete top-level elaboration')
args = parser.parse_args()
build = ROOT / 'tests/.build'
build.mkdir(exist_ok=True)
logs = ROOT / 'validation/N07'
logs.mkdir(parents=True, exist_ok=True)
# Diamond spells LUT4's parameter `init`; this generated netlist uses Yosys's `INIT`.
# Rename only that identifier in a temporary model copy; preserve the vendor truth table.
lut4 = build / 'LUT4.v'
lut4.write_text(re.sub(r'\binit\b', 'INIT', (args.models / 'LUT4.v').read_text()))
sources = ['n64_controller.v', 'queue_1024.v', 'and2.v', 'inv.v', 'vhi.v', 'vlo.v',
           'xor2.v', 'glitch_filter.v', 'n64_receive_command.v', 'n64_transmit_identity.v',
           'n64_transmit_controller_state.v', 'n64_transmit_byte.v', 'n64_transmit_bit.v']

# Record commands, exit status and unabridged simulator diagnostics for reproducibility.
def run(cmd, log):
    result = subprocess.run([str(x) for x in cmd], cwd=ROOT, capture_output=True, text=True)
    log.write('$ ' + subprocess.list2cmdline([str(x) for x in cmd]) + '\n')
    log.write(result.stdout + result.stderr + f'\nEXIT {result.returncode}\n')
    log.flush()
    print(result.stdout + result.stderr, end='')
    return result.returncode

# A focused rerun keeps the full controller/baseline evidence intact.
log_name = 'integration.log' if args.integration_only else 'simulation.log'
with (logs / log_name).open('w', encoding='utf-8') as log:
    run([args.iverilog, '-V'], log)
    # Hash external vendor inputs without copying licensed models into the repository.
    for path in sorted(args.models.glob('*.v')):
        log.write(f'MODEL SHA256 {hashlib.sha256(path.read_bytes()).hexdigest()} {path.name}\n')
    for path in sorted(ROOT.glob('*.v')) + sorted((ROOT / 'tests').glob('*.*')):
        if path.is_file():
            log.write(f'SOURCE SHA256 {hashlib.sha256(path.read_bytes()).hexdigest()} '
                      f'{path.relative_to(ROOT)}\n')
    cases = [] if args.integration_only else ([True, False] if args.baseline else [False])
    for baseline in cases:
        selected = [ROOT / x for x in sources]
        tb = ROOT / 'tests/n07_controller_tb.v'
        label = 'fixed'
        if baseline:
            # Read only the exact assigned Git object; the checkout remains untouched.
            label = 'baseline'
            original = subprocess.check_output(['git', 'show',
                '2f4bab11234cc2d5c1b452e51883447ff2831d10:n64_controller.v'], cwd=ROOT)
            selected[0] = build / 'baseline_controller.v'
            selected[0].write_bytes(original)
            tb = build / 'baseline_tb.v'
            # Reach the actual transmit trigger rather than stopping at old RAM-wait bus drive.
            tb.write_text((ROOT / 'tests/n07_controller_tb.v').read_text().replace(
                ', .tas_underrun(fault_a)', '').replace(', .tas_underrun(fault_b)', '').replace(
                " || a.direction_output !== 1'b0", ''))
        image = build / (label + '.vvp')
        log.write(f'\nCASE {label}\n')
        if run([args.iverilog, '-g2005', '-s', 'n07_controller_tb', '-y', args.models,
                '-o', image, tb, lut4, *selected], log):
            sys.exit('compile failed')
        code = run([args.vvp, image], log)
        if baseline:
            if code != 1:
                sys.exit(f'baseline must fail an assertion, got {code}')
            log.write('EXPECTED baseline failure: empty startup must not trigger a response.\n')
        elif code:
            sys.exit('fixed RTL regression failed')
    # Compile the top-level wiring as well as testing the new UART query end to end.
    image = build / 'status.vvp'
    if run([args.iverilog, '-g2005', '-s', 'n07_status_tb', '-y', args.models,
            '-o', image, ROOT / 'tests/n07_status_tb.v', lut4,
            *[ROOT / x for x in ['serial_handler.v', 'queue_64.v', 'UART_RX.v',
                                 'UART_TX.v', 'and2.v', 'inv.v', 'vhi.v', 'vlo.v', 'xor2.v']]], log):
        sys.exit('status compile failed')
    if run([args.vvp, image], log):
        sys.exit('status regression failed')
    if run([args.iverilog, '-g2005', '-s', 'n07_top_tb', '-y', args.models,
            '-o', build / 'top.vvp', ROOT / 'tests/n07_top_tb.v',
            lut4, *sorted(ROOT.glob('*.v'))], log):
        sys.exit('top compile failed')
    log.write('PASS N07 ' + ('integration' if args.integration_only else 'controller/status')
              + ' regressions and top elaboration\n')
