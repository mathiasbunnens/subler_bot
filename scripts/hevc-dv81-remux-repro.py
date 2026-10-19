#!/usr/bin/env python3
"""Authorized, two-second DV8.1 experiment; never modifies/replaces its input.

Requires --authorize-personal-excerpt and an explicit source. Creates an exclusive
0700 child of --scratch and deletes ALL media/native binaries on success/failure.
Only a sanitized JSON report remains. Never runs Subler or its shared queue.
This is NOT a production remuxer or a whole-film preservation certification.
"""
import argparse
from collections import Counter
from fractions import Fraction
import hashlib
from importlib.util import module_from_spec, spec_from_file_location
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
from typing import Any

FFMPEG = '/opt/homebrew/bin/ffmpeg'
FFPROBE = '/opt/homebrew/bin/ffprobe'


def run(args, check=True):
    try:
        result = subprocess.run([str(a) for a in args], capture_output=True, timeout=120)
    except subprocess.TimeoutExpired:
        raise RuntimeError('Offline tool timeout; private command/output suppressed') from None
    if check and result.returncode:
        # Native/tool errors may contain the user's path, titles or metadata.
        raise RuntimeError('Offline tool failed (exit %d); private output suppressed' % result.returncode)
    return result


def packet_info(path, selector, video=False, bounded=False) -> dict[str, Any]:
    args = [FFPROBE, '-v', 'error']
    if bounded:
        args += ['-read_intervals', '0%+2']
    args += ['-select_streams', selector, '-show_packets', '-show_streams',
             '-show_entries', 'packet=pos,size,pts,dts,duration:stream=time_base', '-of', 'json', path]
    info = json.loads(run(args).stdout)
    base = Fraction(info['streams'][0]['time_base'])
    packets, counts = [], Counter()
    with path.open('rb') as stream:
        for packet in info['packets']:
            stream.seek(int(packet['pos']))
            data = stream.read(int(packet['size']))
            assert len(data) == int(packet['size'])
            timing = {key: str(int(packet[key]) * base) if key in packet else None
                      for key in ('pts', 'dts', 'duration')}
            if not video:
                packets.append(dict(timing, sha256=hashlib.sha256(data).hexdigest()))
                continue
            offset, nals = 0, []
            while offset < len(data):
                assert len(data) - offset >= 4
                size = int.from_bytes(data[offset:offset+4], 'big'); offset += 4
                assert 2 <= size <= len(data) - offset
                nal = data[offset:offset+size]; offset += size
                typ = (nal[0] >> 1) & 63
                counts[typ] += 1
                nals.append([typ, hashlib.sha256(nal).hexdigest()])
            packets.append(dict(timing, nals=nals))
    assert packets, 'No packets in experiment'
    return dict(packets=packets, nal_counts=dict(counts))


def retained(video):
    return [dict(p, nals=[nal for nal in p['nals'] if nal[0] not in (32, 33, 34)])
            for p in video['packets']]


def metadata_atoms(path):
    """Read only bounded moov/udta/tref metadata, not media or user tag values."""
    result = []
    with path.open('rb') as stream:
        end = stream.seek(0, 2)
        def walk(start, stop, trail='', depth=0):
            assert depth < 12
            pos, index = start, 0
            while pos + 8 <= stop:
                stream.seek(pos)
                size, typ = struct.unpack('>I4s', stream.read(8)); header = 8
                if size == 1:
                    size = struct.unpack('>Q', stream.read(8))[0]; header = 16
                if size == 0:
                    size = stop - pos
                assert header <= size <= stop - pos
                here = trail + '/' + typ.decode('latin1') + ':' + str(index)
                body = pos + header
                if typ in (b'moov', b'trak', b'udta', b'tref', b'ilst'):
                    walk(body, pos + size, here, depth+1)
                elif typ == b'meta':
                    walk(body+4, pos+size, here, depth+1)
                elif '/tref:' in here or '/ilst:' in here:
                    assert size <= 16 * 1024 * 1024
                    stream.seek(body); data = stream.read(size-header)
                    result.append(dict(path=here, sha256=hashlib.sha256(data).hexdigest(), length=len(data)))
                pos += size; index += 1
        walk(0, end)
    return result


def streams(path):
    # Explicit selection excludes user-readable tags, filenames and chapter titles.
    return json.loads(run([FFPROBE, '-v', 'error', '-show_entries',
        'stream=index,codec_type,codec_name,codec_tag_string:stream_disposition',
        '-of', 'json', path]).stdout)['streams']


