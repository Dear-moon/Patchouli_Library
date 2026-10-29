// Native widgets consume measured ledger values, never the legacy timer.
// Reconstruct the payload here so cached data is subject to the same privacy
// boundary as a fresh MethodChannel publication.
export interface ReadingWidgetDay {
  date: string;
  verifiedSeconds: number | null;
}

export interface ReadingWidgetHeatmap {
  startDate: string;
  weekStart: number;
  verifiedSeconds: (number | null)[];
}

export interface ReadingWidgetCompletion {
  completedAt: string;
  finished: boolean;
  bookId: number | null;
  title: string | null;
  author: string | null;
  coverPath: string | null;
}

export interface ReadingWidgetSnapshot {
  version: number;
  generatedAt: string;
  localDay: string;
  qualificationSeconds: number;
  verifiedTotalSeconds: number | null;
  verifiedTodaySeconds: number | null;
  qualifiedStreakDays: number | null;
  week: ReadingWidgetDay[];
  heatmap?: ReadingWidgetHeatmap;
  latestCompletion: ReadingWidgetCompletion | null;
  palette: string;
  themeId: string;
  layoutId?: string;
  skinId?: string;
  dailyGoalMinutes?: number;
  desktopImages?: Record<string, string>;
  showBookDetails: boolean;
}

const maximumPayloadBytes: number = 64 * 1024;

export function validReadingGoal(value?: number): number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 1 && value <= 1440 ? value : 0;
}
export function readingGoalCaption(snapshot: ReadingWidgetSnapshot): string {
  const goal = validReadingGoal(snapshot.dailyGoalMinutes);
  if (goal === 0) { return ''; }
  const seconds = snapshot.verifiedTodaySeconds;
  if (seconds === null) { return '每日目标 ' + goal + ' 分钟'; }
  return seconds >= goal * 60 ? '今日目标已达成' : '目标 ' + goal + ' 分 · 还差 ' + Math.ceil((goal * 60 - seconds) / 60) + ' 分';
}

function invalidSnapshot(): Error {
  return new Error('Invalid reading widget snapshot');
}

function withinPayloadLimit(text: string): boolean {
  if (text.length > maximumPayloadBytes) { return false; }
  let bytes: number = 0;
  for (let i: number = 0; i < text.length; i++) {
    const unit: number = text.charCodeAt(i);
    if (unit < 0x80) { bytes++; }
    else if (unit < 0x800) { bytes += 2; }
    else if (unit >= 0xd800 && unit <= 0xdbff && i + 1 < text.length &&
      text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) {
      bytes += 4;
      i++;
    } else { bytes += 3; }
    if (bytes > maximumPayloadBytes) { return false; }
  }
  return true;
}

function validDay(day: string): boolean {
  if (typeof day !== 'string' || !/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(day)) { return false; }
  const year: number = Number(day.substring(0, 4));
  const month: number = Number(day.substring(5, 7));
  const date: number = Number(day.substring(8, 10));
  if (year < 1 || month < 1 || month > 12 || date < 1) { return false; }
  const leap: boolean = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const lengths: number[] = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return date <= lengths[month - 1];
}

function validTimestamp(value: string): boolean {
  if (typeof value !== 'string' || value.length > 40 ||
    !/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,6})?(?:Z|[+-][0-9]{2}:[0-9]{2})?$/.test(value) ||
    !validDay(value.substring(0, 10)) || Number(value.substring(11, 13)) > 23 ||
    Number(value.substring(14, 16)) > 59 || Number(value.substring(17, 19)) > 59) { return false; }
  return Number.isFinite(Date.parse(value));
}

function measured(value: number | null): boolean {
  return value === null || typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}

function boundedText(value: string | null, maximum: number, path: boolean = false): boolean {
  return value === null || typeof value === 'string' && value.length <= maximum &&
    !(path ? /[\x00-\x1f\x7f]/ : /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/).test(value);
}

function utcDay(date: Date): string {
  return date.getUTCFullYear().toString().padStart(4, '0') + '-' +
    (date.getUTCMonth() + 1).toString().padStart(2, '0') + '-' +
    date.getUTCDate().toString().padStart(2, '0');
}

