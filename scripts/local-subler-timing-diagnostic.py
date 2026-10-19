import runpy
from pathlib import Path
import sys
helpers=runpy.run_path(str(Path(__file__).with_name('local-subler-background-repro.py')))
root=Path(sys.argv[1])
for selector, video in [('v:0', True), ('a:0', False)]:
    a=helpers['packets'](root/'generated.mkv',selector,video)
    b=helpers['packets'](root/'queued-mkv.mp4',selector,video)
    print(selector, 'lengths',len(a),len(b))
    key='nals' if video else 'sha256'
    aa=[[n for n in p[key] if n[0] not in [32,33,34]] if video else p[key] for p in a]
    bb=[p[key] for p in b]
    print('payloads equal',aa==bb)
    for x,y in list(zip(a,b))[:6]:
        print({k:v for k,v in x.items() if k!=key},{k:v for k,v in y.items() if k!=key})
