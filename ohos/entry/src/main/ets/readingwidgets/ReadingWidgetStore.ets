import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import formBindingData from '@ohos.app.form.formBindingData';
import formProvider from '@ohos.app.form.formProvider';
import hilog from '@ohos.hilog';
import { ReadingWidgetSnapshot, blankReadingWidgetSnapshot, parseReadingWidgetSnapshot,
  widgetDateStamp, widgetMinutes, validReadingGoal, readingGoalCaption, widgetLocalDay } from './ReadingWidgetSnapshot';
import { readingWidgetWeekSummary, readingWidgetHeatColumns, ReadingWidgetHeatColumn } from './ReadingWidgetPresentation';

interface RegisteredReadingForm { id: string; dimension: number; width?: number; height?: number; cardId?: string; quoteId?: string; }
interface ReadingCardQuote { id: string; text: string; source: string; }
interface ReadingCard { id: string; name: string; design: string; skin: string; appearance: string; showBookDetails: boolean; hasRecent: boolean; localDay: string; images: Record<string, string>; quotes: ReadingCardQuote[]; sources?: Record<string, string>; }
interface ReadingCardBinding { dimension: number; cardWidth: number; cardHeight: number; layoutId: string; skinId: string; desktopImage: string; desktopDarkImage: string; followSystemCard: boolean; staleImage: boolean; dayStamp: string; quoteText: string; quoteSource: string; quoteCount: number; hasQuoteNext: boolean; hasRecent: boolean; cardInk: string; formImages: Record<string, number>; }
export interface ReadingWidgetBounds { width: number; height: number; }
export interface ReadingWidgetBar { date: string; label: string; minutes: string; ratio: number; measured: boolean; }
export interface ReadingWidgetBinding {
  dimension: number;
  cardWidth: number;
  cardHeight: number;
  themeId: string;
  layoutId: string;
  skinId: string;
  season: number;
  goalCaption: string;
  goalRatio: number;
  hasGoalProgress: boolean;
  palette: string;
  dayStamp: string;
  streak: string;
  minutes: string;
  totalMinutes: string;
  weekMinutes: string;
  weekLabel: string;
  week: ReadingWidgetBar[];
  heatColumns: ReadingWidgetHeatColumn[];
  heatWeeks: number;
  hasMoment: boolean;
  momentHeading: string;
  momentDate: string;
  bookTitle: string;
  bookAuthor: string;
  coverImage: string;
  desktopImage: string;
  staleImage: boolean;
  showBookDetails: boolean;
  formImages?: Record<string, number>;
}

export interface ReadingFormTransfer { binding: formBindingData.FormBindingData; file: fs.File | null; extraFiles?: fs.File[]; }

/** A small durable native projection. FormExtension processes never depend on a live Flutter engine. */
export default class ReadingWidgetStore {
  private context: common.Context;
  private directory: string;
  constructor(context: common.Context) {
    this.context = context;
    this.directory = context.filesDir + '/.reading-widgets';
    fs.mkdirSync(this.directory, true);
  }

  read(): ReadingWidgetSnapshot {
    try {
      const snapshot = parseReadingWidgetSnapshot(fs.readTextSync(this.directory + '/snapshot.json'));
      if (snapshot.latestCompletion !== null && !this.isOwnedCover(snapshot.latestCompletion.coverPath)) {
        snapshot.latestCompletion.coverPath = null;
      }
      if (snapshot.desktopImages !== undefined) {
        for (const size of ['small', 'medium', 'large']) {
          if (!this.isOwnedCover(snapshot.desktopImages[size])) { snapshot.desktopImages = undefined; break; }
        }
      }
      return snapshot;
    } catch (_) { return blankReadingWidgetSnapshot(new Date()); }
  }