function weekDates(localDay: string): string[] {
  const date: Date = new Date(localDay + 'T00:00:00.000Z');
  date.setUTCDate(date.getUTCDate() - 6);
  const days: string[] = [];
  for (let i: number = 0; i < 7; i++) {
    days.push(utcDay(date));
    date.setUTCDate(date.getUTCDate() + 1);
  }
  return days;
}

/** UTC calendar components preserve the supplied local date across DST changes. */
export function widgetHeatmapDates(localDay: string): string[] {
  if (!validDay(localDay)) { throw invalidSnapshot(); }
  const date: Date = new Date(localDay + 'T00:00:00.000Z');
  date.setUTCDate(date.getUTCDate() - (date.getUTCDay() + 6) % 7 - 25 * 7);
  const days: string[] = [];
  for (let index: number = 0; index < 182; index++) {
    days.push(utcDay(date));
    date.setUTCDate(date.getUTCDate() + 1);
  }
  return days;
}

/** Malformed additive data never discards usable v1 totals or invents history. */
export function widgetHeatmap(localDay: string, week: ReadingWidgetDay[],
  source?: ReadingWidgetHeatmap): ReadingWidgetHeatmap {
  const dates = widgetHeatmapDates(localDay);
  let valid = source !== undefined && source !== null && typeof source === 'object' &&
    !Array.isArray(source) && source.startDate === dates[0] && source.weekStart === 1 &&
    Array.isArray(source.verifiedSeconds) && source.verifiedSeconds.length === 182;
  if (valid && source !== undefined) {
    for (let index: number = 0; index < 182; index++) {
      const value = source.verifiedSeconds[index];
      if (!measured(value) || dates[index] > localDay && value !== null) { valid = false; break; }
    }
  }
  const values: (number | null)[] = [];
  for (let index: number = 0; index < 182; index++) {
    if (valid && source !== undefined) { values.push(source.verifiedSeconds[index]); }
    else {
      const explicit = week.find((day: ReadingWidgetDay): boolean => day.date === dates[index]);
      values.push(dates[index] > localDay ? null : explicit?.verifiedSeconds ?? null);
    }
  }
  return { startDate: dates[0], weekStart: 1, verifiedSeconds: values };
}

export function widgetHeatLevel(seconds: number | null): number | null {
  if (!measured(seconds)) { throw invalidSnapshot(); }
  if (seconds === null) { return null; }
  return seconds === 0 ? 0 : seconds < 900 ? 1 : seconds < 1800 ? 2 : seconds < 3600 ? 3 : 4;
}

function compatibleTheme(value: string | undefined, palette: string): string {
  if (value === undefined) { return palette === 'night' ? 'constellation' : 'editorial'; }
  if (typeof value !== 'string' || value.length > 64) { throw invalidSnapshot(); }
  switch (value) {
    case 'paper':
    case 'cream': return 'editorial';
    case 'night': return 'constellation';
    case 'archive':
    case 'shelf':
    case 'editorial':
    case 'constellation':
    case 'signal':
    case 'score':
    case 'ink':
    case 'festival': return value;
    default: return 'archive';
  }
}

