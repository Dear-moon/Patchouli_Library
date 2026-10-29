import { ReadingWidgetBar } from './ReadingWidgetStore';
import { ReadingWidgetTheme, readingWidgetTheme, readingWidgetSkin } from './ReadingWidgetTheme';
import { readingWidgetArtPlacement, ReadingWidgetHeatColumn, ReadingWidgetHeatCell } from './ReadingWidgetPresentation';
import { initializeReadingWidgetFonts, readingWidgetNumberFont, readingWidgetTitleFont,
  readingWidgetDynamicTextFont } from './ReadingWidgetTypography';

const readingFormStorage = new LocalStorage();

/** Native, static compositions. Decorations have their own space and encode no data. */
@Entry(readingFormStorage)
@Component
struct ReadingFormCard {
  @LocalStorageProp('dimension') dimension: number = 2;
  @LocalStorageProp('themeId') themeId: string = 'archive';
  @LocalStorageProp('layoutId') layoutId: string = 'classic';
  @LocalStorageProp('skinId') skinId: string = 'original';
  @LocalStorageProp('season') season: number = 3;
  @LocalStorageProp('goalCaption') goalCaption: string = '';
  @LocalStorageProp('goalRatio') goalRatio: number = 0;
  @LocalStorageProp('hasGoalProgress') hasGoalProgress: boolean = false;
  @LocalStorageProp('dayStamp') dayStamp: string = '尚无阅读记录';
  @LocalStorageProp('streak') streak: string = '—';
  @LocalStorageProp('minutes') minutes: string = '—';
  @LocalStorageProp('totalMinutes') totalMinutes: string = '—';
  @LocalStorageProp('weekMinutes') weekMinutes: string = '—';
  @LocalStorageProp('weekLabel') weekLabel: string = '近7日已记录';
  @LocalStorageProp('week') week: ReadingWidgetBar[] = [];
  @LocalStorageProp('heatColumns') heatColumns: ReadingWidgetHeatColumn[] = [];
  @LocalStorageProp('heatWeeks') heatWeeks: number = 7;
  @LocalStorageProp('hasMoment') hasMoment: boolean = false;
  @LocalStorageProp('momentHeading') momentHeading: string = '读到此刻';
  @LocalStorageProp('momentDate') momentDate: string = '';
  @LocalStorageProp('bookTitle') bookTitle: string = '';
  @LocalStorageProp('bookAuthor') bookAuthor: string = '';
  @LocalStorageProp('coverImage') coverImage: string = '';
  @LocalStorageProp('desktopImage') desktopImage: string = '';
  @LocalStorageProp('desktopDarkImage') desktopDarkImage: string = '';
  @LocalStorageProp('followSystemCard') followSystemCard: boolean = false;
  @LocalStorageProp('quoteCount') quoteCount: number = 0;
  @LocalStorageProp('staleImage') staleImage: boolean = false;
  @LocalStorageProp('quoteText') quoteText: string = '';
  @LocalStorageProp('quoteSource') quoteSource: string = '';
  @LocalStorageProp('hasQuoteNext') hasQuoteNext: boolean = false;
  @LocalStorageProp('hasRecent') hasRecent: boolean = false;
  @LocalStorageProp('cardInk') cardInk: string = '#202329';
  @LocalStorageProp('showBookDetails') showBookDetails: boolean = false;
  @LocalStorageProp('cardWidth') cardWidth: number = 160;
  @LocalStorageProp('cardHeight') cardHeight: number = 160;

  aboutToAppear(): void { initializeReadingWidgetFonts(); }

  private theme(): ReadingWidgetTheme {
    if (this.layoutId !== 'classic' && this.skinId !== 'original') { return readingWidgetSkin(this.skinId, this.season); }
    return readingWidgetTheme(this.layoutId === 'focus' ? 'editorial' : this.layoutId === 'week' ? 'constellation' :
      this.layoutId === 'calendar' ? 'shelf' : this.layoutId === 'memory' ? 'festival' : this.themeId);
  }
  private knownCalendar(): boolean {
    return this.heatColumns.some((column: ReadingWidgetHeatColumn): boolean =>
      column.cells.some((cell: ReadingWidgetHeatCell): boolean => cell.level !== null && !cell.future));
  }
  private illustrated(): boolean { return this.layoutId === 'focus' && this.skinId === 'seasons' && this.dimension !== 2; }
  private seasonResource(): Resource {
    if (this.season === 0) { return $r('app.media.widget_season_spring'); }
    if (this.season === 1) { return $r('app.media.widget_season_summer'); }
    if (this.season === 2) { return $r('app.media.widget_season_autumn'); }
    return $r('app.media.widget_season_winter');
  }
  private focusSize(): number { return this.dimension === 4 ? (this.illustrated() ? 64 : 76) : (this.illustrated() ? 44 : 48); }