  async publish(json: string): Promise<void> {
    const snapshot = parseReadingWidgetSnapshot(json);
    const previous = this.read();
    let nextCover: string | null = null;
    if (snapshot.latestCompletion !== null) {
      const source = snapshot.latestCompletion.coverPath;
      if (snapshot.showBookDetails && source !== null) {
        try { nextCover = this.copyCover(source); }
        catch (_) { nextCover = null; }
      }
      snapshot.latestCompletion.coverPath = nextCover;
    }
    const owned: Record<string, string> = {};
    try {
      if (snapshot.desktopImages !== undefined) {
        for (const size of ['small', 'medium', 'large']) { owned[size] = this.copyCover(snapshot.desktopImages[size]); }
        snapshot.desktopImages = owned;
      }
      this.writeJson('snapshot.json', JSON.stringify(snapshot));
    } catch (error) {
      this.removeOwnedCover(nextCover);
      for (const key of Object.keys(owned)) { this.removeOwnedCover(owned[key]); }
      throw error as Error;
    }
    // Never keep a private title/cover from an older snapshot when privacy changes.
    const oldCover = previous.latestCompletion?.coverPath ?? null;
    if (oldCover !== nextCover) { this.removeOwnedCover(oldCover); }
    if (previous.desktopImages !== undefined) {
      for (const size of ['small', 'medium', 'large']) { this.removeOwnedCover(previous.desktopImages[size]); }
    }
    for (const form of this.forms()) {
      try { await this.update(form.id, form.dimension, snapshot); }
      catch (error) { hilog.warn(0, 'ReadingWidgets', '卡片更新待重试：%{public}s', (error as Error).name); }
    }
  }

  register(id: string, dimension: number, width?: number, height?: number, cardId?: string): void {
    if (!/^[0-9]{1,32}$/.test(id)) { throw new Error('Invalid reading form id'); }
    const current = this.forms();
    const previous = current.find((form: RegisteredReadingForm): boolean => form.id === id);
    const nextDimension = this.dimension(dimension);
    const bounds = this.resolveBounds(nextDimension, width, height,
      previous?.dimension === nextDimension ? previous : undefined);
    const forms = current.filter((form: RegisteredReadingForm): boolean => form.id !== id);
    forms.push({ id: id, dimension: nextDimension, width: bounds.width, height: bounds.height, cardId: cardId ?? previous?.cardId, quoteId: previous?.quoteId });
    this.writeJson('forms.json', JSON.stringify(forms));
  }

  remove(id: string): void {
    this.writeJson('forms.json', JSON.stringify(this.forms().filter((form: RegisteredReadingForm): boolean => form.id !== id)));
  }

  dimensionFor(id: string): number {
    const found = this.forms().find((form: RegisteredReadingForm): boolean => form.id === id);
    return found?.dimension ?? 2;
  }

  boundsFor(id: string): ReadingWidgetBounds {
    const form = this.forms().find((item: RegisteredReadingForm): boolean => item.id === id);
    return this.resolveBounds(form?.dimension ?? 2, form?.width, form?.height);
  }

