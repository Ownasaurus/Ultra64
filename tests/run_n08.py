"""N08: run waveform regression, pinned-source negative control and Make build.

Use Python 3 with iverilog, vvp, yosys, nextpnr-ecp5, ecppack and GNU make on
PATH. All generated FPGA/simulator files stay in a temporary directory; only
human-readable command/output/exit-status logs are kept in validation/n08.
"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LOGS = ROOT / 'validation' / 'n08'
BASE = '2f4bab11234cc2d5c1b452e51883447ff2831d10'
LOGS.mkdir(parents=True, exist_ok=True)


def run(label, args, cwd=ROOT):
    # Preserve full output and exit status, including failed negative controls.
    result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, env=dict(os.environ), errors='replace')
    (LOGS / (label + '.log')).write_text(
        '# N08 validation command and result\n$ ' + subprocess.list2cmdline([str(a) for a in args]) + '\n'
        + 'cwd: ' + str(cwd) + '\n' + result.stdout
        + '\nexit_code: ' + str(result.returncode) + '\n', encoding='utf-8')
    print(label, 'exit_code:', result.returncode, flush=True)
    return result


def main():
    # A portable toolchain can be used without modifying the host installation.
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-bin', type=Path)
    options = parser.parse_args()
    if options.tool_bin:
        os.environ['PATH'] = str(options.tool_bin.resolve()) + os.pathsep + ('C:/msys64/ucrt64/bin;C:/msys64/usr/bin;' if os.name == 'nt' else '') + os.environ['PATH']
    # Tool provenance makes the saved evidence reproducible on other hosts.
    for name, args in [('iverilog', ['-V']), ('yosys', ['-V']),
                       ('nextpnr-ecp5', ['--help']), ('ecppack', ['--version']),
                       ('make', ['--version'])]:
        run('tool-' + name, [shutil.which(name) or name] + args)
    sources = ['n64_transmit_controller_state.v', 'n64_transmit_byte.v',
               'n64_transmit_bit.v']
    with tempfile.TemporaryDirectory(prefix='n08-validation-') as temp:
        work = Path(temp)
        # Extract only the original transmitter blob; never modify the checkout
        # to run the negative control against the exact assigned source commit.
        original = subprocess.check_output(
            ['git', 'show', BASE + ':n64_transmit_controller_state.v'], cwd=ROOT)
        baseline = work / 'baseline.v'
        baseline.write_bytes(original)
        for label, controller, extra in [
            ('baseline', baseline, ['+baseline']),
            ('fixed', ROOT / sources[0], []),
        ]:
            image = work / (label + '.vvp')
            result = run(label + '-compile', ['iverilog', '-g2005', '-Wall',
                         '-s', 'n08_snapshot_tb', '-o', str(image),
                         str(ROOT / 'tests/n08_snapshot_tb.v'), str(controller)]
                         + [str(ROOT / s) for s in sources[1:]])
            if result.returncode:
                raise SystemExit('Compilation failed: ' + label)
            result = run(label + '-simulate', ['vvp', str(image)] + extra)
            if label == 'baseline':
                if result.returncode == 0 or 'actual=80000100' not in result.stdout:
                    raise SystemExit('Expected pinned-source mixed-state failure missing')
            elif result.returncode or 'PASS N08: 52 decoded responses' not in result.stdout:
                raise SystemExit('Fixed regression failed')
        # Exercise the repository build recipe in a fresh directory so no stale
        # generated outputs can bypass synthesis or placement (N12 is out of scope).
        build = work / 'build'
        build.mkdir()
        for pattern in ('*.v', '*.lpf', 'Makefile'):
            for path in ROOT.glob(pattern):
                shutil.copy2(path, build / path.name)
        manifest = '\n'.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name
                             for p in sorted(build.iterdir()))
        (LOGS / 'build-inputs.log').write_text(
            '# N08 build input SHA-256 hashes\n' + manifest + '\n', encoding='utf-8')
        # MSYS make needs POSIX paths to retain a temporary Windows toolchain.
        make_args = ['make', 'all']
        if os.name == 'nt':
            entries = []
            for entry in os.environ['PATH'].split(';'):
                entry = entry.replace('\\', '/')
                if len(entry) > 1 and entry[1] == ':':
                    entry = '/' + entry[0].lower() + entry[2:]
                entries.append(entry)
            make_args.append('PATH=' + ':'.join(entries))
        result = run('build', make_args, cwd=build)
        if result.returncode:
            raise SystemExit('Build failed; see validation/n08/build.log')
        # A shell launch can succeed without executing its recipe; require outputs.
        # Make removes _out.config as an intermediate after ecppack succeeds.
        for suffix in ('.json', '.bit', '.svf'):
            artifact = build / ('n64_replay_device' + suffix)
            if not artifact.is_file() or artifact.stat().st_size == 0:
                raise SystemExit('Missing build artifact: ' + str(artifact))
        # Keep hashes of the generated artifacts without committing binary outputs.
        (LOGS / 'build-artifacts.log').write_text(
            '# N08 generated build artifact SHA-256 hashes\n' + '\n'.join(
                hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name
                for p in sorted(build.iterdir()) if p.suffix in ('.json', '.config', '.bit', '.svf'))
            + '\n', encoding='utf-8')
    print('PASS N08 regression, negative control and full build', flush=True)


if __name__ == '__main__':
    main()
