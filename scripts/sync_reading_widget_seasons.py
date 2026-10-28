#!/usr/bin/env python3
"""Build widget-sized derivatives of the four approved report illustrations."""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
for season in ('spring', 'summer', 'autumn', 'winter'):
    source = ROOT / f'assets/report/char_season_{season}.webp'
    with Image.open(source) as image:
        image = image.convert('RGB')
        image.thumbnail((720, 405), Image.Resampling.LANCZOS)
        for folder in ('android/app/src/main/res/drawable-nodpi', 'ohos/entry/src/main/resources/base/media'):
            image.save(ROOT / folder / f'widget_season_{season}.webp', format='WEBP', quality=90, method=6)
        asset = ROOT / f'ios/ReadingWidgets/Assets.xcassets/WidgetSeason_{season}.imageset'
        asset.mkdir(exist_ok=True)
        image.save(asset / 'art.png', optimize=True)
        (asset / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'art.png', 'idiom': 'universal'}],
            'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
    print(season)
