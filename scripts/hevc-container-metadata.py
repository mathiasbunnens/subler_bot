#!/usr/bin/env python3
"""Metadata-only MP4 inspection: skip mdat, report bounded HEVC records."""
import hashlib
import json
import struct
import sys
from pathlib import Path

def inspect(path):
    result = []
    with open(path, 'rb') as f:
        f.seek(0, 2)
        end = f.tell()
        def walk(start, stop, trail=''):
            pos = start
            while pos + 8 <= stop:
                f.seek(pos)
                size, typ = struct.unpack('>I4s', f.read(8))
                header = 8
                if size == 1:
                    size = struct.unpack('>Q', f.read(8))[0]; header = 16
                if size == 0: size = stop - pos
                if size < header or pos + size > stop: raise ValueError((trail, pos, size))
                name = typ.decode('latin1')
                here = trail + '/' + name
                body = pos + header
                if name in ['moov','trak','mdia','minf','stbl']:
                    walk(body, pos + size, here)
                elif name == 'stsd': walk(body + 8, pos + size, here)
                elif name in ['hvc1','hev1','dvh1','dvhe']:
                    result.append({'path':here,'offset':pos,'size':size})
                    walk(body + 78, pos + size, here)
                elif name in ['hvcC','dvcC','dvvC','colr','mdcv','clli']:
                    if size > 1024*1024: raise ValueError('Oversized metadata')
                    f.seek(body); data=f.read(size-header)
                    record={'atom':name,'sha256':hashlib.sha256(data).hexdigest(),'length':len(data)}
                    if name == 'hvcC':
                        record['lengthSize']=(data[21]&3)+1
                        arrays=[]; p=23
                        for _ in range(data[22]):
                            flags=data[p]; n=int.from_bytes(data[p+1:p+3], 'big'); p+=3
                            nals=[]
                            for _ in range(n):
                                length=int.from_bytes(data[p:p+2],'big'); p+=2
                                nal=data[p:p+length]; p+=length
                                nals.append({'length':length,'sha256':hashlib.sha256(nal).hexdigest()})
                            arrays.append({'type':flags&63,'complete':bool(flags&128),'nals':nals})
                        record['arrays']=arrays
                    else: record['hex']=data.hex()
                    result.append(record)
                pos += size
        walk(0,end)
    return result

if __name__ == '__main__':
    for i,path in enumerate(sys.argv[1:]):
        print(json.dumps({'input':i,'metadata':inspect(path)},ensure_ascii=False,indent=2))
