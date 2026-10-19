#!/usr/bin/env python3
"""Synthetic-only packaging experiment. Never opens Subler or its live queue.

Requires installed Subler/MP42Foundation, clang, FFmpeg with libx265 and FFprobe.
Writes exclusively to a newly created child of --scratch; no media input option.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

from importlib.util import module_from_spec, spec_from_file_location


def run(args):
    result = subprocess.run([str(x) for x in args], capture_output=True, text=True,
                            timeout=120, check=True)
    return result.stdout + result.stderr


def packets(probe, path, selector):
    info = json.loads(run([probe, '-v', 'error', '-select_streams', selector,
                           '-show_packets', '-show_entries', 'packet=pos,size,pts,dts,duration',
                           '-of', 'json', path]))
    result = []
    counts = {}
    with path.open('rb') as stream:
        for packet in info['packets']:
            stream.seek(int(packet['pos']))
            data = stream.read(int(packet['size']))
            assert len(data) == int(packet['size'])
            result.append({**{k: packet.get(k) for k in ('pts', 'dts', 'duration')},
                           'sha256': hashlib.sha256(data).hexdigest()})
            if selector == 'v:0':
                offset = 0
                while offset < len(data):
                    assert len(data) - offset >= 4
                    size = int.from_bytes(data[offset:offset+4], 'big')
                    offset += 4
                    assert 2 <= size <= len(data) - offset
                    typ = (data[offset] >> 1) & 63
                    counts[typ] = counts.get(typ, 0) + 1
                    offset += size
    assert result, 'Missing generated packets'
    return result, counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scratch', type=Path, required=True)
    parser.add_argument('--ffmpeg', default='/opt/homebrew/bin/ffmpeg')
    parser.add_argument('--ffprobe', default='/opt/homebrew/bin/ffprobe')
    parser.add_argument('--subler', type=Path, default=Path('/Applications/Subler.app'))
    args = parser.parse_args()
    root = Path(tempfile.mkdtemp(prefix='hevc-packaging-', dir=args.scratch))
    scripts = Path(__file__).resolve().parent
    framework = args.subler / 'Contents/Frameworks'
    native = root / 'native-probe'
    compile_log = run(['clang', '-fobjc-arc', '-Wno-deprecated-declarations',
                      '-F', framework, '-framework', 'MP42Foundation',
                      '-framework', 'Foundation', '-framework', 'AVFoundation',
                      '-framework', 'CoreMedia', '-framework', 'CoreVideo',
                      '-Wl,-rpath,' + str(framework), scripts / 'hevc-native-probe.m', '-o', native])
    (root / 'compile.log').write_text(compile_log)
    run(['install_name_tool', '-change',
         '@loader_path/../Frameworks/MP42Foundation.framework/Versions/A/MP42Foundation',
         framework / 'MP42Foundation.framework/Versions/A/MP42Foundation', native])
    run(['codesign', '--force', '--sign', '-', native])
    source = root / 'generated-hdr10.mkv'
    encode_log = run([args.ffmpeg, '-v', 'error', '-nostdin', '-n',
                     '-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=24:duration=1',
                     '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1',
                     '-c:v', 'libx265', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p10le',
                     '-color_primaries', 'bt2020', '-color_trc', 'smpte2084', '-colorspace', 'bt2020nc',
                     '-x265-params', 'log-level=error:repeat-headers=1:hdr10=1:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(40000000,50):max-cll=1100,668',
                     '-c:a', 'aac', '-shortest', source])
    (root / 'encode.log').write_text(encode_log)
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    spec = spec_from_file_location('metadata', scripts / 'hevc-container-metadata.py')
    assert spec is not None and spec.loader is not None
    metadata = module_from_spec(spec)
    spec.loader.exec_module(metadata)
    results = {}
    for name, force in [('queue', 'false'), ('ui', 'true')]:
        output = root / (name + '.mp4')
        run([native, 'mux', source, output, force])
        decode = run([native, 'inspect', output])
        (root / (name + '-decode.log')).write_text(decode)
        video, nals = packets(args.ffprobe, output, 'v:0')
        audio, _ = packets(args.ffprobe, output, 'a:0')
        results[name] = {'metadata': metadata.inspect(output), 'video': video,
                         'audio': audio, 'nal_counts': nals,
                         'decoded_images': [int(x) for x in re.findall(r'decodedImages=(\d+)', decode)],
                         'decoder_start_failed': 'start error=' in decode}
    assert results['queue']['decoder_start_failed'], 'Expected hev1 Apple rejection not reproduced'
    assert results['ui']['decoded_images'] == [3], 'hvc1 native output did not decode'
    assert results['queue']['video'] == results['ui']['video'], 'Video payload/timing differs'
    assert results['queue']['audio'] == results['ui']['audio'], 'Audio payload/timing differs'
    assert all(results[name]['nal_counts'].get(typ, 0) > 0
               for name in results for typ in (32, 33, 34)), 'In-band parameters not reproduced'
    assert hashlib.sha256(source.read_bytes()).hexdigest() == source_hash, 'Source changed'
    results['checks'] = ['hev1 decoder rejection', 'hvc1 three Apple images',
                         'identical video payload/timing', 'identical audio payload/timing',
                         'in-band VPS/SPS/PPS in both', 'generated source unchanged']
    results['limits'] = ['HDR10 synthetic only, not DV8.1', 'native library options, not live AppleScript queue',
                         'hvc1 decoding is not proof of hvc1 bitstream conformity', 'no product correction installed']
    (root / 'results.json').write_text(json.dumps(results, indent=2))
    print(json.dumps({'evidence': str(root), 'checks': results['checks'], 'limits': results['limits']}, indent=2))


if __name__ == '__main__':
    main()