  transfer(dimension: number, snapshot: ReadingWidgetSnapshot = this.read(),
    bounds: ReadingWidgetBounds = this.resolveBounds(dimension), formId?: string): ReadingFormTransfer {
    const configured = this.cardTransfer(formId, dimension, bounds);
    if (configured !== null) { return configured; }
    const maximum = Math.max(300, ...snapshot.week.map((day): number => day.verifiedSeconds ?? 0));
    const week: ReadingWidgetBar[] = snapshot.week.map((day): ReadingWidgetBar => {
      const weekday = new Date(day.date + 'T00:00:00Z').getUTCDay();
      return { date: day.date, label: ['日', '一', '二', '三', '四', '五', '六'][weekday],
        minutes: widgetMinutes(day.verifiedSeconds), ratio: day.verifiedSeconds === null ? 0 : day.verifiedSeconds / maximum,
        measured: day.verifiedSeconds !== null };
    });
    const moment = snapshot.latestCompletion;
    const weekly = readingWidgetWeekSummary(snapshot.week);
    const heatWeeks = this.dimension(dimension) === 4 ? 26 : this.dimension(dimension) === 3 ? 13 : 7;
    const data: ReadingWidgetBinding = {
      dimension: this.dimension(dimension), themeId: snapshot.themeId, layoutId: snapshot.layoutId ?? 'classic', palette: snapshot.palette,
      skinId: snapshot.skinId ?? 'original',
      season: this.season(snapshot.localDay),
      goalCaption: readingGoalCaption(snapshot),
      goalRatio: validReadingGoal(snapshot.dailyGoalMinutes) === 0 ? 0 : Math.min(1, (snapshot.verifiedTodaySeconds ?? 0) / (validReadingGoal(snapshot.dailyGoalMinutes) * 60)),
      hasGoalProgress: validReadingGoal(snapshot.dailyGoalMinutes) > 0 && snapshot.verifiedTodaySeconds !== null,
      cardWidth: bounds.width, cardHeight: bounds.height,
      dayStamp: '截至 ' + widgetDateStamp(snapshot.localDay),
      streak: snapshot.qualifiedStreakDays === null ? '—' : snapshot.qualifiedStreakDays.toString(),
      minutes: widgetMinutes(snapshot.verifiedTodaySeconds), totalMinutes: widgetMinutes(snapshot.verifiedTotalSeconds),
      weekMinutes: weekly.minutes, weekLabel: weekly.label,
      heatColumns: readingWidgetHeatColumns(snapshot, heatWeeks), heatWeeks: heatWeeks,
      week: week, hasMoment: moment !== null, momentHeading: moment?.finished === true ? '最近读完' : '读到此刻',
      momentDate: moment === null ? '' : widgetDateStamp(moment.completedAt.substring(0, 10)),
      bookTitle: snapshot.showBookDetails ? moment?.title ?? '' : '',
      bookAuthor: snapshot.showBookDetails ? moment?.author ?? '' : '',
      coverImage: '', desktopImage: '', staleImage: snapshot.localDay !== widgetLocalDay(new Date()), showBookDetails: snapshot.showBookDetails
    };
    let file: fs.File | null = null;
    const rendered = snapshot.desktopImages?.[this.dimension(dimension) === 4 ? 'large' : this.dimension(dimension) === 3 ? 'medium' : 'small'];
    if (data.layoutId !== 'classic' && this.isOwnedCover(rendered ?? null)) {
      try {
        file = fs.openSync(rendered!, fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW);
        const key = 'readingFace' + util.generateRandomUUID().replace(/-/g, '');
        const images: Record<string, number> = {};
        images[key] = file.fd;
        data.formImages = images;
        data.desktopImage = 'memory://' + key;
        return { binding: formBindingData.createFormBindingData(data), file: file };
      } catch (_) { if (file !== null) { fs.closeSync(file); file = null; } }
    }
    // Classic large and the explicit keepsake style render local covers.
    if ((data.layoutId === 'classic' && data.dimension === 4 || data.layoutId === 'memory') && snapshot.showBookDetails && this.isOwnedCover(moment?.coverPath ?? null)) {
      try {
        file = fs.openSync(moment!.coverPath!, fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW);
        const key = 'readingCover' + util.generateRandomUUID().replace(/-/g, '');
        const images: Record<string, number> = {};
        images[key] = file.fd;
        data.formImages = images;
        data.coverImage = 'memory://' + key;
      } catch (_) { if (file !== null) { fs.closeSync(file); file = null; } }
    }
    return { binding: formBindingData.createFormBindingData(data), file: file };
  }

  private season(date: string): number {
    const month = Number(date.substring(5, 7));
    return month >= 3 && month <= 5 ? 0 : month >= 6 && month <= 8 ? 1 : month >= 9 && month <= 11 ? 2 : 3;
  }

  async update(id: string, dimension: number = this.dimensionFor(id), snapshot: ReadingWidgetSnapshot = this.read()): Promise<void> {
    const transfer = this.transfer(dimension, snapshot, this.boundsFor(id), id);
    try { await formProvider.updateForm(id, transfer.binding); }
    finally { if (transfer.file !== null) { fs.closeSync(transfer.file); } for (const file of transfer.extraFiles ?? []) { fs.closeSync(file); } }
  }

  private dimension(value: number): number { return value === 3 || value === 4 ? value : 2; }

