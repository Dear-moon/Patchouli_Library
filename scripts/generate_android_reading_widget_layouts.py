"""Generate native 117 identities and the live 119 reading activity calendars.

Only static artwork and fixed display typography are shared with Flutter.
Statistics, dates, book details and accessibility labels stay live TextViews.
"""
import argparse
from pathlib import Path
from xml.etree.ElementTree import Element, SubElement, indent, tostring

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / 'android/app/src/main/res'
THEMES = ('archive', 'shelf', 'editorial', 'constellation', 'signal', 'score', 'ink', 'festival')
INK, WHITE = '#18232C', '#E9EDF7'
PALETTES = {
    'archive': ('F7F8F6', '18232C', '66727B', '2E769E', 'C8D9E0'),
    'shelf': ('EEF4F0', '183A30', '5C6C63', '3E7361', 'BED3C7'),
    'editorial': ('FAF6E9', '353126', '6F6854', '9B8141', 'DAD0AD'),
    'constellation': ('101629', 'E9EDF7', 'A5B0CD', 'B4A3F5', '334267'),
    'signal': ('F0F1E8', '1C292A', '5F6F69', '4F7E6C', 'C8D098'),
    'score': ('FFF4F3', '352F44', '786275', 'C84D76', 'F0BACD'),
    'ink': ('F6F4E9', '233E3B', '607167', 'A4473A', 'B8D1C7'),
    'festival': ('F2F8FB', '1B3D54', '566F7D', 'E47843', 'AECEDF'),
}
LABELS = dict(zip(THEMES, ('阅读档案', '书架索引', '阅读年表', '星港夜航', '行动档案', '青春频率', '云间书信', '晴空来信')))

def tokens(theme):
    return ['#' + color for color in PALETTES[theme]]

def node(tag, parent=None, **attrs):
    element = Element(tag) if parent is None else SubElement(parent, tag)
    for key, value in attrs.items():
        element.set('android:' + key, str(value))
    return element

def save(element, path):
    element.set('xmlns:android', 'http://schemas.android.com/apk/res/android')
    indent(element, space='    ')
    path.write_text('<?xml version="1.0" encoding="utf-8"?>\n' + tostring(element, encoding='unicode') + '\n')

def linear(parent, orientation='vertical', width='match_parent', height='wrap_content', **attrs):
    return node('LinearLayout', parent, layout_width=width, layout_height=height, orientation=orientation, **attrs)

def frame(parent=None, width='match_parent', height='match_parent', **attrs):
    return node('FrameLayout', parent, layout_width=width, layout_height=height, **attrs)

def text(parent, key, value, size=11, color=INK, width='match_parent', height='wrap_content', font='sans-serif', **attrs):
    defaults = dict(layout_width=width, layout_height=height, text=value, textSize=f'{size}sp', textColor=color,
                    includeFontPadding='false', fontFamily=font, maxLines=1, ellipsize='end')
    if key:
        defaults['id'] = '@+id/widget_' + key
    defaults.update(attrs)
    styles = {
        '@font/reading_widget_display_bold': 'ReadingWidgetDisplayBold',
        '@font/reading_widget_display_medium': 'ReadingWidgetDisplayMedium',
        '@font/reading_widget_serif_bold': 'ReadingWidgetSerifBold',
    }
    if font in styles:
        defaults.pop('fontFamily')
    view = node('TextView', parent, **defaults)
    if font in styles:
        view.set('style', '@style/' + styles[font])
    return view

def art(parent, theme, variant='', **attrs):
    suffix = '_' + variant if variant else ''
    defaults = dict(layout_width='match_parent', layout_height='match_parent', src=f'@drawable/reading_widget_art_{theme}{suffix}_117',
                    scaleType='centerCrop', importantForAccessibility='no')
    defaults.update(attrs)
    return node('ImageView', parent, **defaults)

def fill(parent, color, **attrs):
    defaults = dict(layout_width='match_parent', layout_height='match_parent', background=color, importantForAccessibility='no')
    defaults.update(attrs)
    return node('ImageView', parent, **defaults)

def root(theme):
    return frame(id='@+id/reading_widget_root', background='@drawable/reading_widget_surface_' + theme, clipToOutline='true')

