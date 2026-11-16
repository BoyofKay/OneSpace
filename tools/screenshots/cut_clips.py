#!/usr/bin/env python3
"""Cut the emulator screen recordings into one clip per CLIP_START/CLIP_END marker.

Inputs (build/videos/): rec_<lang>_<n>.mp4 segments, segments_<lang>.txt (segment
number + device epoch ms at start), markers_<lang>.log (the flutter drive output).
Outputs: build/videos/<lang>_<clip>.mp4 (H.264, 30 fps, no audio) and .jpg poster.
"""
import re
import subprocess
import sys
from pathlib import Path

lang = sys.argv[1]
V = Path('build/videos')
segs = []
for line in (V / f'segments_{lang}.txt').read_text().split('\n'):
    if len(line.split()) == 2:
        n, t = line.split()
        f = V / f'rec_{lang}_{n}.mp4'
        if f.exists():
            segs.append((int(float(t) * 1000) if '.' in t else int(t), f))
log = (V / f'markers_{lang}.log').read_text(errors='ignore')
starts = {m.group(1): int(m.group(2)) for m in re.finditer(r'CLIP_START (\w+) (\d+)', log)}
ends = {m.group(1): int(m.group(2)) for m in re.finditer(r'CLIP_END (\w+) (\d+)', log)}


def duration(f):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(f)],
                         capture_output=True, text=True).stdout.strip()
    return float(out or 0)


for name, start in starts.items():
    end = ends.get(name)
    if not end:
        continue
    for t0, f in segs:
        dur = duration(f)
        if t0 <= start and end <= t0 + dur * 1000 + 500:
            ss = max(0, (start - t0) / 1000 + 0.3)  # screenrecord starts ~300 ms late
            length = (end - start) / 1000
            out = V / f'{lang}_{name}.mp4'
            subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-ss', f'{ss:.2f}', '-i', str(f), '-t', f'{length:.2f}',
                            '-an', '-vf', 'fps=30,scale=720:-2', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '24',
                            '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(out)], check=True)
            subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-ss', '0.5', '-i', str(out), '-frames:v', '1', '-q:v', '4',
                            str(V / f'{lang}_{name}.jpg')], check=True)
            print('clip', out, f'{length:.1f}s')
            break
    else:
        print('no segment covers', name)
