#!/usr/bin/env python3
"""Authorized TWO-SECOND DV8.1 probe of the distinct local queue, not a film conversion.
Deletes all private media/binaries and suppresses private tool errors.
The extracted fixture intentionally omits original chapter/subtitle/fallback associations;
those are tested by the separate generated rich-container harness.
"""
import argparse
import json
from pathlib import Path
import runpy
import shutil
import tempfile
import time


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--app', type=Path, required=True)
    p.add_argument('--scratch', type=Path, required=True)
    p.add_argument('--authorize-personal-excerpt', action='store_true', required=True)
    args = p.parse_args()
    scripts = Path(__file__).parent
    h = runpy.run_path(str(scripts / 'hevc-dv81-remux-repro.py'))
    meta = runpy.run_path(str(scripts / 'hevc-container-metadata.py'))['inspect']
    literal = runpy.run_path(str(scripts / 'local-subler-background-repro.py'))['literal']
    run = h['run']
    before = args.source.stat()
    root = Path(tempfile.mkdtemp(prefix='local-dv-private-', dir=args.scratch)); root.chmod(0o700)
    report = {'checks': {}, 'limits': ['Two-second video/all-audio fixture only', 'Not whole-film, TV or Dolby display certification', 'Original native associations are not present in extracted fixture']}
    doc = None
    def script(body):
        import subprocess
        result = subprocess.run(['osascript'], input=f'tell application {literal(args.app)}\n{body}\nend tell\n', text=True, capture_output=True, timeout=300)
        if result.returncode: raise RuntimeError('Private local Apple Event failed; details suppressed')
        return result.stdout.strip()
    try:
        identity = run(['/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleIdentifier', args.app/'Contents/Info.plist']).stdout.decode().strip()
        assert identity == 'local.sublerautomation.Subler'
        assert script('return background state') == '0|false|2|0'
        script('repeat with n from 1 to count of queue items\nif status of queue item n is ready or status of queue item n is working then error "Foreign work"\nend repeat')
        framework = args.app/'Contents/Frameworks'; native=root/'native'
        run(['clang', '-fobjc-arc', '-Wno-deprecated-declarations', '-F', framework, '-framework', 'MP42Foundation',
             '-framework', 'Foundation', '-framework', 'AVFoundation', '-framework', 'CoreMedia', '-framework', 'CoreVideo',
             '-Wl,-headerpad_max_install_names', '-Wl,-rpath,'+str(framework), scripts/'hevc-native-probe.m', '-o', native])
        run(['install_name_tool', '-change', '@loader_path/../Frameworks/MP42Foundation.framework/Versions/A/MP42Foundation', framework/'MP42Foundation.framework/Versions/A/MP42Foundation', native])
        run(['codesign', '--force', '--sign', '-', native])
        record = bytes.fromhex(next(a for a in meta(args.source) if a.get('atom') in ['dvvC','dvcC'])['hex'])
        assert record[2] >> 1 == 8 and record[4] >> 4 == 1 and record[3] & 7 == 5
        source=root/'excerpt.mp4'; target=root/'native-output.mp4'
        run([h['FFMPEG'], '-v','error','-nostdin','-n','-i',args.source,'-t','2','-map','0:v:0','-map','0:a?',
             '-c','copy','-strict','unofficial','-map_metadata','-1','-map_chapters','-1',source])
        baseline = h['packet_info'](source, 'v:0', video=True)
        original_prefix = h['packet_info'](args.source, 'v:0', video=True, bounded=True)
        report['checks']['original_prefix_nals_timing'] = original_prefix['packets'] == baseline['packets'][:len(original_prefix['packets'])]
        report['before_apple'] = h['apple'](native, source)
        report['checks']['before_decoder_rejects'] = report['before_apple']['start_failed']
        doc=script(f'return import background file (POSIX file {literal(source)})')
        report['checks']['import_windowless'] = script('return background state') == '0|false|2|1'
        script(f'send to queue (POSIX file {literal(target)}) owned token {literal(doc)}')
        for _ in range(100):
            if script('return background state') == '0|false|2|0': doc=None; break
            time.sleep(.02)
        assert doc is None
        index=int(script(f'repeat with n from 1 to count of queue items\nif destinationPath of queue item n is {literal(target)} then return n as integer\nend repeat\nerror "Missing owned item"'))
        owned=script(f'return id of queue item {index}')
        script(f'repeat with n from 1 to count of queue items\nif id of queue item n is not {literal(owned)} then\nif status of queue item n is ready or status of queue item n is working then error "Foreign work"\nend if\nend repeat\nstart queue')
        state='ready'
        for _ in range(300):
            state=script(f'if id of queue item {index} is not {literal(owned)} then error "Replaced item"\nreturn (status of queue item {index}) as text')
            if state not in ['ready','working']: break
            time.sleep(.1)
        assert state=='completed'
        normalized=h['packet_info'](target,'v:0',video=True)
        report['checks']['retained_nals_timing'] = h['retained'](baseline)==h['retained'](normalized)
        report['checks']['no_inband_parameters'] = all(normalized['nal_counts'].get(t,0)==0 for t in [32,33,34])
        atoms=lambda records: sorted((a['atom'],a['sha256']) for a in records if a.get('atom') in ['dvvC','dvcC','colr','clli','mdcv'])
        report['before_hdr_atoms'] = atoms(meta(source))
        report['after_hdr_atoms'] = atoms(meta(target))
        report['checks']['dv_hdr_atoms'] = report['before_hdr_atoms']==report['after_hdr_atoms']
        arrays=lambda rs: [dict(a,complete=True) for r in rs if r.get('atom')=='hvcC' for a in r['arrays']]
        report['checks']['configuration_nals']=arrays(meta(source))==arrays(meta(target))
        audio_count=sum(s['codec_type']=='audio' for s in h['streams'](source))
        report['checks']['all_original_audio_tracks'] = audio_count == sum(s['codec_type']=='audio' for s in h['streams'](args.source))
        report['checks']['all_audio_packets_timing'] = all(h['packet_info'](source,f'a:{i}')==h['packet_info'](target,f'a:{i}') for i in range(audio_count))
        report['after_apple']=h['apple'](native,target,'all')
        report['seek_apple']=h['apple'](native,target,'seek')
        report['checks']['every_apple_image']=report['after_apple']['images']==[len(normalized['packets'])] and report['after_apple']['statuses']==[2]
        report['checks']['seek_images']=report['seek_apple']['images']==[3]
        report['checks']['closed_windowless']=script('return background state')=='0|false|2|0'
        report['checks']['original_unchanged']=args.source.stat()==before
    finally:
        if doc is not None: script(f'close document owned token {literal(doc)}')
        shutil.rmtree(root)
        report['private_media_deleted']=not root.exists()
        out=args.scratch/'local-subler-dv81-results.json'
        out.write_text(json.dumps(report,indent=2))
        print(json.dumps(report,indent=2))
    assert all(report['checks'].values()), 'Native DV gate failed; not a production fix'

if __name__=='__main__': main()