def apple(native, path, mode=None) -> dict[str, Any]:
    args = [native, 'inspect', path]
    if mode:
        args.append(mode)
    result = run(args)
    text = (result.stdout + result.stderr).decode(errors='replace')
    return dict(images=[int(x) for x in re.findall(r'decodedImages=(\d+)', text)],
                statuses=[int(x) for x in re.findall(r'decodedImages=\d+ status=(\d+)', text)],
                start_failed='start error=' in text,
                errors=re.findall(r'Domain=([\w.]+) Code=(-?\d+)', text))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--scratch', type=Path, required=True)
    parser.add_argument('--authorize-personal-excerpt', action='store_true', required=True)
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    before = source.stat()
    root = Path(tempfile.mkdtemp(prefix='dv81-private-', dir=args.scratch))
    root.chmod(0o700)
    scripts = Path(__file__).resolve().parent
    spec = spec_from_file_location('container_metadata', scripts/'hevc-container-metadata.py')
    assert spec is not None and spec.loader is not None
    metadata = module_from_spec(spec); spec.loader.exec_module(metadata)
    report: dict[str, Any] = dict(scope='Authorized first two seconds; not whole-film/TV certification', checks=[])
    def check(condition, description):
        assert condition, description
        report['checks'].append(description)
    try:
        framework = Path('/Applications/Subler.app/Contents/Frameworks')
        native = root/'native-probe'
        run(['clang', '-fobjc-arc', '-Wno-deprecated-declarations', '-F', framework,
             '-framework', 'MP42Foundation', '-framework', 'Foundation', '-framework', 'AVFoundation',
             '-framework', 'CoreMedia', '-framework', 'CoreVideo', '-Wl,-rpath,'+str(framework),
             scripts/'hevc-native-probe.m', '-o', native])
        run(['install_name_tool', '-change',
             '@loader_path/../Frameworks/MP42Foundation.framework/Versions/A/MP42Foundation',
             framework/'MP42Foundation.framework/Versions/A/MP42Foundation', native])
        run(['codesign', '--force', '--sign', '-', native])
        original_meta = metadata.inspect(source)
        dv = next(x for x in original_meta if x.get('atom') in ('dvvC', 'dvcC'))
        record = bytes.fromhex(dv['hex'])
        check(record[2] >> 1 == 8 and record[4] >> 4 == 1 and record[3] & 7 == 5,
              'Input is single-layer DV8.1 with RPU and base layer, no enhancement layer')
        report['original_apple'] = apple(native, source)
        check(report['original_apple']['start_failed'], 'Original hev1 Apple decoder startup rejection reproduced')
        report['original_atoms'] = metadata_atoms(source)
        bounded = packet_info(source, 'v:0', video=True, bounded=True)
        # Video/audio-only excerpt intentionally does not claim artwork/subtitle/chapter preservation.
        excerpt = root/'excerpt.mp4'
        run([FFMPEG, '-v', 'error', '-nostdin', '-n', '-i', source, '-t', '2',
             '-map', '0:v:0', '-map', '0:a?', '-c', 'copy', '-strict', 'unofficial',
             '-map_metadata', '0', '-map_chapters', '-1', excerpt])
        baseline = packet_info(excerpt, 'v:0', video=True)
        check(bounded['packets'] == baseline['packets'][:len(bounded['packets'])],
              'Bounded original video NAL hashes and rational timestamps match extracted prefix')
        report['excerpt_apple'] = apple(native, excerpt)
        check(report['excerpt_apple']['start_failed'], 'Extracted hev1 reproduces Apple rejection')
        fixed = root/'strict.mp4'
        run([FFMPEG, '-v', 'error', '-nostdin', '-n', '-i', excerpt, '-map', '0',
             '-c', 'copy', '-bsf:v:0', 'filter_units=remove_types=32|33|34', '-tag:v:0', 'hvc1',
             '-strict', 'unofficial', fixed])
        normalized = packet_info(fixed, 'v:0', video=True)
        check(retained(baseline) == retained(normalized),
              'All excerpt VCL/SEI/RPU/AUD NAL bytes/order and rational timestamps preserved')
        check(all(normalized['nal_counts'].get(t, 0) == 0 for t in (32, 33, 34)),
              'Strict output contains no in-band VPS/SPS/PPS')
        before_meta, after_meta = metadata.inspect(excerpt), metadata.inspect(fixed)
        atoms = lambda value: [x for x in value if x.get('atom') not in (None, 'hvcC')]
        check(atoms(before_meta) == atoms(after_meta), 'dvvC/colr/clli/mdcv preserved byte-for-byte')
        config = lambda value: next(x for x in value if x.get('atom') == 'hvcC')['arrays']
        a, b = config(before_meta), config(after_meta)
        parameter_hashes = {x['type']: {n['sha256'] for n in x['nals']}
                            for x in a if x['type'] in (32, 33, 34)}
        check(all(nal[1] in parameter_hashes.get(nal[0], set())
                  for packet in baseline['packets'] for nal in packet['nals'] if nal[0] in (32, 33, 34)),
              'Every removed in-band parameter set already exists byte-for-byte in hvcC')
        check([dict(x, complete=True) for x in a] == [dict(x, complete=True) for x in b]
              and all(x['complete'] for x in b if x['type'] in (32, 33, 34)),
              'hvcC parameter sets preserved with complete VPS/SPS/PPS arrays')
        audio_count = sum(s['codec_type'] == 'audio' for s in streams(excerpt))
        check(audio_count == sum(s['codec_type'] == 'audio' for s in streams(source)),
              'Every original audio track included in excerpt')
        for index in range(audio_count):
            check(packet_info(excerpt, 'a:%d' % index) == packet_info(fixed, 'a:%d' % index),
                  'Audio track %d packet hashes and rational timestamps preserved' % index)
        report['fixed_apple'] = apple(native, fixed, 'all')
        check(report['fixed_apple']['images'] == [len(normalized['packets'])]
              and report['fixed_apple']['statuses'] == [2], 'Apple decodes every excerpt frame to image buffers through completed status')
        report['seek_apple'] = apple(native, fixed, 'seek')
        check(report['seek_apple']['images'] == [3], 'Apple produces images after seek to one second')
        negative = root/'missing-rpu.mp4'
        run([FFMPEG, '-v', 'error', '-nostdin', '-n', '-i', fixed, '-map', '0', '-c', 'copy',
             '-bsf:v:0', 'filter_units=remove_types=62|63', '-strict', 'unofficial', negative])
        check(retained(normalized) != retained(packet_info(negative, 'v:0', video=True)),
              'Negative control: actual RPU removal is detected by retained-NAL comparison')
        # Never map sparse original subtitle/chapter tracks just to test preservation:
        # an output -t limit does not bound input demuxing while waiting for them.
        report['excerpt_atoms'] = metadata_atoms(excerpt)
        report['normalized_atoms'] = metadata_atoms(fixed)
        relation_types = lambda records: sorted(x['path'].split('/')[-1].split(':')[0]
                                                for x in records if '/tref:' in x['path'])
        report['original_reference_types'] = relation_types(report['original_atoms'])
        report['excerpt_reference_types'] = relation_types(report['excerpt_atoms'])
        report['normalized_reference_types'] = relation_types(report['normalized_atoms'])
        report['original_streams'] = streams(source)
        report['baseline'] = baseline
        report['normalized'] = normalized
        report['excerpt_metadata'] = before_meta
        report['normalized_metadata'] = after_meta
        check(source.stat() == before, 'Original source identity/size/mtime unchanged')
        report['limits'] = ['No application/TV/AirPlay test or whole-film scan',
            'Excerpt has video and all audio only; subtitles, artwork, chapters and native associations are NOT certified',
            'No automatic production fix installed; full-track FFmpeg copy cannot be assumed safe',
            'DV configuration/RPU bytes preserved; not independent Dolby display certification']
    finally:
        shutil.rmtree(root)
    report['private_media_deleted'] = not root.exists()
    path = args.scratch/'dv81-remux-results.json'
    # Report is exclusively hashes, codec records, rational timing and sanitized diagnostics.
    path.write_text(json.dumps(report, indent=2))
    print(json.dumps(dict(checks=report['checks'],
                         original_reference_types=report['original_reference_types'],
                         excerpt_reference_types=report['excerpt_reference_types'],
                         normalized_reference_types=report['normalized_reference_types'],
                         normalized_frame_count=len(normalized['packets']),
                         apple=report['fixed_apple'],
                         private_media_deleted=report['private_media_deleted'], report=str(path)), indent=2))


if __name__ == '__main__':
    main()
