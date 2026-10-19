#!/usr/bin/env python3
"""Synthetic-only installed Subler API regression; does not start/change its queue.

Requires explicit opt-in to create and close owned Subler documents. This is an
asserting diagnostic of the missing native save option, NOT a production fix.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import runpy
import subprocess
import sys
import time


SCRIPTS = Path(__file__).resolve().parent


def script(body, *args):
    result = subprocess.run(['osascript', '-e', body, *map(str, args)],
                            capture_output=True, text=True, timeout=60)
    if result.returncode:
        # Do not forward raw native errors, document names or queue paths.
        raise RuntimeError('Owned Subler Apple Event failed')
    return result.stdout.strip()


def queue_snapshot():
    value = script('''tell application id "org.galad.Subler"
        set snapshot to ""
        repeat with i from 1 to count of queue items
            set snapshot to snapshot & (id of queue item i) & tab & ((status of queue item i) as text) & tab & (destinationPath of queue item i) & linefeed
        end repeat
        return snapshot
    end tell''')
    return hashlib.sha256(value.encode()).hexdigest()


def create(source):
    return int(script('''on run argv
        tell application id "org.galad.Subler"
            set ownedDoc to make new document
            try
                import file (POSIX file (item 1 of argv)) into ownedDoc
                set windowIDs to id of every window
                repeat with candidateID in windowIDs
                    set wid to candidateID as integer
                    if wid > 0 then
                        try
                            if document of window id wid is ownedDoc then return wid
                        end try
                    end if
                end repeat
                error "No owned window"
            on error
                close document doc ownedDoc
                error "Owned import failed"
            end try
        end tell
    end run''', source))


def close(wid):
    # Window wrappers can remain after closing; existence alone is not readback.
    script(f'''tell application id "org.galad.Subler"
        close document doc (document of window id {wid})
    end tell''')
    for _ in range(50):
        result = script(f'''tell application id "org.galad.Subler"
            try
                get name of document of window id {wid}
                return "open"
            on error number n
                if n is -1728 then return "closed"
                error "Cannot verify owned closure"
            end try
        end tell''')
        if result == 'closed':
            return
        time.sleep(0.1)
    raise RuntimeError('Owned document closure was not verified')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scratch', type=Path, required=True)
    parser.add_argument('--authorize-owned-subler-documents', action='store_true', required=True)
    args = parser.parse_args()
    original_queue = queue_snapshot()
    repro = subprocess.run([sys.executable, str(SCRIPTS / 'hevc-packaging-repro.py'),
                            '--scratch', str(args.scratch)], capture_output=True,
                           text=True, timeout=120, check=True)
    root = Path(json.loads(repro.stdout)['evidence'])
    source = root / 'generated-hdr10.mkv'
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    wid = create(source)
    try:
        standard_error = int(script(f'''on run argv
            tell application id "org.galad.Subler"
                try
                    save (document of window id {wid}) in (POSIX file (item 1 of argv))
                    return 0
                on error number n
                    return n
                end try
            end tell
        end run''', root / 'standard.mp4'))
        assert standard_error == -1708, 'Standard save behavior changed: investigate native options'
        assert not (root / 'standard.mp4').exists()
        output = root / 'scripted.mp4'
        script(f'''on run argv
            tell application id "org.galad.Subler"
                save as (POSIX file (item 1 of argv)) doc (document of window id {wid})
            end tell
        end run''', output)
        # Native save is asynchronous; require stable output and completed reader.
        deadline = time.monotonic() + 30
        previous = None
        stable = 0
        while time.monotonic() < deadline:
            size = output.stat().st_size if output.exists() else 0
            stable = stable + 1 if size > 0 and size == previous else 0
            previous = size
            if stable >= 3:
                break
            time.sleep(0.2)
        else:
            raise RuntimeError('Owned native save did not finish')
        helpers = runpy.run_path(str(SCRIPTS / 'hevc-packaging-repro.py'))
        decode = helpers['run']([root / 'native-probe', 'inspect', output, 'all'])
        assert 'start error=' in decode and 'Code=-11833' in decode
        ui_decode = helpers['run']([root / 'native-probe', 'inspect', root / 'ui.mp4', 'all'])
        expected_images = len(helpers['packets']('/opt/homebrew/bin/ffprobe', root / 'ui.mp4', 'v:0')[0])
        assert expected_images > 0
        image_results = re.findall(r'decodedImages=(\d+) status=(\d+) error=(.*)', ui_decode)
        print(json.dumps({'evidence': str(root), 'expected_samples': expected_images,
                          'apple_image_counts_and_status': [list(item[:2]) for item in image_results]}), file=sys.stderr)
        assert len(image_results) == 1 and image_results[0][1:] == ('2', '(null)')
        decoded_images = int(image_results[0][0])
        assert decoded_images >= 3
        for selector in ('v:0', 'a:0'):
            assert helpers['packets']('/opt/homebrew/bin/ffprobe', output, selector) == helpers['packets']('/opt/homebrew/bin/ffprobe', root / 'queue.mp4', selector)
        assert hashlib.sha256(source.read_bytes()).hexdigest() == source_hash
    finally:
        close(wid)
        assert queue_snapshot() == original_queue, 'Foreign queue snapshot changed; inspect without mutating it'
    results = {
        'standard_save_error': standard_error,
        'native_force_hvc1_images': decoded_images,
        'native_force_hvc1_compressed_samples': expected_images,
        'production_gate_all_samples_decode': decoded_images == expected_images,
        'checks': ['standard save unsupported (-1708)', 'custom save reproduces Apple -11833',
                   'native force-hvc1 yields images and reader completes', 'custom/native default video bytes and timing equal',
                   'custom/native default audio bytes and timing equal', 'synthetic source unchanged',
                   'owned document closed (readback)', 'queue records unchanged (snapshot)'],
        'limits': ['No product fix', 'No accepted GUI save evidence', 'No personal media',
                   'HDR10 synthetic only; no DV or rich-container certification',
                   'Native force-hvc1 still retains in-band parameter sets'],
    }
    (root / 'scripted-save-results.json').write_text(json.dumps(results, indent=2))
    print(json.dumps({'evidence': str(root), **results}, indent=2))
    if not results['production_gate_all_samples_decode']:
        raise RuntimeError('Production image completeness gate failed; no product repair is certified')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        import traceback
        frames = traceback.extract_tb(error.__traceback__)
        print('Diagnostic failed: ' + type(error).__name__ + ' at ' +
              ', '.join(f'{Path(frame.filename).name}:{frame.lineno}' for frame in frames), file=sys.stderr)
        sys.exit(1)
