"""Sync accepted 117 widget art as exact lossless WebP and copy display fonts.

Regeneration requires Pillow and cwebp on PATH; normal Android builds do not.
The PNG masters stay untouched. RemoteViews draws live text over these art-only
resources; these files never contain user statistics or whole cards.
"""
import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
THEMES = ('archive', 'shelf', 'editorial', 'constellation', 'signal', 'score', 'ink', 'festival')


def write_lossless(image, target, encoder):
    """Publish only after every decoded RGBA pixel matches the source image."""
    with tempfile.TemporaryDirectory(prefix='.widget-art-', dir=target.parent) as directory:
        source = Path(directory) / 'source.png'
        output = Path(directory) / 'encoded.webp'
        image.save(source, format='PNG')
        subprocess.run([
            encoder, '-quiet', '-lossless', '-exact', '-m', '6', '-q', '100',
            '-metadata', 'icc', str(source), '-o', str(output),
        ], check=True)
        with Image.open(output) as decoded:
            if (decoded.size != image.size or
                    decoded.convert('RGBA').tobytes() != image.convert('RGBA').tobytes()):
                raise ValueError(f'Lossless pixel verification failed: {target.name}')
        os.replace(output, target)
    # Identical Android resource basenames cannot coexist as PNG and WebP.
    # Remove only the legacy counterpart of this successfully verified output.
    target.with_suffix('.png').unlink(missing_ok=True)
    print(f'{target.relative_to(ROOT)}: {image.width}x{image.height}, '
          f'{target.stat().st_size} bytes, exact decoded pixels')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--themes', nargs='+', choices=THEMES, default=list(THEMES))
    parser.add_argument('--fonts-only', action='store_true',
                        help='Refresh display fonts without re-encoding artwork.')
    args = parser.parse_args()
    encoder = shutil.which('cwebp')
    if not args.fonts_only and encoder is None:
        parser.error('cwebp is required to regenerate lossless widget artwork')

    resources = ROOT / 'android/app/src/main/res'
    art = resources / 'drawable-nodpi'
    art.mkdir(exist_ok=True)
    (resources / 'font').mkdir(exist_ok=True)
    for theme in [] if args.fonts_only else args.themes:
        # Native narrow panels use the right-hand subject in the accepted master.
        # Cropping changes framing only: no resize, recolor or quality reduction.
        source = ROOT / f'assets/reading_art/{theme}-117.png'
        with Image.open(source) as image:
            if image.size != (1536, 1024):
                raise ValueError(f'Unexpected accepted artwork dimensions: {source}')
            with image.crop((640, 0, 1536, 1024)) as cropped:
                write_lossless(cropped, art / f'reading_widget_art_{theme}_117.webp', encoder)

    for source_name, resource_name in (
        ('ReadingDisplay-Bold.ttf', 'reading_widget_display_bold.ttf'),
        ('ReadingDisplay-Medium.ttf', 'reading_widget_display_medium.ttf'),
        ('ReadingSerifDisplay-Bold.ttf', 'reading_widget_serif_bold.ttf'),
    ):
        shutil.copy2(ROOT / 'assets/fonts' / source_name, resources / 'font' / resource_name)
    print('Copied display fonts; PNG masters unchanged.' if args.fonts_only else
          'Synced exact lossless WebP artwork and display fonts; PNG masters unchanged.')


if __name__ == '__main__':
    main()
