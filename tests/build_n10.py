"""Run the repository's unmodified FPGA build in scratch space and retain evidence."""
import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--tool-bin', type=pathlib.Path, required=True)
parser.add_argument('--make', default='make')
parser.add_argument('--timing-mhz', type=float,
                    help='Also run place and route at this explicit clock target')
parser.add_argument('--log', type=pathlib.Path, default=ROOT / 'validation/N10/build.log')
args = parser.parse_args()

# Copy only build inputs so no generated bitstream or netlist enters the commit.
with tempfile.TemporaryDirectory(prefix='n10-build-') as tmp:
    inputs = list(ROOT.glob('*.v')) + [ROOT / 'Makefile', ROOT / 'ecp5evn.lpf']
    for source in inputs:
        shutil.copy2(source, tmp)
    env = dict(os.environ)
    env['PATH'] = str(args.tool_bin.resolve()) + os.pathsep + env.get('PATH', '')
    # Retain hashes to tie the build evidence to the reviewed inputs and output.
    manifest = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    command = [args.make, 'all']
    args.log.parent.mkdir(parents=True, exist_ok=True)
    with args.log.open('w', encoding='utf-8') as log:
        log.write(f'$ {subprocess.list2cmdline(command)}\ncwd={tmp}\n')
        log.write('Input SHA256:\n' + json.dumps(manifest, indent=2) + '\n')
        log.flush()
        result = subprocess.run(command, cwd=tmp, env=env, stdout=log,
                                stderr=subprocess.STDOUT, timeout=600)
        log.write(f'\nexit={result.returncode}\n')
        bitstream = pathlib.Path(tmp) / 'n64_replay_device.bit'
        if result.returncode == 0 and bitstream.exists():
            log.write(f'Bitstream SHA256: {hashlib.sha256(bitstream.read_bytes()).hexdigest()}\n')
        # The native recipe defaults to 12 MHz; optionally check the 50 MHz
        # clock assumed by the receiver without changing repository constraints.
        if result.returncode == 0 and args.timing_mhz:
            timing = [str(args.tool_bin / 'nextpnr-ecp5'), '--json', 'n64_replay_device.json',
                      '--textcfg', 'timing.config', '--um5g-85k', '--package', 'CABGA381',
                      '--lpf', 'ecp5evn.lpf', '--freq', str(args.timing_mhz)]
            log.write(f'\n$ {subprocess.list2cmdline(timing)}\n')
            log.flush()
            result = subprocess.run(timing, cwd=tmp, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=600)
            log.write(f'\nExplicit timing exit={result.returncode}\n')
        print(f'Build exit={result.returncode}; log={args.log}')
    raise SystemExit(result.returncode)
