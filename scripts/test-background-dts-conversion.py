#!/usr/bin/env python3
"""Scratch-only engine proof: MKV (h264 + DTS [+ SRT]) -> MP4 with AAC counted by AVFoundation.

Drives a SEPARATELY launched engine copy through its Apple Events with a distinct bundle id
(never the production local.sublerautomation.Subler). Source and output stay in the scratch dir.
  --engine-id  bundle id of the already running scratch engine copy
  --source     scratch MKV;  --language fr  --expect-title "La Tour Montparnasse infernale" (optional, online)
"""
import argparse, json, os, subprocess, sys, time
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--engine-id', required=True)
p.add_argument('--source', type=Path, required=True)
p.add_argument('--language', default='fr')
p.add_argument('--expect-title')
a = p.parse_args()
scratch = Path(os.environ['TMPDIR']).resolve()
assert a.engine_id != 'local.sublerautomation.Subler', 'refusing production engine'
assert str(a.source.resolve()).startswith(str(scratch)), 'source must live in scratch'
out = a.source.with_name(a.source.stem + '.out.mp4')
assert not out.exists()

def osa(body, timeout=300):
    r = subprocess.run(['osascript', '-e', f'tell application id "{a.engine_id}"\n{body}\nend tell'],
                       capture_output=True, text=True, timeout=timeout)
    if r.returncode: raise SystemExit(f'osascript failed: {r.stderr.strip()}')
    return r.stdout.strip()

token = osa(f'return import background file (POSIX file "{a.source}")')
print('token', token)
tk = f'owned token "{token}"'
if a.expect_title:
    lines = osa(f'set l to fetch metadata candidates {tk} limit 50 language "{a.language}"\n'
                'set t to ""\nrepeat with x in l\nset t to t & (x as text) & linefeed\nend repeat\nreturn t').splitlines()
    print('candidates:', lines[:5])
    idx = next((i + 1 for i, l in enumerate(lines) if a.expect_title.lower() in l.lower()), None)
    assert idx, f'no candidate titled {a.expect_title!r}'
    osa(f'fetch and set metadata candidate {idx} {tk} language "{a.language}"')
    time.sleep(2)
osa(f'send to queue (POSIX file "{out}") {tk}')
osa('start queue')
st = ''
for _ in range(600):
    st = osa(f'repeat with i from 1 to count of queue items\nif destinationPath of queue item i is "{out}" then return (status of queue item i) as text\nend repeat\nreturn ""')
    if st in ('completed', 'failed', 'cancelled'): break
    time.sleep(1)
print('queue status', st)
assert st == 'completed', st
fp = lambda *args: json.loads(subprocess.run(['ffprobe', '-v', 'error', '-print_format', 'json', *args, str(out)],
                                             capture_output=True, text=True, check=True).stdout)
streams = fp('-show_streams')['streams']
for s in streams: print(s['codec_type'], s['codec_name'], s.get('codec_tag_string'), s.get('tags', {}).get('language'))
assert any(s['codec_type'] == 'audio' and s['codec_name'] == 'aac' for s in streams), 'no aac audio'
assert not any(s['codec_name'] == 'dts' for s in streams), 'dts copied'
title = fp('-show_format')['format'].get('tags', {}).get('title')
print('title', title)
if a.expect_title: assert title and title.lower() == a.expect_title.lower(), title
print('PASS')
