# Optional font catalogue

No font binary is bundled. Users explicitly download, choose or delete each
face; App, shared reader and per-book choices remain independent. Opening
the catalogue does not download preview fonts. Installed previews and selected
faces are loaded lazily, once per face.

| Face | Fixed upstream release / file | Download | Managed file | Notice |
|---|---|---|---|---|
| Source Han Serif CN | Adobe `2.003R`, `SourceHanSerifCN-VF.otf` | 22,613,144 B | same | `OFL-SourceHanSerif.txt` |
| Source Han Sans CN | Adobe `2.005R`, `SourceHanSansCN-VF.otf` | 15,636,088 B | same | `OFL-SourceHanSans.txt` |
| LXGW WenKai GB Screen | `lxgw/LxgwWenKai-Screen`, `v1.530`, `LXGWWenKaiGBScreen.ttf` | 26,456,786 B | same | `OFL-LXGWWenKaiScreen.txt` |
| Zhuque Fangsong | `TrionesType/zhuque`, `v0.212`, technical preview | ZIP 5,743,932 B | `ZhuqueFangsong-Regular.ttf`, 8,824,084 B | `OFL-ZhuqueFangsong.txt` |
| Iansui | `ButTaiwan/iansui`, `v1.020`, `fonts/ttf/Iansui-Regular.ttf` | 9,447,424 B | same | `OFL-Iansui.txt` |

All files are unmodified upstream releases under SIL OFL 1.1. Their original
copyright and license notices are included here and in the app license page.
Iansui uses Taiwan traditional forms and has a smaller character set; missing
glyphs use the normal platform fallback. Zhuque is marked as a font preview.
Font data is streamed to private temporary files and installed only after
length and SFNT validation. Its one ZIP is unpacked off the UI isolate, only
for the exact catalogue entry. Cancellation and failed transfers remove
partial files. The catalogue does not use the app's update Worker or a paid API.

Source URLs and byte counts are fixed in `lib/font_catalog.dart`. The Adobe
fonts use the ISCAS mirror first, then the official fixed tag; other fonts
use the author's fixed GitHub release/tag directly. Retrieval: 2026-10-20.

## Existing Source Han Serif preference

Unmodified Adobe Source Han Serif CN variable subset font, version 2.003.
One variable font supplies the app's Regular (400) and Bold (700) weights.
It is an optional download, not a Flutter application asset.

- Project: https://github.com/adobe-fonts/source-han-serif
- Official file: `release/Variable/OTF/Subset/SourceHanSerifCN-VF.otf`
- Retrieved: 2026-10-19
- License: SIL Open Font License 1.1; full notice in `OFL-SourceHanSerif.txt`.

The app exposes this font as “思源宋体”. Downloading is explicit; users can
delete the private copy or download it again. Offline and not downloaded,
the app uses the platform font while retaining the saved font choice.
The family name and preference ID remain `SourceHanSerifCN` / `sourceHanSerif`.
The font covers the same 30,930 Unicode code points as the former bundled face.

The Serif download uses the public ISCAS Adobe mirror at
https://mirror.iscas.ac.cn/adobe-fonts/source-han-serif/Variable/OTF/Subset/SourceHanSerifCN-VF.otf
and the official immutable `2.003R` GitHub tag as fallback. No account or
reading data is sent; this does not use a paid API or the app's Worker quota.
The full OFL notice remains an application asset. An unchanged test fixture
is under `test/fixtures/fonts/`; neither it nor any OTF is listed in pubspec.
