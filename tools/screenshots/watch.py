#!/usr/bin/env python3
"""Reads `flutter drive` output; on each "SNAP <name>" line captures the emulator
screen with adb into build/screenshots/<name>.png. Also tees the output to a log."""
import subprocess
import sys
from pathlib import Path

log = open(sys.argv[1], 'w')
out = Path('build/screenshots'); out.mkdir(parents=True, exist_ok=True)
for raw in sys.stdin:
    sys.stdout.write(raw); sys.stdout.flush(); log.write(raw); log.flush()
    if 'SNAP ' in raw:
        name = raw.split('SNAP ', 1)[1].strip().split()[0]
        png = subprocess.run(['adb', '-s', 'emulator-5554', 'exec-out', 'screencap', '-p'], capture_output=True).stdout
        if png[:4] == b'\x89PNG':
            (out / f'{name}.png').write_bytes(png)
            print(f'saved {name}.png', flush=True)
