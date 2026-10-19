#!/usr/bin/env python3
"""Exercise ONLY the distinct local Subler build on generated fixtures; never user media.

Uses its isolated queue. Refuses any pre-existing documents or active queue items.
Does not clear queue entries, terminate applications, or activate windows.
"""
import argparse
from decimal import Decimal
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import struct
import tempfile
import time


def run(args, *, text=None, timeout=120):
    p = subprocess.run(list(map(str, args)), input=text, text=True, capture_output=True, timeout=timeout)
    if p.returncode:
        raise RuntimeError(f'{Path(str(args[0])).name} exit {p.returncode}: {p.stderr[-1800:]}')
    return p.stdout + p.stderr


def literal(value):
    return json.dumps(str(value), ensure_ascii=False)


def packets(path, selector, video=False):
    info = json.loads(run(['/opt/homebrew/bin/ffprobe', '-v', 'error', '-select_streams', selector,
                          '-show_packets', '-show_streams', '-show_data', '-show_entries',
                          'packet=pts,dts,duration,data:stream=time_base', '-of', 'json', path]))
    base = Fraction(info['streams'][0]['time_base'])
    result = []
    for packet in info['packets']:
        data = b''.join(bytes.fromhex(line.split(':', 1)[1].strip().split('  ')[0])
                        for line in packet['data'].splitlines() if ':' in line)
        timing = {k: str(int(packet[k]) * base) if k in packet else None for k in ['pts', 'dts', 'duration']}
        if not video:
            result.append(dict(timing, sha256=hashlib.sha256(data).hexdigest()))
            continue
        nals = []
        while data:
            size = int.from_bytes(data[:4], 'big')
            assert 2 <= size <= len(data) - 4
            nal, data = data[4:4+size], data[4+size:]
            nals.append([(nal[0] >> 1) & 63, hashlib.sha256(nal).hexdigest()])
        result.append(dict(timing, nals=nals))
    return result


