#!/usr/bin/env python3
"""Bound a test command and capture macOS process stacks before terminating a hang."""

import argparse
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile


def descendants(root_pid):
    output = subprocess.check_output(["ps", "-axo", "pid=,ppid="], text=True)
    pairs = [tuple(map(int, line.split())) for line in output.splitlines()]
    found = {root_pid}
    while True:
        added = {pid for pid, parent in pairs if parent in found} - found
        if not added:
            return found
        found.update(added)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=90)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        parser.error("a test command is required")
    process = subprocess.Popen(command)
    try:
        return process.wait(timeout=args.timeout)
    except subprocess.TimeoutExpired:
        print(f"Test command exceeded {args.timeout:g} seconds; collecting process stacks.", flush=True)
        pids = descendants(process.pid)
        subprocess.run(["ps", "-p", ",".join(map(str, sorted(pids))), "-o", "pid,ppid,stat,etime,command"], check=False)
        sampler = shutil.which("sample")
        if sampler:
            with tempfile.TemporaryDirectory(prefix="spectro-test-stacks-") as directory:
                for pid in sorted(pids):
                    path = Path(directory) / f"{pid}.txt"
                    try:
                        subprocess.run([sampler, str(pid), "1", "-file", str(path)], timeout=10, check=False)
                        if path.exists():
                            print(path.read_text(errors="replace"), flush=True)
                    except (OSError, subprocess.TimeoutExpired) as error:
                        print(f"Could not sample {pid}: {error}", flush=True)
        for pid in sorted(pids - {process.pid}, reverse=True):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        if process.poll() is None:
            process.kill()
        process.wait(timeout=10)
        return 124


if __name__ == "__main__":
    sys.exit(main())
