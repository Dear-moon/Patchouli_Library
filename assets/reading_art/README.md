# Reading artwork

Eight original illustrations generated for this project on 2026-10-28 with the
built-in image-generation tool. The current set pairs three restrained
information-design themes with five ACG character themes. Every statistic,
date, book title, badge and quotation is laid out separately from live data.

| Asset | Theme | Composition |
| --- | --- | --- |
| `archive-117` | 阅读档案 | Cool-white paper book, blue bookmark and precise index rules |
| `shelf-117` | 书架索引 | Mint-and-forest book spines with uncluttered catalog space |
| `editorial-117` | 阅读年表 | Ivory page sequence, gold tabs and a thin binding thread |
| `constellation-117` | 星港夜航 | Silver-haired reader in an ivory orbital-library uniform |
| `signal-117` | 行动档案 | Calm reader in graphite-and-green archive utility wear |
| `score-117` | 青春频率 | Coral cardigan, headphones and a reading-radio composition |
| `ink-117` | 云间书信 | Jade robe, vermilion bookmark ribbon and flat cloud bands |
| `festival-117` | 晴空来信 | Blue-shirt reader by a bright train window, orange tote |

The five character illustrations derive from `assets/branding/app-icon-source.png`:
silver asymmetric hair, a single side braid and the bookmark-shaped clip. The
normal themes use their small illustrations as supporting material; real book
covers and reading data remain the main subject.

The 1536 × 1024 PNGs are retained as source art. The exact, lossless WebP
versions keep the same dimensions; Flutter packages only the eight 117 WebP files
listed in `pubspec.yaml`. The 110 sources remain available as historical material
but are not packaged by the current Flutter registry. Native widgets consume
the current 117 art in each host's appropriate format and focal crops.

Reports, moments, excerpts and home widgets compose the art for their own aspect
ratios. Keep names and excerpts in the ordinary text font: `ReadingSerifDisplay`
covers fixed headings only. Inspect the actual crops and text contrast on narrow
widgets instead of treating a source image as a finished layout.

The complete prompt set and source identity are in [creation-117.json](creation-117.json).
[Arknights](https://ak.hypergryph.com/) informed strong scale contrast, hard color
boundaries and precise indexing; [Zenless Zone Zero](https://zenless.hoyoverse.com/main)
informed character-led poster balance and fresh graphic color. No game artwork,
character, logo or promotional asset is included.