def track_structure(path):
    """Generated MP4s only: flags, alternates, languages and edit lists by track."""
    result = []
    data = path.read_bytes()
    def walk(start, stop, track=None):
        pos = start
        while pos + 8 <= stop:
            size, typ = struct.unpack_from('>I4s', data, pos); header = 8
            if size == 1: size = struct.unpack_from('>Q', data, pos+8)[0]; header = 16
            if size == 0: size = stop-pos
            assert header <= size <= stop-pos
            body, end = pos+header, pos+size
            if typ == b'trak':
                entry = {}; result.append(entry); walk(body, end, entry)
            elif typ in [b'moov', b'mdia', b'edts']:
                walk(body, end, track)
            elif track is not None and typ == b'tkhd':
                shift = 12 if data[body] == 1 else 0
                track['flags'] = data[body+1:body+4].hex()
                track['layer_alternate'] = data[body+32+shift:body+36+shift].hex()
            elif track is not None and typ == b'mdhd':
                offset = 32 if data[body] == 1 else 20
                track['language'] = data[body+offset:body+offset+2].hex()
            elif track is not None and typ == b'elst':
                track['edit_list'] = data[body:end].hex()
            pos = end
    walk(0,len(data))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--scratch', type=Path, required=True)
    parser.add_argument('--authorize-local-build', action='store_true', required=True)
    args = parser.parse_args()
    info = run(['/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleIdentifier', args.app / 'Contents/Info.plist']).strip()
    assert info == 'local.sublerautomation.Subler', 'Refusing any installed/foreign application'
    run(['codesign', '--verify', '--deep', '--strict', args.app])
    root = Path(tempfile.mkdtemp(prefix='local-subler-', dir=args.scratch))
    result = {'evidence': str(root), 'checks': {}, 'limits': ['direct local queue probe; Swift service integration is tested separately', 'generated HDR10 only, no DV claim']}
    observations = []
    doc = None

    def script(body):
        return run(['osascript'], text=f'tell application {literal(args.app)}\n{body}\nend tell\n', timeout=300).strip()

    def observe():
        state = script('return background state')
        observations.append(state)
        fields = state.split('|')
        assert fields[:3] == ['0', 'false', '2'], 'Local build constructed windows or became active: ' + state
        return int(fields[3])

    try:
        run(['open', '-gj', args.app])
        assert observe() == 0, 'Local build has existing documents; refusing to use them'
        script('repeat with n from 1 to count of queue items\nif status of queue item n is ready or status of queue item n is working then error "Foreign active local queue item"\nend repeat')
        framework = args.app / 'Contents/Frameworks'
        probe = root / 'probe'
        run(['clang', '-fobjc-arc', '-Wno-deprecated-declarations', '-F', framework,
             '-framework', 'MP42Foundation', '-framework', 'Foundation', '-framework', 'AVFoundation',
             '-framework', 'CoreMedia', '-framework', 'CoreVideo', '-Wl,-headerpad_max_install_names', '-Wl,-rpath,' + str(framework),
             Path(__file__).with_name('hevc-native-probe.m'), '-o', probe])
        run(['install_name_tool', '-change', '@loader_path/../Frameworks/MP42Foundation.framework/Versions/A/MP42Foundation',
             framework / 'MP42Foundation.framework/Versions/A/MP42Foundation', probe])
        run(['codesign', '--force', '--sign', '-', probe])
        helpers = runpy.run_path(str(Path(__file__).with_name('hevc-dv81-remux-repro.py')))
        for ext in ['mp4', 'mkv', 'rich', 'negative']:
            source = root / ('generated.' + ext)
            target = root / ('queued-' + ext + '.mp4')
            if ext == 'negative':
                source = root / 'changing-parameters.mp4'
                shutil.copyfile(root / 'generated.mp4', source)
                positions = json.loads(run(['/opt/homebrew/bin/ffprobe', '-v','error','-select_streams','v:0',
                    '-show_packets','-show_entries','packet=pos,size','-of','json', source]))['packets']
                data = bytearray(source.read_bytes()); changed = False
                for packet in positions:
                    pos = int(packet['pos']); stop = pos + int(packet['size'])
                    while pos < stop:
                        size = int.from_bytes(data[pos:pos+4], 'big')
                        assert 2 <= size <= stop-pos-4
                        if (data[pos+4] >> 1) & 63 == 32:
                            data[pos+3+size] ^= 1; changed = True; break
                        pos += size+4
                    if changed: break
                assert changed
                source.write_bytes(data)
            elif ext == 'rich':
                source = root / 'generated-rich.mp4'
                subtitle = root / 'generated.srt'
                subtitle.write_text('1\n00:00:00,100 --> 00:00:01,800\nGenerated subtitle\n')
                streams = root / 'rich-streams.mp4'
                run(['/opt/homebrew/bin/ffmpeg', '-v', 'error', '-nostdin', '-n',
                     '-i', root / 'generated.mp4', '-i', subtitle, '-map', '0:v:0',
                     '-map', '0:a:0', '-map', '0:a:0', '-map', '0:a:0',
                     '-map', '0:a:0', '-map', '0:a:0', '-map', '0:a:0', '-map', '1:s:0',
                     '-c:v', 'copy', '-c:a:0', 'copy', '-c:a:1', 'copy', '-c:a:2', 'copy',
                     '-c:a:3', 'ac3', '-c:a:4', 'ac3', '-c:a:5', 'eac3', '-c:s', 'mov_text', streams])
                cover = root / 'cover.png'
                run(['/opt/homebrew/bin/ffmpeg', '-v', 'error', '-nostdin', '-n',
                     '-f', 'lavfi', '-i', 'color=c=blue:size=32x32', '-frames:v', '1', '-threads', '1', cover])
                builder = root / 'rich-builder'
                run(['clang', '-fobjc-arc', '-F', framework, '-framework', 'MP42Foundation', '-framework', 'Foundation',
                     '-Wl,-headerpad_max_install_names', '-Wl,-rpath,' + str(framework), Path(__file__).with_name('local-subler-rich-fixture.m'), '-o', builder])
                run(['install_name_tool', '-change', '@loader_path/../Frameworks/MP42Foundation.framework/Versions/A/MP42Foundation',
                     framework / 'MP42Foundation.framework/Versions/A/MP42Foundation', builder])
                run(['codesign', '--force', '--sign', '-', builder])
                run([builder, streams, source, cover])
            else:
                run(['/opt/homebrew/bin/ffmpeg', '-v', 'error', '-nostdin', '-n',
                 '-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=24:duration=2',
                 '-f', 'lavfi', '-i', 'sine=frequency=440:duration=2',
                 '-c:v', 'libx265', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p10le',
                 '-color_primaries', 'bt2020', '-color_trc', 'smpte2084', '-colorspace', 'bt2020nc',
                 '-x265-params', 'log-level=error:repeat-headers=1:hdr10=1:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(40000000,50):max-cll=1100,668',
                     '-c:a', 'aac', '-shortest', source])
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            doc = int(Decimal(script(f'return (import background file (POSIX file {literal(source)})) as integer')))
            assert observe() == 1
            script(f'send to queue (POSIX file {literal(target)}) owned token {doc}')
            for _ in range(50):
                if observe() == 0:
                    doc = None
                    break
                time.sleep(.02)
            assert doc is None, 'Owned document was not closed after enqueue'
            # Match exact destination and stable persistent ID; never start foreign work.
            index = int(script(f'repeat with n from 1 to count of queue items\nif destinationPath of queue item n is {literal(target)} then return n as integer\nend repeat\nerror "Missing owned item"'))
            owned = script(f'return id of queue item {index}')
            script(f'repeat with n from 1 to count of queue items\nif id of queue item n is not {literal(owned)} then\nif status of queue item n is ready or status of queue item n is working then error "Foreign active item"\nend if\nend repeat\nstart queue')
            state = "ready"
            for _ in range(120):
                observe()
                state = script(f'if id of queue item {index} is not {literal(owned)} then error "Owned item replaced"\nreturn (status of queue item {index}) as text')
                if state not in ['ready', 'working']:
                    break
                time.sleep(.1)
            if ext == 'negative':
                result['checks']['changing_parameters_native_refusal'] = state == 'failed'
                result['checks']['negative_source_unchanged'] = hashlib.sha256(source.read_bytes()).hexdigest() == digest
                assert state == 'failed', 'Changed parameter set must fail rather than publish'
                continue
            assert state == 'completed', 'Owned queue item failed: ' + state
            decode = run([probe, 'inspect', target, 'all'])
            (root / (ext + '-decode.log')).write_text(decode)
            images = [int(n) for n in re.findall(r'decodedImages=(\d+)', decode)]
            seek = run([probe, 'inspect', target, 'seek'])
            (root / (ext + '-seek.log')).write_text(seek)
            result[ext] = {'images': images, 'reader_completed': 'status=2 error=(null)' in decode,
                           'seek_images': [int(n) for n in re.findall(r'decodedImages=(\d+)', seek)]}
            result['checks'][ext + '_source_unchanged'] = hashlib.sha256(source.read_bytes()).hexdigest() == digest
            result['checks'][ext + '_all_images'] = images == [48] and result[ext]['reader_completed']
            result['checks'][ext + '_seek'] = result[ext]['seek_images'] == [3]
            before, after = packets(source, 'v:0', True), packets(target, 'v:0', True)
            retained = [dict(p, nals=[n for n in p['nals'] if n[0] not in [32, 33, 34]]) for p in before]
            if ext == 'mkv':
                baseline = root / 'native-mkv-baseline.mp4'
                run([probe, 'mux', source, baseline, 'true'])
                baseline_video = packets(baseline, 'v:0', True)
                result['checks']['mkv_native_baseline_nals_timing'] = [dict(p, nals=[n for n in p['nals'] if n[0] not in [32,33,34]]) for p in baseline_video] == after
                result['checks']['mkv_native_baseline_audio_timing'] = packets(baseline, 'a:0') == packets(target, 'a:0')
                result['checks']['mkv_original_payloads'] = [p['nals'] for p in retained] == [p['nals'] for p in after]
                source_audio, target_audio = packets(source, 'a:0'), packets(target, 'a:0')
                result['checks']['mkv_original_audio_payloads'] = [p['sha256'] for p in source_audio] == [p['sha256'] for p in target_audio]
                result['checks']['mkv_pts_within_source_tick'] = all(len(a) == len(b) and all(
                    abs(Fraction(x['pts']) - Fraction(y['pts'])) <= Fraction(1,1000) for x,y in zip(a,b))
                    for a,b in [(before,after),(source_audio,target_audio)])
                result[ext]['original_rational_timing_exact'] = retained == after and source_audio == target_audio
            else:
                result['checks'][ext + '_retained_nals_timing'] = retained == after
                result['checks'][ext + '_audio_packets_timing'] = all(packets(source, f'a:{i}') == packets(target, f'a:{i}') for i in range(6 if ext == 'rich' else 1))
            result['checks'][ext + '_no_inband_parameters'] = not any(n[0] in [32,33,34] for p in after for n in p['nals'])
            metadata = runpy.run_path(str(Path(__file__).with_name('hevc-container-metadata.py')))['inspect']
            records = metadata(target)
            result['checks'][ext + '_hvc1_complete'] = any('/hvc1' in r.get('path', '') for r in records) and all(
                a['complete'] for r in records if r.get('atom') == 'hvcC' for a in r['arrays'] if a['type'] in [32,33,34])
            if ext == 'mp4':
                hdr = lambda rs: [(r['atom'], r['sha256']) for r in rs if r.get('atom') in ['colr','clli','mdcv','dvvC','dvcC']]
                result['checks']['mp4_hdr_atoms'] = hdr(metadata(source)) == hdr(records)
            if ext != 'mkv':
                arrays = lambda rs: [dict(a, complete=True) for r in rs if r.get('atom') == 'hvcC' for a in r['arrays']]
                result['checks'][ext + '_configuration_nals'] = arrays(metadata(source)) == arrays(records)
            if ext == 'rich':
                atoms = helpers['metadata_atoms']
                original_atoms, output_atoms = atoms(source), atoms(target)
                stable_atoms = lambda items: [dict(a, path=re.sub(r'/tref:\d+', '/tref', a['path'])) for a in items]
                result['checks']['rich_fallback_chapter_artwork_identity'] = stable_atoms(original_atoms) == stable_atoms(output_atoms)
                result['checks']['rich_three_fallbacks_present'] = sum('/fall:' in a['path'] for a in original_atoms) == 3
                result['checks']['rich_subtitle_packets_timing'] = packets(source, 's:0') == packets(target, 's:0')
                chapters = lambda p: json.loads(run(['/opt/homebrew/bin/ffprobe', '-v', 'error', '-show_chapters', '-of', 'json', p]))['chapters']
                result['checks']['rich_chapters'] = chapters(source) == chapters(target)
                result['checks']['rich_track_structure_edit_lists'] = track_structure(source) == track_structure(target)
        result['checks']['windowless_inactive'] = bool(observations)
    finally:
        if doc is not None:
            script(f'close document owned token {doc}')
        result['observations'] = observations
        (root / 'results.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result, indent=2))
    assert all(result['checks'].values()), 'Preservation/playback gate failed; not production-ready'


if __name__ == '__main__':
    main()
