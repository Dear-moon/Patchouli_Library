import { ReadingWidgetDay, ReadingWidgetSnapshot, widgetMinutes,
  widgetHeatmap, widgetHeatmapDates, widgetHeatLevel } from './ReadingWidgetSnapshot';

export interface ReadingWidgetArtPlacement {
  imageWidth: number;
  imageHeight: number;
  left: number;
  top: number;
}

/** Native Image placement: cover without distortion, preserving the selected focal point. */
export function readingWidgetArtPlacement(width: number, height: number,
  focusX: number, focusY: number): ReadingWidgetArtPlacement {
  const scale = Math.max(width / 1536, height / 1024);
  const imageWidth = 1536 * scale;
  const imageHeight = 1024 * scale;
  return {
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    left: Math.min(0, Math.max(width - imageWidth, width * 0.5 - imageWidth * focusX)),
    top: Math.min(0, Math.max(height - imageHeight, height * 0.5 - imageHeight * focusY))
  };
}

export interface ReadingWidgetWeekSummary { minutes: string; label: string; }

/** Aggregate original seconds once, before rounding; null days remain explicitly unmeasured. */
export function readingWidgetWeekSummary(days: ReadingWidgetDay[]): ReadingWidgetWeekSummary {
  let seconds = 0;
  let measured = false;
  let partial = false;
  for (const day of days) {
    if (day.verifiedSeconds === null) { partial = true; }
    else { seconds += day.verifiedSeconds; measured = true; }
  }
  return { minutes: widgetMinutes(measured ? seconds : null), label: partial ? '近7日已记录' : '近7日' };
}

export interface ReadingWidgetHeatCell {
  date: string;
  level: number | null;
  future: boolean;
  today: boolean;
  description: string;
}
export interface ReadingWidgetHeatColumn { date: string; cells: ReadingWidgetHeatCell[]; }

export function readingWidgetHeatColumns(snapshot: ReadingWidgetSnapshot, weeks: number): ReadingWidgetHeatColumn[] {
  const count = weeks === 7 || weeks === 13 ? weeks : 26;
  const map = widgetHeatmap(snapshot.localDay, snapshot.week, snapshot.heatmap);
  const dates = widgetHeatmapDates(snapshot.localDay);
  const columns: ReadingWidgetHeatColumn[] = [];
  for (let index: number = 182 - count * 7; index < 182; index += 7) {
    const cells: ReadingWidgetHeatCell[] = [];
    for (let offset: number = 0; offset < 7; offset++) {
      const at = index + offset;
      const seconds = map.verifiedSeconds[at];
      const future = dates[at] > snapshot.localDay;
      cells.push({ date: dates[at], level: widgetHeatLevel(seconds), future: future,
        today: dates[at] === snapshot.localDay,
        description: dates[at] + (future ? ' 尚未到来' : seconds === null ? ' 未记录' :
          ' 有效阅读 ' + widgetMinutes(seconds) + ' 分钟') });
    }
    columns.push({ date: dates[index], cells: cells });
  }
  return columns;
}
