import json
import subprocess
import sys
from pathlib import Path
for name in sys.argv[1:]:
    result = json.loads(subprocess.check_output(['/opt/homebrew/bin/ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_packets', '-show_entries', 'packet=pos,size', '-of', 'json', name]))
    counts = {}
    with open(name, 'rb') as stream:
        for packet in result['packets']:
            stream.seek(int(packet['pos']))
            data = stream.read(int(packet['size']))
            offset = 0
            while offset < len(data):
                size = int.from_bytes(data[offset:offset+4], 'big')
                offset += 4
                if size < 2 or offset+size > len(data): raise ValueError('Invalid NAL')
                typ = (data[offset] >> 1) & 63
                counts[typ] = counts.get(typ, 0)+1
                offset += size
    print(Path(name).name, counts)
