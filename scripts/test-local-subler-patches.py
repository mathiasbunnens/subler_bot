#!/usr/bin/env python3
"""Reconstruct patched files from pristine pinned git objects in scratch, offline."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
for checkout, base, patch in [
    ('vendor-local/Subler', '9077b6d149be621ff7d7b0d8eb46839a56610844', 'subler.patch'),
    ('vendor-local/Subler/MP42Foundation', 'bfa477b799ce55716f744638e6dfe3f23d39c5d7', 'mp42foundation.patch'),
]:
    source = root / checkout
    diff = root / 'patches/local-subler' / patch
    with tempfile.TemporaryDirectory(prefix='subler-source-replay-', dir=os.environ['TMPDIR']) as temp:
        archive = subprocess.run(['git', '-C', source, 'archive', base], check=True, capture_output=True).stdout
        subprocess.run(['tar', '-xf', '-', '-C', temp], input=archive, check=True)
        subprocess.run(['git', 'apply', '--check', diff], cwd=temp, check=True)
        subprocess.run(['git', 'apply', diff], cwd=temp, check=True)
        if patch == 'subler.patch':
            shutdown = root / 'patches/local-subler/graceful-quit.patch'
            subprocess.run(['git', 'apply', '--check', shutdown], cwd=temp, check=True)
            subprocess.run(['git', 'apply', shutdown], cwd=temp, check=True)
        files = [line[6:] for line in diff.read_text().splitlines() if line.startswith('+++ b/')]
        assert files
        for name in files:
            assert (Path(temp) / name).read_bytes() == (source / name).read_bytes(), name
        print(f'PASS: {patch}: {len(files)} reconstructed files match reviewed native checkout')