export function parseReadingWidgetSnapshot(json: string): ReadingWidgetSnapshot {
  if (typeof json !== 'string' || !withinPayloadLimit(json)) { throw invalidSnapshot(); }
  let source: ReadingWidgetSnapshot;
  try { source = JSON.parse(json) as ReadingWidgetSnapshot; }
  catch (_) { throw invalidSnapshot(); }
  if (source === null || typeof source !== 'object' || Array.isArray(source) ||
    source.version !== 1 || source.qualificationSeconds !== 300 ||
    !validTimestamp(source.generatedAt) || !validDay(source.localDay) ||
    !measured(source.verifiedTotalSeconds) || !measured(source.verifiedTodaySeconds) ||
    !measured(source.qualifiedStreakDays) || typeof source.showBookDetails !== 'boolean' ||
    (source.palette !== 'cream' && source.palette !== 'night') ||
    !Array.isArray(source.week) || source.week.length !== 7) { throw invalidSnapshot(); }
  const expected: string[] = weekDates(source.localDay);
  const week: ReadingWidgetDay[] = [];
  for (let i: number = 0; i < 7; i++) {
    const day: ReadingWidgetDay = source.week[i];
    if (day === null || typeof day !== 'object' || Array.isArray(day) ||
      !validDay(day.date) || day.date !== expected[i] || !measured(day.verifiedSeconds)) { throw invalidSnapshot(); }
    week.push({ date: day.date, verifiedSeconds: day.verifiedSeconds });
  }
  let completion: ReadingWidgetCompletion | null = null;
  if (source.latestCompletion !== null) {
    const record: ReadingWidgetCompletion = source.latestCompletion;
    if (record === undefined || typeof record !== 'object' || Array.isArray(record) ||
      !validTimestamp(record.completedAt) ||
      (record.finished !== undefined && typeof record.finished !== 'boolean') ||
      !measured(record.bookId) || !boundedText(record.title, 2048) ||
      !boundedText(record.author, 1024) || !boundedText(record.coverPath, 4096, true)) { throw invalidSnapshot(); }
    completion = {
      completedAt: record.completedAt,
      finished: record.finished === true,
      bookId: source.showBookDetails ? record.bookId : null,
      title: source.showBookDetails ? record.title : null,
      author: source.showBookDetails ? record.author : null,
      coverPath: source.showBookDetails ? record.coverPath : null
    };
  }
  const desktopImages: Record<string, string> = {};
  if (source.desktopImages !== undefined && source.desktopImages !== null) {
    for (const size of ['small', 'medium', 'large']) {
      const path = source.desktopImages[size];
      if (typeof path !== 'string' || !boundedText(path, 4096, true)) { throw invalidSnapshot(); }
      desktopImages[size] = path;
    }
  }
  return {
    version: 1,
    generatedAt: source.generatedAt,
    localDay: source.localDay,
    qualificationSeconds: 300,
    verifiedTotalSeconds: source.verifiedTotalSeconds,
    verifiedTodaySeconds: source.verifiedTodaySeconds,
    qualifiedStreakDays: source.qualifiedStreakDays,
    week: week,
    heatmap: widgetHeatmap(source.localDay, week, source.heatmap),
    latestCompletion: completion,
    palette: source.palette,
    themeId: compatibleTheme(source.themeId, source.palette),
    layoutId: ['focus', 'week', 'calendar', 'memory'].includes(source.layoutId ?? '') ? source.layoutId : 'classic',
    skinId: ['seasons', 'archive', 'night', 'film', 'paper'].includes(source.skinId ?? '') ? source.skinId : 'original',
    dailyGoalMinutes: validReadingGoal(source.dailyGoalMinutes),
    desktopImages: Object.keys(desktopImages).length === 3 ? desktopImages : undefined,
    showBookDetails: source.showBookDetails
  };
}

export function widgetLocalDay(now: Date): string {
  if (!Number.isFinite(now.getTime()) || now.getFullYear() < 1 || now.getFullYear() > 9999) { throw invalidSnapshot(); }
  return now.getFullYear().toString().padStart(4, '0') + '-' +
    (now.getMonth() + 1).toString().padStart(2, '0') + '-' +
    now.getDate().toString().padStart(2, '0');
}

export function blankReadingWidgetSnapshot(now: Date): ReadingWidgetSnapshot {
  const localDay: string = widgetLocalDay(now);
  const week: ReadingWidgetDay[] = weekDates(localDay).map((date: string): ReadingWidgetDay => {
    return { date: date, verifiedSeconds: null };
  });
  return {
    version: 1,
    generatedAt: now.toISOString(),
    localDay: localDay,
    qualificationSeconds: 300,
    verifiedTotalSeconds: null,
    verifiedTodaySeconds: null,
    qualifiedStreakDays: null,
    week: week,
    heatmap: widgetHeatmap(localDay, week),
    latestCompletion: null,
    palette: 'cream',
    themeId: 'archive',
    layoutId: 'classic',
    skinId: 'original',
    dailyGoalMinutes: 0,
    desktopImages: undefined,
    showBookDetails: false
  };
}

export function widgetMinutes(value: number | null): string {
  if (!measured(value)) { throw invalidSnapshot(); }
  if (value === null) { return '—'; }
  return value > 0 && value < 60 ? '<1' : Math.floor(value / 60).toString();
}

export function widgetDateStamp(day: string): string {
  if (!validDay(day)) { throw invalidSnapshot(); }
  return day.substring(5, 7) + '.' + day.substring(8, 10);
}
