"""N04 RTL regressions; requires Icarus Verilog (iverilog and vvp) on PATH."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run(command):
    # N04: Print reproducible commands and propagate compile/simulation failures.
    print("+ " + " ".join(map(str, command)), flush=True)
    subprocess.run(list(map(str, command)), cwd=ROOT, check=True)


def main():
    # N04: Keep generated simulation binaries outside the source worktree.
    with tempfile.TemporaryDirectory(prefix="ultra64-n04-") as tmp:
        for top, sources, divisors in [
            ("uart_break_tb", ["UART_RX.v", "tests/uart_break_tb.v"], [None]),
            ("uart_framing_tb", ["UART_RX.v", "tests/uart_framing_tb.v"], [8, 9, 434]),
            ("serial_framing_tb", ["UART_RX.v", "UART_TX.v", "serial_handler.v",
                                   "tests/queue_64_model.v", "tests/serial_framing_tb.v"], [None]),
        ]:
            for divisor in divisors:
                output = pathlib.Path(tmp) / f"{top}-{divisor}.vvp"
                command = ["iverilog", "-g2005", "-Wall", "-s", top, "-o", output]
                if divisor is not None:
                    command += [f"-P{top}.CPB={divisor}"]
                run(command + sources)
                run(["vvp", output])
    print("PASS: all N04 RTL regressions", flush=True)


if __name__ == "__main__":
    main()
