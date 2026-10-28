# Optional font catalogue

No full reading font is bundled. Users explicitly download, choose or delete each
reading face; App, shared reader and per-book choices remain independent. Opening
the catalogue does not download preview fonts. Installed previews and selected
faces are loaded lazily, once per face.

| Face | Fixed upstream release / file | Download | Managed file | Notice |
|---|---|---|---|---|
| Source Han Serif CN | Adobe `2.003R`, `SourceHanSerifCN-VF.otf` | 22,613,144 B | same | `OFL-SourceHanSerif.txt` |
| Source Han Sans CN | Adobe `2.005R`, `SourceHanSansCN-VF.otf` | 15,636,088 B | same | `OFL-SourceHanSans.txt` |
| LXGW WenKai GB Screen | `lxgw/LxgwWenKai-Screen`, `v1.530`, `LXGWWenKaiGBScreen.ttf` | 26,456,786 B | same | `OFL-LXGWWenKaiScreen.txt` |
| Zhuque Fangsong | `TrionesType/zhuque`, `v0.212`, technical preview | ZIP 5,743,932 B | `ZhuqueFangsong-Regular.ttf`, 8,824,084 B | `OFL-ZhuqueFangsong.txt` |
| Iansui | `ButTaiwan/iansui`, `v1.020`, `fonts/ttf/Iansui-Regular.ttf` | 9,447,424 B | same | `OFL-Iansui.txt` |
| LXGW ZhenKai Slab GB | `lxgw/LxgwZhenKai`, `v0.827`, `LXGWZhenKaiSlabGB-Regular.ttf` | 17,453,376 B | same | `OFL-LXGWZhenKai.txt` |
| LXGW Marker Gothic | `lxgw/LxgwMarkerGothic`, `v1.004` | ZIP 3,703,389 B | `LxgwMarkerGothic-v1.004/fonts/ttf/LXGWMarkerGothic-Regular.ttf`, 3,190,368 B | `OFL-LXGWMarkerGothic.txt` |
| Xiaolai | `lxgw/kose-font`, `v3.126`, `Xiaolai-Regular.ttf` | 22,220,806 B | same | `OFL-Xiaolai.txt` |
| Yozai Medium | `lxgw/yozai-font`, `v0.868`, `Yozai-Medium.ttf` | 15,238,394 B | same | `OFL-Yozai.txt` |
| Source Han Serif TW | Adobe `2.003R`, `SourceHanSerifTW-VF.otf` | 15,175,972 B | same | `OFL-SourceHanSerif.txt` |
| Source Han Sans TW | Adobe `2.005R`, `SourceHanSansTW-VF.otf` | 10,495,320 B | same | `OFL-SourceHanSans.txt` |
| LXGW WenKai TC | `lxgw/LxgwWenkaiTC`, `v1.530`, `LXGWWenKaiTC-Regular.ttf` | 15,341,148 B | same | `OFL-LXGWWenKaiTC.txt` |
| jf open Huninn | `justfont/open-huninn-font`, `v2.1`, `jf-openhuninn-2.1.ttf` | 4,911,464 B | same | `OFL-OpenHuninn.txt` |

All files are unmodified upstream releases under SIL OFL 1.1. Their original
copyright and license notices are included here and in the app license page.
The Source Han TW faces and Iansui use Taiwan traditional forms; LXGW WenKai
TC uses inherited traditional forms. Huninn covers Taiwan's common characters
rather than every CJK character. Traditional-first faces use traditional
preview text. Missing glyphs use the normal platform fallback. Zhuque is marked
as a font preview.
Font data is streamed to private temporary files and installed only after
length and SFNT validation. ZIP files are unpacked off the UI isolate, only
for the exact catalogue entry. Cancellation and failed transfers remove
partial files. The catalogue does not use the app's update Worker or a paid API.

Source URLs and byte counts are fixed in `lib/font_catalog.dart`. The Adobe
fonts use the ISCAS mirror first, then the official fixed tag; other fonts
use the author's fixed GitHub release/tag directly. Catalogue expanded and new
downloads checked: 2026-10-27. License texts are taken unchanged from each fixed
tag (`OFL.txt`, or `LICENSE` for Huninn); Source Han CN and TW share Adobe's
license. The optional catalogue adds only these small notices to application assets.

## Reading-image display faces

The report, milestone and home-widget visual system has two small bundled display
faces, independent of reading-font preferences:

- `ReadingDisplay`: unmodified Barlow Condensed Medium and Bold for numerals and
  Latin display labels, from `google/fonts/ofl/barlowcondensed` (SIL OFL 1.1).
- `ReadingSerifDisplay`: Noto Serif SC at weight 700, subset to the fixed Chinese
  headings in `reading-serif-display-glyphs.txt` and renamed Reading Serif Display.
  This is not a general reading font; arbitrary book titles and quotations keep
  the existing platform/installed-font path.

Sources: https://github.com/google/fonts/tree/main/ofl/barlowcondensed and
https://github.com/google/fonts/tree/main/ofl/notoserifsc (retrieved 2026-10-28).
Original copyright/OFL notices are included and registered on the app license page.
Rebuild the heading subset with `tools/subset_reading_display_font.py`; full upstream
Noto source is not an application asset. Artwork is separately packaged as WebP;
its high-resolution PNG sources are not listed in `pubspec.yaml`.

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
