import runpy,sys,json
from pathlib import Path
h=runpy.run_path(str(Path(__file__).with_name('hevc-dv81-remux-repro.py')))
r=Path(sys.argv[1])
a=h['metadata_atoms'](r/'generated-rich.mp4');b=h['metadata_atoms'](r/'queued-rich.mp4')
for side,items,other in [('before',a,b),('after',b,a)]:
    print(side)
    for x in items:
        if x not in other: print(json.dumps(x))
