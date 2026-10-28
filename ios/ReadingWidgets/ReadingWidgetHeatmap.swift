import SwiftUI

/// Static, level-batched paths: no per-day view tree, timer, or image decoding.
struct ReadingWidgetHeatmapView: View {
  let data: ReadingWidgetSnapshot
  let theme: ReadingWidgetTheme
  let period: ReadingWidgetHeatmapPeriod
  var gridHeight: CGFloat = 49
  var showLegend = false
  var trailingCaption: String? = nil
  var skin: ReadingWidgetSkin? = nil

  var body: some View {
    let theme = skin ?? ReadingWidgetSkin(id: "original", date: data.localDay, fallback: self.theme)
    let cells = data.heatmapCells(for: period)
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(period.caption).font(.system(size: 9, weight: .medium))
        if let trailingCaption {
          Spacer(minLength: 1)
          Text(trailingCaption).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.85)
        }
      }.foregroundColor(theme.muted)
      HStack(spacing: 3) {
        VStack(spacing: 0) {
          ForEach(0..<7) { row in
            Text(["一", "", "三", "", "五", "", "日"][row])
              .font(.system(size: 7)).foregroundColor(theme.muted)
              .frame(height: gridHeight / 7)
          }
        }.frame(width: 8, height: gridHeight)
        ZStack {
          ForEach(0..<5) { level in
            ReadingHeatmapDots(cells: cells, columns: period.rawValue, layer: level)
              .fill(theme.heatmapColor(level))
          }
          ReadingHeatmapDots(cells: cells, columns: period.rawValue, layer: -1)
            .stroke(theme.muted.opacity(0.42), lineWidth: 0.65)
          ReadingHeatmapDots(cells: cells, columns: period.rawValue, layer: -2)
            .stroke(theme.accent, lineWidth: 0.9)
        }
      }.frame(height: gridHeight)
      if showLegend {
        HStack(spacing: 8) {
          ForEach(0..<5) { level in
            HStack(spacing: 3) {
              Circle().fill(theme.heatmapColor(level)).frame(width: 5, height: 5)
              Text(["0", "<15", "15", "30", "60+"][level])
            }
          }
          Text("分钟")
          Spacer(minLength: 0)
          Circle().stroke(theme.muted.opacity(0.6), lineWidth: 0.65).frame(width: 5, height: 5)
          Text("未记录")
        }.font(.system(size: 8)).foregroundColor(theme.muted).padding(.top, 1)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(period.caption)阅读热图，周一至周日，\(cells.filter { $0.level != nil }.count)天有记录；颜色表示每天有效阅读分钟")
  }
}

/// layer -1 = unknown outline; -2 = today's ring; 0...4 = fixed measured levels.
struct ReadingHeatmapDots: Shape {
  let cells: [ReadingWidgetHeatmapCell]
  let columns: Int
  let layer: Int

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let dx = rect.width / CGFloat(columns)
    let dy = rect.height / 7
    let step = min(dx, dy)
    let diameter = max(1, step * 0.64)
    // Ring plus half its stroke must stay inside every cell, including Mon/Sun.
    let ring = max(1, min(diameter + 2, step - 1.0))
    for (index, cell) in cells.enumerated() where !cell.isFuture {
      let include = layer == -2 ? cell.isToday : layer == -1 ? cell.level == nil : cell.level == layer
      guard include else { continue }
      let size = layer == -2 ? ring : diameter
      path.addEllipse(in: CGRect(x: rect.minX + (CGFloat(index / 7) + 0.5) * dx - size / 2,
        y: rect.minY + (CGFloat(index % 7) + 0.5) * dy - size / 2, width: size, height: size))
    }
    return path
  }
}

/// The existing rolling-seven-day rhythm stays separate from calendar heatmaps.
struct ReadingWidgetWeekRhythm: View {
  let data: ReadingWidgetSnapshot
  let theme: ReadingWidgetTheme
  private var days: [ReadingWidgetDay] {
    let recorded = Array(data.week.suffix(7))
    return Array(repeating: ReadingWidgetDay(date: "", verifiedSeconds: nil), count: 7 - recorded.count) + recorded
  }
  private func weekday(_ day: ReadingWidgetDay) -> String {
    guard let date = ReadingWidgetCalendar.day(day.date) else { return "—" }
    return ["日", "一", "二", "三", "四", "五", "六"][ReadingWidgetCalendar.calendar.component(.weekday, from: date) - 1]
  }
  var body: some View {
    let days = days
    let maximum = max(1, days.compactMap(\.verifiedSeconds).max() ?? 1)
    HStack(alignment: .bottom, spacing: 4) {
      ForEach(0..<7) { index in
        VStack(spacing: 1) {
          Group {
            if let value = days[index].verifiedSeconds {
              Rectangle().fill(value == 0 ? theme.secondary.opacity(0.6) : theme.accent.opacity(0.8))
                .frame(height: max(1, CGFloat(max(0, value)) / CGFloat(maximum) * 11))
            } else {
              Rectangle().stroke(theme.muted.opacity(0.5), lineWidth: 0.6).frame(height: 1)
            }
          }.frame(maxWidth: .infinity, minHeight: 11, maxHeight: 11, alignment: .bottom)
          Text(weekday(days[index])).font(.system(size: 7)).foregroundColor(theme.muted)
        }
      }
    }.frame(height: 21)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("近七日阅读节律，" + days.map { "\($0.date)，\(ReadingWidgetSnapshot.minutes($0.verifiedSeconds))分钟" }.joined(separator: "；"))
  }
}