def numeral(parent, size=58, color=WHITE, height='0dp', weight=1, align='start', unit='天'):
    width = 'wrap_content' if parent.get('android:orientation') == 'horizontal' else 'match_parent'
    row = linear(parent, 'horizontal', width=width, height=height, gravity='bottom|' + align, **({'layout_weight': weight} if weight else {}))
    text(row, 'value', '—', size, color, width='wrap_content', height='match_parent', gravity='bottom',
         font='@font/reading_widget_display_bold', maxLines=1)
    text(row, 'unit', unit, 13, color, width='wrap_content', layout_marginStart='6dp', layout_marginBottom='8dp')
    return row

def cover(parent, width='40dp', height='52dp'):
    box = frame(parent, width=width, height=height, id='@+id/widget_cover_container', visibility='gone', layout_marginStart='12dp')
    node('ImageView', box, id='@+id/widget_cover', layout_width='match_parent', layout_height='match_parent', scaleType='centerCrop', contentDescription='最近读到书尾的书籍封面')
    text(box, 'bookmark', '', visibility='gone')
    return box

def heading(parent, color=INK, label='连续阅读', **attrs):
    return text(parent, 'heading', label, 11, color, **attrs)

def detail(parent, color=INK, label='近7日 — 分钟', **attrs):
    return text(parent, 'detail', label, 11, color, **attrs)

def caption(parent, color='#676A62', **attrs):
    return text(parent, 'caption', '截至 —', 11, color, **attrs)

def bookline(parent, color=INK, size=17, lines=2, **attrs):
    return text(parent, 'detail', '把时间留给书页', size, color, maxLines=lines, lineSpacingExtra='2dp', **attrs)

def chart(parent, theme, height='36dp', color=None, **attrs):
    area = linear(parent, 'horizontal', height=height, gravity='bottom', **attrs)
    for index in range(7):
        col = linear(area, width='0dp', height='match_parent', layout_weight=1, gravity='bottom|center_horizontal')
        barbox = frame(col, height='0dp', layout_weight=1)
        bar = node('ProgressBar', barbox, id=f'@+id/widget_bar_{index}', layout_width='19dp', layout_height='5dp',
                   rotation=-90, layout_gravity='center', progressDrawable=f'@drawable/reading_widget_progress_{theme}',
                   max=100, progress=0, indeterminate='false')
        bar.set('style', '?android:attr/progressBarStyleHorizontal')
        text(col, f'day_{index}', '—', 10, color or tokens(theme)[2], gravity='center', layout_marginTop='2dp')
    return area

def heatmap(parent, theme, family):
    muted = tokens(theme)[2]
    weeks = {'small': 7, 'medium': 13, 'large': 26}[family]
    row = linear(parent, 'horizontal', height='15dp', gravity='center_vertical')
    text(row, 'heatmap_heading', f'近{weeks}周', 10, muted, width='0dp', layout_weight=1)
    text(row, 'as_of', '截至 —', 10, muted, width='wrap_content', visibility='visible' if family == 'large' else 'gone')
    node('ImageView', parent, id='@+id/widget_heatmap', layout_width='match_parent',
         layout_height='49dp' if family == 'large' else '0dp', scaleType='fitCenter', contentDescription=f'近{weeks}周阅读热力图',
         **({} if family == 'large' else {'layout_weight': 1}))