  private cards(): ReadingCard[] {
    try { return JSON.parse(fs.readTextSync(this.directory + '/cards.json')) as ReadingCard[]; } catch (_) { return []; }
  }
  async publishCards(json: string): Promise<void> {
    const cards = JSON.parse(json) as ReadingCard[];
    if (!Array.isArray(cards)) { throw new Error('Invalid cards'); }
    const previous = this.cards(); const created: string[] = []; const retained: string[] = [];
    try {
      for (const card of cards) {
        if (!/^[a-zA-Z0-9_-]{1,64}$/.test(card.id) || !Array.isArray(card.quotes)) { throw new Error('Invalid card'); }
        const old = previous.find((value: ReadingCard): boolean => value.id === card.id);
        const sources: Record<string, string> = {}; const images: Record<string, string> = {};
        for (const size of ['small', 'medium', 'large']) { for (const mode of ['light', 'dark']) {
          const key = size + '_' + mode; const source = card.images[key]; sources[key] = source;
          let path = old?.sources?.[key] === source && this.isOwnedCover(old?.images[key] ?? null) ? old!.images[key] : '';
          if (path.length === 0) { path = this.copyCover(source); created.push(path); }
          images[key] = path; retained.push(path);
        } }
        card.sources = sources; card.images = images;
      }
      this.writeJson('cards.json', JSON.stringify(cards));
    } catch (error) { for (const path of created) { this.removeOwnedCover(path); } throw error as Error; }
    for (const card of previous) { for (const key of Object.keys(card.images)) {
      if (!retained.includes(card.images[key])) { this.removeOwnedCover(card.images[key]); }
    } }
    await this.updateAll();
  }
  async bindCard(id: string, cardId: string): Promise<void> {
    const forms = this.forms(); const form = forms.find((value: RegisteredReadingForm): boolean => value.id === id);
    if (form === undefined || !this.cards().some((value: ReadingCard): boolean => value.id === cardId)) { throw new Error('Missing card'); }
    form.cardId = cardId; form.quoteId = undefined;
    this.writeJson('forms.json', JSON.stringify(forms)); await this.update(id);
  }
  async nextQuote(id: string): Promise<void> {
    const forms = this.forms(); const form = forms.find((value: RegisteredReadingForm): boolean => value.id === id);
    const card = this.cards().find((value: ReadingCard): boolean => value.id === form?.cardId);
    if (form === undefined || card === undefined || card.quotes.length < 2) { return; }
    const index = Math.max(0, card.quotes.findIndex((value: ReadingCardQuote): boolean => value.id === form.quoteId));
    form.quoteId = card.quotes[(index + 1) % card.quotes.length].id;
    this.writeJson('forms.json', JSON.stringify(forms)); await this.update(id);
  }
  async updateAll(): Promise<void> { for (const form of this.forms()) { await this.update(form.id); } }
  private cardTransfer(id: string | undefined, dimension: number, bounds: ReadingWidgetBounds): ReadingFormTransfer | null {
    if (id === undefined) { return null; }
    const form = this.forms().find((value: RegisteredReadingForm): boolean => value.id === id);
    const card = this.cards().find((value: ReadingCard): boolean => value.id === form?.cardId);
    if (card === undefined) { return null; }
    const dark = card.appearance === 'dark';
    const size = dimension === 4 ? 'large' : dimension === 3 ? 'medium' : 'small';
    const path = card.images[size + (dark ? '_dark' : '_light')];
    if (!this.isOwnedCover(path)) { return null; }
    const quote = card.quotes.find((value: ReadingCardQuote): boolean => value.id === form?.quoteId) ?? card.quotes[0];
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW);
    const key = 'readingCard' + util.generateRandomUUID().replace(/-/g, ''); const images: Record<string, number> = {}; images[key] = file.fd;
    const extras: fs.File[] = []; let darkImage = '';
    if (card.appearance === 'system') {
      try {
        const darkPath = card.images[size + '_dark'];
        if (!this.isOwnedCover(darkPath)) { throw new Error('Missing dark image'); }
        const other = fs.openSync(darkPath, fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW);
        extras.push(other); const darkKey = 'readingCard' + util.generateRandomUUID().replace(/-/g, '');
        images[darkKey] = other.fd; darkImage = 'memory://' + darkKey;
      } catch (error) { fs.closeSync(file); throw error as Error; }
    }
    const data: ReadingCardBinding = { dimension: dimension, cardWidth: bounds.width, cardHeight: bounds.height,
      layoutId: card.design, skinId: card.skin, desktopImage: 'memory://' + key, desktopDarkImage: darkImage, followSystemCard: card.appearance === 'system', staleImage: card.design !== 'quote' && card.localDay !== widgetLocalDay(new Date()), dayStamp: '截至 ' + widgetDateStamp(card.localDay),
      quoteText: quote?.text ?? '在阅读中留下喜欢的句子', quoteSource: quote?.source ?? '', hasQuoteNext: card.quotes.length > 1,
      hasRecent: card.hasRecent, quoteCount: card.quotes.length, cardInk: dark ? '#F2EFE8' : '#202329', formImages: images };
    return { binding: formBindingData.createFormBindingData(data), file: file, extraFiles: extras };
  }

  private resolveBounds(dimension: number, width?: number, height?: number,
    previous?: RegisteredReadingForm): ReadingWidgetBounds {
    const fallbackWidth = dimension === 3 || dimension === 4 ? 328 : 160;
    const fallbackHeight = dimension === 4 ? 328 : 160;
    return {
      width: typeof width === 'number' && Number.isFinite(width) && width > 0 ? width :
        (typeof previous?.width === 'number' && Number.isFinite(previous.width) && previous.width > 0 ? previous.width : fallbackWidth),
      height: typeof height === 'number' && Number.isFinite(height) && height > 0 ? height :
        (typeof previous?.height === 'number' && Number.isFinite(previous.height) && previous.height > 0 ? previous.height : fallbackHeight)
    };
  }

  private forms(): RegisteredReadingForm[] {
    try {
      const source = JSON.parse(fs.readTextSync(this.directory + '/forms.json')) as RegisteredReadingForm[];
      if (!Array.isArray(source) || source.length > 512) { return []; }
      return source.filter((form: RegisteredReadingForm): boolean => form !== null &&
        typeof form.id === 'string' && /^[0-9]{1,32}$/.test(form.id) && [2, 3, 4].includes(form.dimension));
    } catch (_) { return []; }
  }

  private writeJson(name: string, json: string): void {
    const next = this.directory + '/' + name + '.next';
    const file = fs.openSync(next, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      const bytes = new util.TextEncoder().encodeInto(json);
      let written = 0;
      while (written < bytes.byteLength) {
        const count = fs.writeSync(file.fd, bytes.buffer.slice(written));
        if (count <= 0) { throw new Error('Unable to write reading widget snapshot'); }
        written += count;
      }
      fs.fsyncSync(file.fd);
    }
    finally { fs.closeSync(file); }
    fs.renameSync(next, this.directory + '/' + name);
  }

  private isOwnedCover(path: string | null): boolean {
    return path !== null && path.startsWith(this.directory + '/cover-') && /^cover-[0-9a-f-]+\.png$/.test(path.substring(this.directory.length + 1));
  }

  private removeOwnedCover(path: string | null): void {
    if (this.isOwnedCover(path)) { try { fs.unlinkSync(path!); } catch (_) {} }
  }

  private copyCover(source: string): string {
    const roots = [this.context.filesDir, this.context.cacheDir, this.context.tempDir];
    const root = roots.find((value: string): boolean => source.startsWith(value + '/'));
    if (root === undefined || source.split('/').includes('..') || source.includes('\u0000')) { throw new Error('Invalid cover path'); }
    // Refuse symlink escapes, including intermediary components, without broad storage permission.
    let path = root;
    for (const component of source.substring(root.length + 1).split('/')) {
      if (component.length === 0 || component === '.') { throw new Error('Invalid cover path'); }
      path += '/' + component;
      if (fs.lstatSync(path).isSymbolicLink()) { throw new Error('Invalid cover link'); }
    }
    const file = fs.openSync(source, fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW);
    const destination = this.directory + '/cover-' + util.generateRandomUUID() + '.png';
    try {
      const stat = fs.statSync(file.fd);
      // API 17–19 Form images have a real 2 MiB/image IPC limit.
      if (!stat.isFile() || stat.size < 8 || stat.size > 2 * 1024 * 1024) { throw new Error('Invalid cover size'); }
      const signature = new ArrayBuffer(8);
      if (fs.readSync(file.fd, signature, { offset: 0, length: 8 }) !== 8) { throw new Error('Invalid PNG'); }
      const bytes = new Uint8Array(signature);
      const png = [137, 80, 78, 71, 13, 10, 26, 10];
      for (let index = 0; index < 8; index++) { if (bytes[index] !== png[index]) { throw new Error('Invalid PNG'); } }
      fs.lseek(file.fd, 0, fs.WhenceType.SEEK_SET);
      fs.copyFileSync(file.fd, destination);
      return destination;
    } catch (error) { this.removeOwnedCover(destination); throw error as Error; }
    finally { fs.closeSync(file); }
  }
}
