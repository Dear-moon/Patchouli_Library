#!/usr/bin/env python3
"""Copy the accepted, lossless artwork to native Form resources without re-encoding."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
IDS = ('archive', 'shelf', 'editorial', 'constellation', 'signal', 'score', 'ink', 'festival')

for identity in IDS:
    source = ROOT / f'assets/reading_art/{identity}-117.webp'
    target = ROOT / f'ohos/entry/src/main/resources/base/media/reading_art_{identity}_117.webp'
    if not source.is_file():
        raise FileNotFoundError(source)
    shutil.copyfile(source, target)
    obsolete = target.with_name(f'reading_art_{identity}_110.webp')
    if obsolete.is_file():
        obsolete.unlink()
print('Copied eight accepted 117 artworks to native Harmony Form resources.')
