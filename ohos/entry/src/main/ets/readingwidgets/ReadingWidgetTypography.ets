import text from '@ohos.graphics.text';

const systemFont: string = 'HarmonyOS Sans';
const numberFont: string = 'ReadingWidgetDisplayBold110';
const labelFont: string = 'ReadingWidgetDisplayMedium110';
const titleFont: string = 'ReadingWidgetSerifDisplayBold110';
let numberLoaded: boolean = false;
let labelLoaded: boolean = false;
let titleLoaded: boolean = false;

// These are fixed product headings, never a book title, author or user note.
// The resource contract checks every character against the packaged subset.
const fixedTitles: string[] = [
  '年度档案', '藏书展览', '纸间叙事', '夜航星图', '旷野信号', '余音书简', '墨间长卷', '晴日切片',
  '阅读档案', '阅读夜航', '阅读信号', '阅读书简', '阅读长卷', '阅读切片',
  '七日档案', '七日节律', '七日\n节律', '七日夜航', '七日阅读信号', '七日书简',
  '七日墨间', '七日切片', '七日\n切片', '阅读纪念', '连续有效阅读', '下一次阅读',
  '连续阅读', '最近读完', '读到此刻',
  '阅读\n留在此刻'
];

function load(collection: text.FontCollection, family: string, resource: Resource): boolean {
  try {
    if (typeof collection.loadFontSyncWithCheck === 'function') {
      collection.loadFontSyncWithCheck(family, resource);
    } else {
      collection.loadFontSync(family, resource);
    }
    return true;
  } catch (_) { return false; }
}

/** Call from the Form component's aboutToAppear, not the UIAbility process.
 * API 22 introduced the Form-local collection. Every Form of this application
 * shares it, so do not unload these fonts when one Form disappears.
 * https://github.com/openharmony/docs/blob/master/en/application-dev/form/arkts-ui-widget-load-custom-font.md
 */
export function initializeReadingWidgetFonts(): void {
  try {
    // Older supported systems retain actual system text; never call the global
    // font registry or return a custom family which was not loaded in this host.
    if (typeof text.FontCollection.getLocalInstance !== 'function') { return; }
    const collection: text.FontCollection = text.FontCollection.getLocalInstance();
    if (!numberLoaded) { numberLoaded = load(collection, numberFont, $rawfile('reading_display_bold_110.ttf')); }
    if (!labelLoaded) { labelLoaded = load(collection, labelFont, $rawfile('reading_display_medium_110.ttf')); }
    if (!titleLoaded) { titleLoaded = load(collection, titleFont, $rawfile('reading_serif_display_bold_110.ttf')); }
  } catch (_) {}
}

export function readingWidgetNumberFont(): string {
  return numberLoaded ? numberFont + ',' + systemFont : systemFont;
}

export function readingWidgetLabelFont(): string {
  return labelLoaded ? labelFont + ',' + systemFont : systemFont;
}

/** Only allow known fixed headings through the limited Chinese serif subset. */
export function readingWidgetTitleFont(value: string): string {
  return titleLoaded && fixedTitles.includes(value) ? titleFont + ',' + systemFont : systemFont;
}

/** Dynamic titles/authors/notes must use the full system character coverage. */
export function readingWidgetDynamicTextFont(): string { return systemFont; }