  @Builder
  private SeasonArt(width: number, height: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(this.seasonResource()).objectFit(ImageFit.Fill)
        .width(720 * Math.max(width / 720, height / 405)).height(405 * Math.max(width / 720, height / 405))
        .position({ x: (width - 720 * Math.max(width / 720, height / 405)) * 0.8,
          y: (height - 405 * Math.max(width / 720, height / 405)) * 0.15 })
    }.width(width).height(height).clip(true).accessibilityLevel('no')
  }
  private heatCellSize(): number { return this.dimension === 2 ? 4.5 : this.dimension === 3 ? 5 : 7; }
  private heatGap(): number { return this.dimension === 4 ? 3 : 2; }
  private heatFill(cell: ReadingWidgetHeatCell): string {
    return cell.level === null ? 'transparent' : cell.level === 0 ? this.theme().secondary : this.theme().accent;
  }
  private heatOpacity(cell: ReadingWidgetHeatCell): number {
    return cell.level === null ? 1 : cell.level === 0 ? 0.45 : cell.level === 1 ? 0.25 : cell.level === 2 ? 0.48 : cell.level === 3 ? 0.72 : 1;
  }
  private open(destination: string): void {
    postCardAction(this, { action: 'router', abilityName: 'EntryAbility',
      params: { readingWidgetDestination: destination } });
  }

  @Builder
  private Artwork(resource: Resource, width: number, height: number, focusX: number, focusY: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(resource).objectFit(ImageFit.Fill)
        .width(readingWidgetArtPlacement(width, height, focusX, focusY).imageWidth)
        .height(readingWidgetArtPlacement(width, height, focusX, focusY).imageHeight)
        .position({ x: readingWidgetArtPlacement(width, height, focusX, focusY).left,
          y: readingWidgetArtPlacement(width, height, focusX, focusY).top })
        .accessibilityLevel('no')
    }.width(width).height(height).clip(true)
  }

  @Builder
  private CompactWeek(inverse: boolean) {
    Row({ space: 4 }) {
      ForEach(this.week, (day: ReadingWidgetBar) => {
        Stack({ alignContent: Alignment.Bottom }) {
          if (day.measured) {
            Rect().width('100%').height(Math.max(2, day.ratio * 13))
              .fill(inverse ? this.theme().background : this.theme().accent).opacity(0.8)
          } else {
            Rect().width('100%').height(3).fill(Color.Transparent).stroke(this.theme().secondary).strokeWidth(0.7)
          }
        }.layoutWeight(1).height(13).accessibilityText(day.date + ' 阅读 ' + day.minutes + ' 分钟')
      }, (day: ReadingWidgetBar): string => day.date)
    }.width('100%').height(13)
  }

  @Builder
  private MinuteLine(centered: boolean) {
    Text('当日 ' + this.minutes + ' 分钟').fontSize(11).fontColor(this.theme().foreground)
      .maxLines(1).width('100%').textAlign(centered ? TextAlign.Center : TextAlign.Start)
  }
  @Builder
  private Rule() { Rect().width('100%').height(1).fill(this.theme().secondary) }

  @Builder
  private Heatmap() {
    Column({ space: 4 }) {
      Row() {
        Text('近' + this.heatWeeks + '周').fontSize(10).fontColor(this.theme().muted)
        Blank()
        Text(this.dayStamp).fontSize(9).fontColor(this.theme().muted)
      }.width('100%')
      Row({ space: 5 }) {
        Column() {
          Text('一').fontSize(8).fontColor(this.theme().muted).height(9)
          Blank()
          Text('四').fontSize(8).fontColor(this.theme().muted).height(9)
          Blank()
          Text('日').fontSize(8).fontColor(this.theme().muted).height(9)
        }.width(9).height(this.heatCellSize() * 7 + this.heatGap() * 6)
        Row({ space: this.heatGap() }) {
          ForEach(this.heatColumns, (column: ReadingWidgetHeatColumn) => {
            Column({ space: this.heatGap() }) {
              ForEach(column.cells, (cell: ReadingWidgetHeatCell) => {
                Stack() {
                  if (!cell.future) {
                    Rect().width(this.heatCellSize() - (cell.today ? 2 : 0))
                      .height(this.heatCellSize() - (cell.today ? 2 : 0)).radius(1.1)
                      .fill(this.heatFill(cell)).fillOpacity(this.heatOpacity(cell))
                      .stroke(cell.level === null ? this.theme().secondary : Color.Transparent)
                      .strokeWidth(cell.level === null ? 0.5 : 0)
                    if (cell.today) {
                      Rect().width(this.heatCellSize()).height(this.heatCellSize()).radius(1.3)
                        .fill(Color.Transparent).stroke(this.theme().accent).strokeWidth(0.7)
                    }
                  }
                }.width(this.heatCellSize()).height(this.heatCellSize()).accessibilityText(cell.description)
              }, (cell: ReadingWidgetHeatCell): string => cell.date)
            }
          }, (column: ReadingWidgetHeatColumn): string => column.date)
        }
        Blank()
      }.width('100%')
    }.padding({ left: 12, right: 12, top: 5, bottom: 7 }).width('100%')
      .backgroundColor(this.theme().background)
  }

  @Builder
  private CompactMetric(size: number) {
    Row({ space: 3 }) {
      Text('连续').fontSize(10).fontColor(this.theme().muted).margin({ bottom: 4 })
      Text(this.streak).fontFamily(readingWidgetNumberFont()).fontWeight(FontWeight.Bold)
        .fontSize(size).fontColor(this.theme().foreground).maxLines(1)
      Text('天').fontSize(10).fontColor(this.theme().muted).margin({ bottom: 4 })
    }.alignItems(VerticalAlign.Bottom)
  }

  @Builder
  private Header(label: string) {
    Text(label).fontFamily(this.theme().prefersSerif ? readingWidgetTitleFont(label) : readingWidgetDynamicTextFont())
      .fontSize(11).fontWeight(FontWeight.Medium).fontColor(this.theme().foreground).maxLines(1)
  }

  @Builder
  private RecentSummary() {
    Column({ space: 3 }) {
      this.CompactWeek(false)
      Text(this.weekLabel + ' ' + this.weekMinutes + ' 分钟').fontSize(10).fontColor(this.theme().foreground).maxLines(1)
    }.width('100%')
  }

  @Builder
  private MomentCopy(size: number, centered: boolean) {
    Column({ space: 6 }) {
      Text(this.hasMoment ? this.momentHeading : '下一次阅读').fontSize(11).fontColor(this.theme().muted)
        .fontFamily(this.theme().prefersSerif ? readingWidgetTitleFont(this.hasMoment ? this.momentHeading : '下一次阅读') : readingWidgetDynamicTextFont())
        .width('100%').textAlign(centered ? TextAlign.Center : TextAlign.Start)
      Text(this.hasMoment ? (this.showBookDetails && this.bookTitle.length > 0 ? this.bookTitle : '一个属于你的\n阅读时刻') : '故事还在\n等待翻开')
        .fontSize(size).fontFamily(readingWidgetDynamicTextFont()).fontWeight(FontWeight.Medium).fontColor(this.theme().foreground)
        .maxLines(this.themeId === 'score' || this.themeId === 'shelf' || this.themeId === 'signal' ? 2 : 3)
        .width('100%').textAlign(centered ? TextAlign.Center : TextAlign.Start)
      if (this.showBookDetails && this.bookAuthor.length > 0) {
        Text(this.bookAuthor).fontFamily(readingWidgetDynamicTextFont()).fontSize(11).fontColor(this.theme().muted)
          .maxLines(1).width('100%').textAlign(centered ? TextAlign.Center : TextAlign.Start)
      }
      if (this.hasMoment) {
        Text(this.momentDate).fontSize(11).fontColor(this.theme().muted).width('100%')
          .textAlign(centered ? TextAlign.Center : TextAlign.Start)
      }
    }.width('100%')
  }

  // Small: readable live streak/today above a seven-week native activity grid.
  @Builder
  private SmallArchive() {
    Column({ space: 2 }) {
      Row() { this.Header('阅读档案'); Blank(); Rect().width(22).height(3).fill(this.theme().accent) }.width('100%')
      this.CompactMetric(31)
      Text('当日 ' + this.minutes + ' 分钟').fontSize(10).fontColor(this.theme().muted).maxLines(1)
    }.padding({ left: 12, right: 12, top: 10, bottom: 5 }).width('100%').height('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  private SmallShelf() {
    Row({ space: 8 }) {
      Rect().width(3).height('80%').fill(this.theme().accent)
      Column({ space: 2 }) { this.Header('书架索引'); this.CompactMetric(31); this.MinuteLine(false) }.layoutWeight(1)
    }.padding({ left: 12, right: 8, top: 9, bottom: 4 }).width('100%').height('100%')
  }
  @Builder
  private SmallEditorial() {
    Column({ space: 1 }) {
      this.Header('阅读年表')
      Row() { this.CompactMetric(31); Blank(); Rect().width(1).height(28).fill(this.theme().accent) }.width('100%')
      this.MinuteLine(false)
    }.padding({ left: 13, right: 13, top: 9, bottom: 4 }).width('100%').height('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  private SmallConstellation() {
    Stack({ alignContent: Alignment.TopEnd }) {
      this.Artwork($r('app.media.reading_art_constellation_117'), this.cardWidth * 0.47, this.cardHeight - 70, 0.67, 0.5)
      Column({ space: 2 }) { this.Header('星港夜航'); this.CompactMetric(29); this.MinuteLine(false) }
        .padding({ left: 12, top: 9, right: 5, bottom: 4 }).width('100%').height('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').clip(true)
  }
  @Builder
  private SmallSignal() {
    Row({ space: 0 }) {
      Column({ space: 2 }) { this.Header('行动档案'); this.CompactMetric(29); this.MinuteLine(false) }
        .padding({ left: 10, top: 7, right: 3, bottom: 3 }).width('68%').height('100%')
      this.Artwork($r('app.media.reading_art_signal_117'), this.cardWidth * 0.32, this.cardHeight - 70, 0.72, 0.5)
    }.width('100%').height('100%').border({ width: { top: 3 }, color: this.theme().accent }).clip(true)
  }
  @Builder
  private SmallScore() {
    Stack({ alignContent: Alignment.TopEnd }) {
      this.Artwork($r('app.media.reading_art_score_117'), this.cardWidth * 0.45, this.cardHeight - 70, 0.69, 0.46)
      Column({ space: 1 }) { this.Header('青春频率'); this.CompactMetric(30); this.MinuteLine(false) }
        .padding({ left: 12, top: 8, right: 6, bottom: 3 }).width('100%').height('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').border({ width: { bottom: 2 }, color: this.theme().secondary }).clip(true)
  }
  @Builder
  private SmallInk() {
    Row({ space: 6 }) {
      Rect().width(2).height(42).fill(this.theme().accent)
      Column({ space: 1 }) { this.Header('云间书信'); this.CompactMetric(29); this.MinuteLine(false) }.layoutWeight(1)
      this.Artwork($r('app.media.reading_art_ink_117'), this.cardWidth * 0.28, this.cardHeight - 80, 0.69, 0.47)
    }.padding({ left: 11, top: 7, bottom: 3 }).width('100%').height('100%').clip(true)
  }
  @Builder
  private SmallFestival() {
    Column({ space: 1 }) {
      Row() { this.Header('晴空来信'); Blank(); Rect().width(18).height(3).fill(this.theme().accent) }.width('100%')
      Row({ space: 4 }) { this.CompactMetric(30); Blank(); this.Artwork($r('app.media.reading_art_festival_117'), 39, 34, 0.7, 0.45) }.width('100%')
      this.MinuteLine(false)
    }.padding({ left: 12, right: 10, top: 8, bottom: 3 }).width('100%').height('100%').alignItems(HorizontalAlign.Start)
  }

  // Medium: retain the exact seven-day rhythm and totals, then add thirteen weeks.
  @Builder
  private MediumArchive() {
    Column({ space: 4 }) {
      Row() { this.Header('阅读档案'); Blank(); Text('累计 ' + this.totalMinutes + ' 分钟').fontSize(10).fontColor(this.theme().muted) }.width('100%')
      Row({ space: 18 }) { this.CompactMetric(33); Column() { this.RecentSummary() }.layoutWeight(1) }.width('100%')
    }.padding({ left: 14, top: 11, right: 14, bottom: 5 }).width('100%').height('100%')
      .border({ width: { top: 3 }, color: this.theme().accent })
  }
  @Builder
  private MediumShelf() {
    Row({ space: 13 }) {
      Rect().width(4).height(53).fill(this.theme().accent)
      Column({ space: 2 }) { this.Header('书架索引'); this.CompactMetric(32) }.width(100)
      Column({ space: 4 }) { this.RecentSummary(); Text('当日 ' + this.minutes + ' 分钟').fontSize(10).fontColor(this.theme().muted) }.layoutWeight(1)
    }.padding({ left: 13, right: 13, top: 9, bottom: 5 }).width('100%').height('100%')
  }
  @Builder
  private MediumEditorial() {
    Row({ space: 13 }) {
      Column({ space: 2 }) { this.Header('阅读年表'); this.CompactMetric(32) }.width(105)
      Rect().width(1).height(53).fill(this.theme().accent)
      Column({ space: 4 }) { Text('累计 ' + this.totalMinutes + ' 分钟').fontSize(10).fontColor(this.theme().muted); this.RecentSummary() }.layoutWeight(1)
    }.padding({ left: 14, right: 14, top: 8, bottom: 5 }).width('100%').height('100%')
  }
  @Builder
  private MediumConstellation() {
    Row({ space: 0 }) {
      Column({ space: 2 }) { this.Header('星港夜航'); this.CompactMetric(29); this.RecentSummary() }
        .padding({ left: 14, right: 12, top: 6, bottom: 4 }).width('58%').height('100%')
      this.Artwork($r('app.media.reading_art_constellation_117'), this.cardWidth * 0.42, this.cardHeight - 75, 0.68, 0.5)
    }.width('100%').height('100%').clip(true)
  }
  @Builder
  private MediumSignal() {
    Row({ space: 0 }) {
      this.Artwork($r('app.media.reading_art_signal_117'), this.cardWidth * 0.35, this.cardHeight - 75, 0.72, 0.48)
      Column({ space: 2 }) { this.Header('行动档案'); this.CompactMetric(29); this.RecentSummary() }
        .padding({ left: 13, right: 13, top: 4, bottom: 4 }).layoutWeight(1).height('100%')
    }.width('100%').height('100%').border({ width: { top: 3 }, color: this.theme().accent }).clip(true)
  }
  @Builder
  private MediumScore() {
    Column({ space: 0 }) {
      Row({ space: 10 }) {
        Column({ space: 1 }) { this.Header('青春频率'); this.CompactMetric(30) }.width(118)
        this.Artwork($r('app.media.reading_art_score_117'), this.cardWidth - 145, 42, 0.7, 0.48)
      }.width('100%')
      this.RecentSummary()
    }.padding({ left: 13, right: 13, top: 4, bottom: 4 }).width('100%').height('100%')
  }
  @Builder
  private MediumInk() {
    Row({ space: 8 }) {
      Rect().width(2).height(48).fill(this.theme().accent)
      Column({ space: 2 }) { this.Header('云间书信'); this.CompactMetric(29); this.RecentSummary() }.layoutWeight(1)
      this.Artwork($r('app.media.reading_art_ink_117'), this.cardWidth * 0.36, this.cardHeight - 75, 0.69, 0.5)
    }.padding({ left: 13, top: 3, bottom: 3 }).width('100%').height('100%').clip(true)
  }
  @Builder
  private MediumFestival() {
    Row({ space: 0 }) {
      Column({ space: 2 }) { this.Header('晴空来信'); this.CompactMetric(29); this.RecentSummary() }
        .padding({ left: 14, right: 10, top: 5, bottom: 4 }).width('58%').height('100%')
      this.Artwork($r('app.media.reading_art_festival_117'), this.cardWidth * 0.42, this.cardHeight - 75, 0.71, 0.49)
    }.width('100%').height('100%').border({ width: { bottom: 3 }, color: this.theme().accent }).clip(true)
  }

  // Large separates immutable completion metadata from the current 26-week activity.
  @Builder
  private LargeArchive() {
    Column({ space: 8 }) {
      Row() { this.Header('阅读档案'); Blank(); Rect().width(25).height(3).fill(this.theme().accent) }.width('100%')
      Row({ space: 16 }) {
        if (this.showBookDetails && this.coverImage.length > 0) {
          Image(this.coverImage).objectFit(ImageFit.Contain).width(64).height(100)
        }
        Column() { this.MomentCopy(21, false) }.layoutWeight(1)
      }.width('100%').layoutWeight(1)
      this.Artwork($r('app.media.reading_art_archive_117'), this.cardWidth - 28, 25, 0.66, 0.5)
    }.padding(14).width('100%').height('100%')
  }
  @Builder
  private LargeShelf() {
    Row({ space: 13 }) {
      Rect().width(4).height('90%').fill(this.theme().accent)
      Column({ space: 9 }) {
        this.Header('书架索引')
        Row({ space: 14 }) {
          Column() { this.MomentCopy(20, false) }.layoutWeight(1)
          if (this.showBookDetails && this.coverImage.length > 0) {
            Image(this.coverImage).objectFit(ImageFit.Contain).width(65).height(102)
          }
        }.width('100%').layoutWeight(1)
        this.Artwork($r('app.media.reading_art_shelf_117'), this.cardWidth - 47, 23, 0.73, 0.5)
      }.layoutWeight(1).height('100%')
    }.padding(14).width('100%').height('100%')
  }
  @Builder
  private LargeEditorial() {
    Column({ space: 8 }) {
      this.Header('阅读年表')
      Row({ space: 12 }) {
        Rect().width(1).height('95%').fill(this.theme().accent)
        Column() { this.MomentCopy(21, false) }.layoutWeight(1)
        if (this.showBookDetails && this.coverImage.length > 0) {
          Image(this.coverImage).objectFit(ImageFit.Contain).width(62).height(98)
        }
      }.width('100%').layoutWeight(1)
      this.Artwork($r('app.media.reading_art_editorial_117'), this.cardWidth - 28, 23, 0.7, 0.5)
    }.padding(14).width('100%').height('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  private LargeConstellation() {
    Row({ space: 0 }) {
      Column({ space: 9 }) {
        this.MomentCopy(20, false)
        if (this.showBookDetails && this.coverImage.length > 0) {
          Image(this.coverImage).objectFit(ImageFit.Contain).width(40).height(60)
        }
      }.padding(14).width('57%').height('100%').alignItems(HorizontalAlign.Start)
      this.Artwork($r('app.media.reading_art_constellation_117'), this.cardWidth * 0.43, this.cardHeight - 112, 0.69, 0.48)
    }.width('100%').height('100%').clip(true)
  }
  @Builder
  private LargeSignal() {
    Row({ space: 0 }) {
      this.Artwork($r('app.media.reading_art_signal_117'), this.cardWidth * 0.43, this.cardHeight - 112, 0.7, 0.48)
      Column({ space: 8 }) {
        this.Rule()
        this.MomentCopy(19, false)
        if (this.showBookDetails && this.coverImage.length > 0) {
          Image(this.coverImage).objectFit(ImageFit.Contain).width(36).height(54)
        }
      }.padding(13).layoutWeight(1).height('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').clip(true)
  }
  @Builder
  private LargeScore() {
    Column({ space: 0 }) {
      this.Artwork($r('app.media.reading_art_score_117'), this.cardWidth, 64, 0.7, 0.48)
      Row({ space: 15 }) {
        if (this.showBookDetails && this.coverImage.length > 0) {
          Image(this.coverImage).objectFit(ImageFit.Contain).width(50).height(78)
        }
        Column({ space: 6 }) { this.Rule(); this.MomentCopy(19, true) }.layoutWeight(1)
      }.padding({ left: 16, top: 9, right: 16, bottom: 8 }).width('100%').layoutWeight(1)
    }.width('100%').height('100%').clip(true)
  }
  @Builder
  private LargeInk() {
    Row({ space: 8 }) {
      Rect().width(3).height('78%').fill(this.theme().accent)
      Column({ space: 8 }) {
        this.MomentCopy(19, false)
        if (this.showBookDetails && this.coverImage.length > 0) {
          Image(this.coverImage).objectFit(ImageFit.Contain).width(36).height(54)
        }
      }.width('52%').height('100%').alignItems(HorizontalAlign.Start)
      this.Artwork($r('app.media.reading_art_ink_117'), this.cardWidth * 0.37, this.cardHeight - 112, 0.69, 0.5)
    }.padding({ left: 12, top: 12, bottom: 7 }).width('100%').height('100%').clip(true)
  }
  @Builder
  private LargeFestival() {
    Column({ space: 0 }) {
      Row({ space: 0 }) {
        Column() { this.MomentCopy(20, false) }.padding(14).width('57%')
        this.Artwork($r('app.media.reading_art_festival_117'), this.cardWidth * 0.43, this.cardHeight - 112, 0.7, 0.48)
      }.width('100%').layoutWeight(1)
      if (this.showBookDetails && this.coverImage.length > 0) {
        Image(this.coverImage).objectFit(ImageFit.Contain).width(35).height(53).margin({ left: 14, bottom: 7 })
      }
    }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
      .border({ width: { bottom: 3 }, color: this.theme().accent }).clip(true)
  }

  @Builder
  private Small() {
    if (this.themeId === 'shelf') { this.SmallShelf() }
    else if (this.themeId === 'editorial') { this.SmallEditorial() }
    else if (this.themeId === 'constellation') { this.SmallConstellation() }
    else if (this.themeId === 'signal') { this.SmallSignal() }
    else if (this.themeId === 'score') { this.SmallScore() }
    else if (this.themeId === 'ink') { this.SmallInk() }
    else if (this.themeId === 'festival') { this.SmallFestival() }
    else { this.SmallArchive() }
  }
  @Builder
  private Medium() {
    if (this.themeId === 'shelf') { this.MediumShelf() }
    else if (this.themeId === 'editorial') { this.MediumEditorial() }
    else if (this.themeId === 'constellation') { this.MediumConstellation() }
    else if (this.themeId === 'signal') { this.MediumSignal() }
    else if (this.themeId === 'score') { this.MediumScore() }
    else if (this.themeId === 'ink') { this.MediumInk() }
    else if (this.themeId === 'festival') { this.MediumFestival() }
    else { this.MediumArchive() }
  }
  @Builder
  private Large() {
    if (this.themeId === 'shelf') { this.LargeShelf() }
    else if (this.themeId === 'editorial') { this.LargeEditorial() }
    else if (this.themeId === 'constellation') { this.LargeConstellation() }
    else if (this.themeId === 'signal') { this.LargeSignal() }
    else if (this.themeId === 'score') { this.LargeScore() }
    else if (this.themeId === 'ink') { this.LargeInk() }
    else if (this.themeId === 'festival') { this.LargeFestival() }
    else { this.LargeArchive() }
  }
  @Builder
  private ContentDesign() {
    Column({ space: 8 }) {
      if (this.layoutId === 'focus') {
        Text(this.dayStamp.replace('截至 ', '') + ' / 阅读').fontSize(11).fontColor(this.theme().muted)
        Blank()
        if (this.minutes !== '—') {
          Text(this.minutes).fontFamily(readingWidgetNumberFont()).fontSize(this.focusSize())
            .fontColor(this.skinId === 'original' ? this.theme().foreground : this.theme().accent).maxLines(1).minFontSize(28).maxFontSize(this.focusSize())
          Text('分钟').fontSize(12).fontColor(this.theme().muted)
        }
        Blank()
        if (this.hasGoalProgress) {
          Stack({ alignContent: Alignment.Start }) {
            Rect().radius(2).height(4).width('100%').fill(this.theme().secondary)
            Rect().radius(2).height(4).width((this.goalRatio * 100).toString() + '%').fill(this.theme().accent)
          }.width('100%').height(4)
        }
        if (this.goalCaption.length > 0) { Text(this.goalCaption).fontSize(11).fontColor(this.theme().muted).maxLines(1) }
        Text(this.streak !== '—' && this.streak !== '0' ? '连续 ' + this.streak + ' 天' : this.dayStamp)
          .fontSize(10).fontColor(this.theme().muted).maxLines(1)
      } else if (this.layoutId === 'week') {
        Text('近七日 / READING RHYTHM').fontSize(10).fontColor(this.theme().muted)
        if (this.weekMinutes !== '—') {
          Text(this.weekMinutes + ' 分钟').fontFamily(readingWidgetNumberFont()).fontSize(32)
            .fontColor(this.theme().foreground).maxLines(1)
          Row({ space: 8 }) {
            ForEach(this.week, (day: ReadingWidgetBar) => {
              Column({ space: 5 }) {
                Blank()
                if (day.measured) {
                  Rect().radius(2).width('70%').height(Math.max(2, (this.cardHeight - 125) * day.ratio))
                    .fill(this.theme().accent)
                } else {
                  Rect().radius(2).width('70%').height(3).fill(Color.Transparent).stroke(this.theme().secondary).strokeWidth(1)
                }
                Text(day.date.substring(8)).fontSize(9).fontColor(this.theme().muted)
              }.layoutWeight(1).height('100%').accessibilityText(day.date + '：' + (day.measured ? day.minutes + ' 分钟' : '未记录'))
            }, (day: ReadingWidgetBar): string => day.date)
          }.layoutWeight(1).width('100%')
        } else { Blank() }
        Text(this.dayStamp).fontSize(10).fontColor(this.theme().muted)
      } else if (this.layoutId === 'calendar') {
        Text('阅读日历').fontSize(11).fontColor(this.theme().muted)
        Blank()
        if (this.knownCalendar()) { this.Heatmap() }
        Blank()
      } else {
        Text(this.hasMoment ? '书页留念' : '下一段故事').fontSize(11).fontColor(this.theme().muted)
        Blank()
        Row({ space: 10 }) {
          Column({ space: 8 }) {
            Text(this.showBookDetails && this.bookTitle.length > 0 ? this.bookTitle : this.hasMoment ? '每一页，\n都算数。' : '从这一页\n开始。')
              .fontSize(23).fontFamily(readingWidgetDynamicTextFont()).fontColor(this.theme().foreground).maxLines(3)
            if (this.showBookDetails && this.bookAuthor.length > 0) {
              Text(this.bookAuthor).fontSize(11).fontColor(this.theme().muted).maxLines(1)
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.showBookDetails && this.coverImage.length > 0) {
            Image(this.coverImage).objectFit(ImageFit.Contain).width(45).height(68)
          }
        }.width('100%')
        Blank()
        Rect().width('100%').height(3).fill(this.theme().accent)
        Text(this.hasMoment ? this.momentDate + ' · ' + this.momentHeading : this.dayStamp)
          .fontSize(10).fontColor(this.theme().muted).maxLines(1)
      }
    }.padding(16).width('100%').height('100%').alignItems(HorizontalAlign.Start)
  }
  build() {
    Stack() {
      if (this.desktopImage.length > 0 && this.layoutId !== 'classic') {
        Stack({ alignContent: Alignment.BottomEnd }) {
          Image(this.desktopImage).width('100%').height('100%').objectFit(ImageFit.Fill)
            .opacity(this.followSystemCard ? $r('app.float.reading_widget_light_opacity') : 1)
            .accessibilityText('轻小说文库，阅读 ' + this.minutes + ' 分钟。' + this.dayStamp)
            .onClick((): void => this.open(this.layoutId === 'memory' ? 'moments' : this.layoutId === 'quote' ? 'excerpts' : 'statistics'))
          if (this.followSystemCard && this.desktopDarkImage.length > 0) {
            Image(this.desktopDarkImage).width('100%').height('100%').objectFit(ImageFit.Fill).opacity($r('app.float.reading_widget_dark_opacity'))
              .onClick((): void => this.open(this.layoutId === 'memory' ? 'moments' : this.layoutId === 'quote' ? 'excerpts' : 'statistics'))
          }
          if (this.staleImage) { Text(this.dayStamp).fontSize(10).fontColor('#FFFFFF').padding(3).backgroundColor('#CC17191B').borderRadius(3).margin(10) }
          if (this.layoutId === 'quote') {
            Column({ space: 6 }) {
              Text(this.quoteText).fontSize((this.dimension === 4 ? 20 : this.dimension === 3 ? 16 : 14) * this.cardWidth / (this.dimension === 2 ? 170 : 364))
                .fontColor(this.followSystemCard ? $r('app.color.reading_widget_ink') : this.cardInk).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              Blank()
              if (this.quoteSource.length > 0) { Text(this.quoteSource).fontSize(10).fontColor(this.followSystemCard ? $r('app.color.reading_widget_ink') : this.cardInk).opacity(0.7).maxLines(1).width('100%') }
            }.alignItems(HorizontalAlign.Start)
              .width(this.cardWidth * (this.dimension === 3 ? 318 / 364 : this.dimension === 4 ? 332 / 364 : 138 / 170))
              .height(this.cardHeight * (this.dimension === 4 ? 108 / 382 : this.dimension === 2 ? 72 / 170 : 84 / 170))
              .position({ x: this.cardWidth * (this.dimension === 3 ? 30 / 364 : this.dimension === 4 ? 16 / 364 : 16 / 170),
                y: this.cardHeight * (this.dimension === 4 ? 230 / 382 : this.dimension === 2 ? 62 / 170 : 50 / 170) })
              .onClick((): void => this.open('excerpts'))
            if (this.hasQuoteNext) {
              Row() {
                Text('↻ 换一条').fontSize(11).fontColor('#FFFFFF').backgroundColor('#477D77').borderRadius(12).width(66).height(24).textAlign(TextAlign.Center)
              }.width(80).height(44).justifyContent(FlexAlign.Center)
                .position({ x: this.cardWidth - 80, y: this.cardHeight - 44 }).accessibilityText('换一条摘录')
                .onClick((): void => { postCardAction(this, { action: 'message', params: { action: 'nextQuote' } }); })
            }
            if (this.dimension === 4 && this.quoteCount > 0) {
              Text('共 ' + this.quoteCount + ' 条摘录').fontSize(11).fontColor(this.followSystemCard ? $r('app.color.reading_widget_ink') : this.cardInk).opacity(0.7)
                .position({ x: 16, y: this.cardHeight - 32 })
            }
          }
          if (this.dimension === 4 && this.hasRecent) {
            Row().width('100%').height(this.cardHeight * 54 / 382).position({ x: 0, y: this.cardHeight * 328 / 382 })
              .accessibilityText('继续上次阅读').onClick((): void => { this.open('continue'); })
          }
        }.width('100%').height('100%')
      } else if (this.layoutId !== 'classic') {
        this.SkinDecoration()
        if (this.illustrated()) {
          if (this.dimension === 4) {
            Column({ space: 0 }) {
              this.SeasonArt(this.cardWidth, 126)
              Column() { this.ContentDesign() }.layoutWeight(1).width('100%')
            }.width('100%').height('100%')
          } else {
            Row({ space: 0 }) {
              this.SeasonArt(116, this.cardHeight)
              Column() { this.ContentDesign() }.layoutWeight(1).height('100%')
            }.width('100%').height('100%')
          }
        } else { this.ContentDesign() }
      }
      else {
      Column({ space: 0 }) {
      Stack() {
        if (this.dimension === 4) { this.Large() }
        else if (this.dimension === 3) { this.Medium() }
        else { this.Small() }
      }.width('100%').layoutWeight(1).clip(true)
      this.Heatmap()
      }
      }
    }.width('100%').height('100%').backgroundColor(this.theme().background)
      .onClick((): void => {
        // Rendered cards route via sibling hit regions. A quote-button tap must
        // never bubble into an application launch from the outer container.
        if (this.desktopImage.length === 0 || this.layoutId === 'classic') {
          this.open(this.layoutId === 'memory' || this.layoutId === 'classic' && this.dimension === 4 ? 'moments' : this.layoutId === 'quote' ? 'excerpts' : 'statistics');
        }
      })
  }

  @Builder
  private SkinDecoration() {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.skinId === 'seasons') {
        Text(['春', '夏', '秋', '冬'][this.season]).fontSize(62).fontColor(this.theme().accent).opacity(0.13).margin({ right: 12, top: 4 })
        Row() {
          ForEach(['#AF7D8B', '#5786A2', '#B18842', '#4F8985'], (color: string) => {
            Rect().height(5).layoutWeight(1).fill(color)
          })
        }.width('100%').position({ x: 0, y: this.cardHeight - 5 })
      } else if (this.skinId === 'archive') {
        Rect().width(4).height('100%').fill(this.theme().accent).position({ x: 0, y: 0 })
        Row({ space: 2 }) { ForEach([0,1,2,3,4,5,6,7,8,9], (value: number) => {
          Rect().width(1).height(12).fill(this.theme().accent)
        }) }.position({ x: this.cardWidth - 44, y: this.cardHeight - 26 })
      } else if (this.skinId === 'film') {
        Row({ space: 8 }) { ForEach([0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24], (value: number) => {
          Rect().width(6).height(4).fill('#D6D2C7')
        }) }.position({ x: 12, y: 3 })
        Row({ space: 8 }) { ForEach([0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24], (value: number) => {
          Rect().width(6).height(4).fill('#D6D2C7')
        }) }.position({ x: 12, y: this.cardHeight - 7 })
      } else if (this.skinId === 'night') {
        Circle().width(16).height(16).fill(this.theme().accent).position({ x: this.cardWidth - 33, y: 17 })
        Circle().width(16).height(16).fill(this.theme().background).position({ x: this.cardWidth - 29, y: 13 })
        Row({ space: 5 }) { ForEach([10,16,22,10,16,22,10,16], (height: number, index: number) => {
          Rect().height(height).layoutWeight(1).fill(this.theme().foreground).opacity(0.06)
        }, (height: number, index: number): string => index.toString()) }.width('100%').height(22).alignItems(VerticalAlign.Bottom).position({ x: 0, y: this.cardHeight - 22 })
      } else if (this.skinId === 'paper') {
        Rect().width(24).height(13).fill(this.theme().accent).opacity(0.3).rotate({ angle: 7 }).position({ x: this.cardWidth - 39, y: -2 })
      }
    }.width('100%').height('100%').clip(true).accessibilityLevel('no')
  }
}
