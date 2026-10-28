"""Build/check UI-only theme thumbnails; never change full native widget art.

The Flutter selector already decodes these pictures at 420 pixels. Ship that
resolution once, losslessly encoded, instead of bundling eight extra masters.
Requires Pillow; normal app builds consume the checked-in WebP outputs.
"""
import argparse
import os
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
THEMES = ('archive', 'shelf', 'editorial', 'constellation', 'signal', 'score', 'ink', 'festival')
SIZE = (420, 280)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    folder = ROOT / 'assets/reading_previews'
    if not args.check:
        folder.mkdir(exist_ok=True)
    total = 0
    for theme in THEMES:
        source = ROOT / f'assets/reading_art/{theme}-117.png'
        target = folder / f'{theme}-117.webp'
        with Image.open(source) as master:
            if master.size != (1536, 1024):
                raise ValueError(f'Unexpected source dimensions: {source}')
            expected = master.convert('RGBA').resize(SIZE, Image.Resampling.LANCZOS)
            if not args.check:
                with tempfile.NamedTemporaryFile(dir=folder, suffix='.webp', delete=False) as temporary:
                    staged = Path(temporary.name)
                try:
                    expected.save(staged, 'WEBP', lossless=True, exact=True, quality=100, method=6,
                                  icc_profile=master.info.get('icc_profile', b''))
                    with Image.open(staged) as encoded:
                        if encoded.size != SIZE or encoded.convert('RGBA').tobytes() != expected.tobytes():
                            raise ValueError(f'Preview pixel mismatch: {theme}')
                    os.replace(staged, target)
                finally:
                    staged.unlink(missing_ok=True)
            with Image.open(target) as decoded:
                assert decoded.size == SIZE
                assert decoded.convert('RGBA').tobytes() == expected.tobytes(), theme
            total += target.stat().st_size
            print(f'{theme}: {target.stat().st_size} bytes; 420x280; verified thumbnail pixels')
    print(f'Total preview bytes: {total}; full PNG/WebP and native resources unchanged')


if __name__ == '__main__':
    main()