def activity_layout(theme, family):
    bg, fg, muted, accent, secondary = tokens(theme)
    normal = theme in THEMES[:3]
    surface = root(theme)
    col = linear(surface, height='match_parent', padding='10dp')
    if family == 'small':
        top = frame(col, height='50dp')
        if not normal:
            art(top, theme, layout_width='50dp', layout_height='44dp', layout_gravity='end')
        else:
            art(top, theme, layout_width='36dp', layout_height='34dp', layout_gravity='center_vertical|end')
        data = linear(top, width='94dp')
        heading(data, fg)
        numeral(data, 28, fg, height='34dp', weight=0)
        detail(col, fg, label='有效阅读 — 分钟', layout_marginTop='1dp')
        caption(col, muted, visibility='gone')
        text(col, 'totals', '', visibility='gone')
        heatmap(col, theme, family)
    elif family == 'medium':
        top = linear(col, 'horizontal', height='65dp')
        weekly = theme in ('shelf', 'editorial', 'signal', 'score')
        data = linear(top, width='100dp', height='match_parent')
        heading(data, fg, label='近7日阅读' if weekly else '连续阅读')
        numeral(data, 28, fg, height='34dp', weight=0, unit='分钟' if weekly else '天')
        detail(data, muted, label='连续 — 天', textSize='10sp')
        rhythm = linear(top, width='0dp', height='match_parent', layout_weight=1, paddingStart='8dp', paddingEnd='8dp' if not normal else '0dp')
        text(rhythm, None, '近7日节律', 10, muted)
        chart(rhythm, theme, height='30dp', color=muted)
        caption(rhythm, muted, textSize='10sp', gravity='end', layout_marginTop='1dp')
        text(col, 'totals', '', visibility='gone')
        heatmap(col, theme, family)
    else:
        header = linear(col, 'horizontal', height='16dp', gravity='center_vertical')
        heading(header, muted, label='阅读纪念', width='0dp', layout_weight=1)
        text(header, None, LABELS[theme], 10, accent, width='wrap_content')
        fill(col, secondary, layout_height='1dp', layout_marginTop='5dp')
        hero = frame(col, height='0dp', layout_weight=1, layout_marginTop='3dp')
        if not normal:
            art(hero, theme, layout_width='104dp', layout_gravity='end', scaleType='fitCenter')
        else:
            art(hero, theme, layout_width='82dp', layout_height='60dp', layout_gravity='center_vertical|end')
        text(hero, 'value', '每一页，\n都算数。', 20, fg, font='@font/reading_widget_serif_bold' if theme in ('editorial', 'ink') else 'sans-serif',
             maxLines=2, width='160dp', layout_gravity='center_vertical', lineSpacingExtra='2dp', background=bg)
        row = linear(col, 'horizontal', height='48dp', gravity='center_vertical', layout_marginTop='3dp')
        bookline(row, fg, 15, 2, width='0dp', layout_weight=1)
        cover(row, '36dp', '48dp')
        caption(col, muted, textSize='10sp', maxLines=2, height='30dp', layout_marginTop='2dp')
        text(col, 'totals', '连续 — 天 · 今天 — 分钟 · 近7日 — 分钟', 10, muted, maxLines=2, height='28dp')
        heatmap(col, theme, family)
    return surface

def drawables(theme):
    bg, fg, muted, accent, secondary = tokens(theme)
    shape = node('shape', shape='rectangle')
    node('solid', shape, color=bg)
    node('corners', shape, radius='20dp')
    save(shape, RES / f'drawable/reading_widget_surface_{theme}.xml')
    progress = node('layer-list')
    item = node('item', progress, id='@android:id/background')
    node('solid', node('shape', item), color=secondary)
    item = node('item', progress, id='@android:id/progress')
    node('solid', node('shape', node('clip', item)), color=accent)
    save(progress, RES / f'drawable/reading_widget_progress_{theme}.xml')

def typography():
    # Native downloadable/font resources arrived in API 26. Earlier supported
    # hosts keep the same layout using platform condensed/serif typefaces.
    for qualifier, embedded in [('values', False), ('values-v26', True)]:
        folder = RES / qualifier
        folder.mkdir(exist_ok=True)
        resources = Element('resources')
        for name, resource, fallback, weight in [
            ('ReadingWidgetDisplayBold', 'reading_widget_display_bold', 'sans-serif-condensed', 'bold'),
            ('ReadingWidgetDisplayMedium', 'reading_widget_display_medium', 'sans-serif-condensed', 'normal'),
            ('ReadingWidgetSerifBold', 'reading_widget_serif_bold', 'serif', 'bold'),
        ]:
            style = SubElement(resources, 'style', {'name': name})
            SubElement(style, 'item', {'name': 'android:fontFamily'}).text = '@font/' + resource if embedded else fallback
            SubElement(style, 'item', {'name': 'android:textStyle'}).text = weight
        save(resources, folder / 'reading_widget_typography.xml')

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--themes', nargs='+', choices=THEMES, default=list(THEMES))
args = parser.parse_args()
typography()
for theme in args.themes:
    drawables(theme)
    for family in ('small', 'medium', 'large'):
        layout = activity_layout(theme, family)
        save(layout, RES / f'layout/reading_widget_{theme}_{family}.xml')
        if theme == 'archive':
            save(layout, RES / f'layout/reading_widget_{family}.xml')
print('Native 117 artwork identities and live 119 activity layouts written.')
