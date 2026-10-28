import Foundation

struct ReadingCardQuote: Codable { let id: String; let text: String; let source: String }
struct ReadingCard: Codable {
  let id: String; let name: String; let design: String; let skin: String; let appearance: String
  let showBookDetails: Bool; let hasRecent: Bool; let localDay: String
  var images: [String: String]; let quotes: [ReadingCardQuote]
  var sources: [String: String]? = nil
  var isToday: Bool {
    let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    return localDay == String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
  }
}
enum ReadingCardStore {
  static var file: URL? { ReadingWidgetStore.container?.appendingPathComponent("reading-cards.json") }
  static func read() -> [ReadingCard] {
    guard let file, let data = try? Data(contentsOf: file), let cards = try? JSONDecoder().decode([ReadingCard].self, from: data) else { return [] }
    return cards
  }
  static func cursor(_ instance: String) -> String? {
    guard let root = ReadingWidgetStore.container else { return nil }
    let file = root.appendingPathComponent("reading-card-cursors.json")
    return ((try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String:String].self, from: $0) })?[instance]
  }
  static func next(_ id: String, instance: String) throws {
    guard let root = ReadingWidgetStore.container, let card = read().first(where: { $0.id == id }), card.quotes.count > 1 else { return }
    let file = root.appendingPathComponent("reading-card-cursors.json")
    var values = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String:String].self, from: $0) } ?? [:]
    let index = card.quotes.firstIndex(where: { $0.id == values[instance] }) ?? 0
    values[instance] = card.quotes[(index + 1) % card.quotes.count].id
    try JSONEncoder().encode(values).write(to: file, options: .atomic)
  }
  static func publish(_ input: Any) throws {
    guard let root = ReadingWidgetStore.container, let file else { throw CocoaError(.fileNoSuchFile) }
    let data = try JSONSerialization.data(withJSONObject: input)
    var cards = try JSONDecoder().decode([ReadingCard].self, from: data)
    let previous = read(); let directory = root.appendingPathComponent("reading-cards", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var created: [URL] = []; var retained = Set<String>()
    do {
      for i in cards.indices {
        let old = previous.first { $0.id == cards[i].id }; let incoming = cards[i].images
        for size in ["small", "medium", "large"] { for mode in ["light", "dark"] {
          let key = "\(size)_\(mode)"
          guard let path = incoming[key] else { throw CocoaError(.coderInvalidValue) }
          let source = URL(fileURLWithPath: path).resolvingSymlinksInPath()
          guard source.path.hasPrefix(URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path + "/") else { throw CocoaError(.fileReadNoPermission) }
          if old?.sources?[key] == path, let owned = old?.images[key], FileManager.default.fileExists(atPath: owned) {
            cards[i].images[key] = owned; retained.insert(owned); continue
          }
          let bytes = try Data(contentsOf: source)
          guard bytes.count >= 8, bytes.count <= 2097152 else { throw CocoaError(.coderInvalidValue) }
          let target = directory.appendingPathComponent(UUID().uuidString + ".png")
          try bytes.write(to: target, options: .atomic); created.append(target)
          cards[i].images[key] = target.path; retained.insert(target.path)
        } }
        cards[i].sources = incoming
      }
      try JSONEncoder().encode(cards).write(to: file, options: .atomic)
    } catch { for url in created { try? FileManager.default.removeItem(at: url) }; throw error }
    for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where !retained.contains(url.path) { try? FileManager.default.removeItem(at: url) }
  }
}

struct ReadingWidgetDay: Codable {
  let date: String
  let verifiedSeconds: Int?
}

struct ReadingWidgetCompletion: Codable {
  let completedAt: String
  let finished: Bool
  var bookId: Int?
  var title: String?
  var author: String?
  var coverPath: String?

  var momentCaption: String { finished ? "最近读完" : "读到此刻" }
  var dateCaption: String {
    String(completedAt.prefix(10)).replacingOccurrences(of: "-", with: ".")
      + "  " + (finished ? "读完" : "读到此刻")
  }
}

struct ReadingWidgetSnapshot: Codable {
  let version: Int
  let generatedAt: String
  let localDay: String
  let qualificationSeconds: Int
  let verifiedTotalSeconds: Int?
  let verifiedTodaySeconds: Int?
  let qualifiedStreakDays: Int?
  let week: [ReadingWidgetDay]
  var latestCompletion: ReadingWidgetCompletion?
  let palette: String
  let showBookDetails: Bool
  var themeId: String? = nil
  var layoutId: String? = nil
  var skinId: String? = nil
  var dailyGoalMinutes: Int? = nil
  var heatmap: ReadingWidgetHeatmap? = nil
  var desktopImages: [String: String]? = nil

  var resolvedSkinId: String { ["seasons", "archive", "night", "film", "paper"].contains(skinId ?? "") ? skinId! : "original" }
  var dailyGoal: Int { (1...1440).contains(dailyGoalMinutes ?? 0) ? dailyGoalMinutes! : 0 }
  var goalCaption: String {
    guard dailyGoal > 0 else { return "" }
    guard let seconds = verifiedTodaySeconds else { return "每日目标 \(dailyGoal) 分钟" }
    return seconds >= dailyGoal * 60 ? "今日目标已达成" : "目标 \(dailyGoal) 分 · 还差 \((dailyGoal * 60 - seconds + 59) / 60) 分"
  }

  var resolvedLayoutId: String {
    guard let layoutId, ["focus", "week", "calendar", "memory"].contains(layoutId) else { return "classic" }
    return layoutId
  }
  var designThemeId: String {
    switch resolvedLayoutId {
    case "focus": return "editorial"
    case "week": return "constellation"
    case "calendar": return "shelf"
    case "memory": return "festival"
    default: return resolvedThemeId
    }
  }

  static let empty = ReadingWidgetSnapshot(version: 1, generatedAt: "", localDay: "",
    qualificationSeconds: 300, verifiedTotalSeconds: nil, verifiedTodaySeconds: nil,
    qualifiedStreakDays: nil, week: [], latestCompletion: nil, palette: "cream", showBookDetails: false,
    themeId: "archive")

  /// Additive v1 field: palette-only snapshots migrate to the matching theme.
  var resolvedThemeId: String {
    let value = themeId ?? palette
    switch value {
    case "paper", "cream": return "editorial"
    case "night": return "constellation"
    case "archive", "shelf", "editorial", "constellation", "signal", "score", "ink", "festival": return value
    default: return "archive"
    }
  }

  var weekSeconds: Int? {
    let values = week.compactMap(\.verifiedSeconds)
    return values.isEmpty ? nil : values.reduce(0, +)
  }
  /// Seven rolling natural days ending at localDay, not a calendar week.
  var rollingWeekCaption: String { "近7日 \(Self.minutes(weekSeconds)) 分钟" }
  static func minutes(_ seconds: Int?) -> String {
    guard let value = seconds else { return "—" }
    return value > 0 && value < 60 ? "<1" : "\(value / 60)"
  }
  var isToday: Bool {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date()) == localDay
  }
  var dateCaption: String {
    localDay.isEmpty ? "从这一页开始" : "截至 " + localDay.suffix(5).replacingOccurrences(of: "-", with: ".")
  }

  func heatmapCells(for period: ReadingWidgetHeatmapPeriod) -> [ReadingWidgetHeatmapCell] {
    guard let today = ReadingWidgetCalendar.day(localDay),
      let start = ReadingWidgetCalendar.start(of: today) else {
      return Array(repeating: .unknown, count: period.cellCount)
    }
    var values = Array<Int?>(repeating: nil, count: 182)
    if let heatmap, heatmap.isValid, heatmap.startDate == ReadingWidgetCalendar.string(start) {
      values = heatmap.verifiedSeconds
    } else {
      // A legacy snapshot only knows its explicitly dated seven-day records.
      for day in week {
        guard let date = ReadingWidgetCalendar.day(day.date), date <= today,
          let index = ReadingWidgetCalendar.calendar.dateComponents([.day], from: start, to: date).day,
          values.indices.contains(index), day.verifiedSeconds.map({ $0 >= 0 }) ?? true else { continue }
        values[index] = day.verifiedSeconds
      }
    }
    return (182 - period.cellCount..<182).map { index in
      let date = ReadingWidgetCalendar.calendar.date(byAdding: .day, value: index, to: start)!
      let future = date > today
      return ReadingWidgetHeatmapCell(date: ReadingWidgetCalendar.string(date),
        seconds: future ? nil : values[index], isFuture: future, isToday: date == today)
    }
  }
}

extension ReadingWidgetSnapshot {
  private enum CodingKeys: String, CodingKey {
    case version, generatedAt, localDay, qualificationSeconds, verifiedTotalSeconds,
      verifiedTodaySeconds, qualifiedStreakDays, week, latestCompletion, palette,
      showBookDetails, themeId, layoutId, skinId, dailyGoalMinutes, heatmap, desktopImages
  }
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(Int.self, forKey: .version)
    generatedAt = try container.decode(String.self, forKey: .generatedAt)
    localDay = try container.decode(String.self, forKey: .localDay)
    qualificationSeconds = try container.decode(Int.self, forKey: .qualificationSeconds)
    verifiedTotalSeconds = try container.decodeIfPresent(Int.self, forKey: .verifiedTotalSeconds)
    verifiedTodaySeconds = try container.decodeIfPresent(Int.self, forKey: .verifiedTodaySeconds)
    qualifiedStreakDays = try container.decodeIfPresent(Int.self, forKey: .qualifiedStreakDays)
    week = try container.decode([ReadingWidgetDay].self, forKey: .week)
    latestCompletion = try container.decodeIfPresent(ReadingWidgetCompletion.self, forKey: .latestCompletion)
    palette = try container.decode(String.self, forKey: .palette)
    showBookDetails = try container.decode(Bool.self, forKey: .showBookDetails)
    themeId = try container.decodeIfPresent(String.self, forKey: .themeId)
    layoutId = try? container.decode(String.self, forKey: .layoutId)
    skinId = try? container.decode(String.self, forKey: .skinId)
    dailyGoalMinutes = try? container.decode(Int.self, forKey: .dailyGoalMinutes)
    // An invalid additive block must not discard otherwise usable v1 data.
    heatmap = try? container.decode(ReadingWidgetHeatmap.self, forKey: .heatmap)
    desktopImages = try? container.decode([String: String].self, forKey: .desktopImages)
  }
}

enum ReadingWidgetHeatmapPeriod: Int, CaseIterable {
  case small = 7, medium = 13, large = 26
  var cellCount: Int { rawValue * 7 }
  var caption: String { "近\(rawValue)周" }
}

struct ReadingWidgetHeatmap: Codable {
  let startDate: String
  let weekStart: Int
  let verifiedSeconds: [Int?]
  var isValid: Bool {
    guard weekStart == 1, verifiedSeconds.count == 182,
      verifiedSeconds.allSatisfy({ $0.map({ $0 >= 0 }) ?? true }),
      let start = ReadingWidgetCalendar.day(startDate) else { return false }
    return ReadingWidgetCalendar.calendar.component(.weekday, from: start) == 2
  }
}

struct ReadingWidgetHeatmapCell: Equatable {
  let date: String?
  let seconds: Int?
  let isFuture: Bool
  let isToday: Bool
  static let unknown = ReadingWidgetHeatmapCell(date: nil, seconds: nil, isFuture: false, isToday: false)
  var level: Int? {
    guard !isFuture, let seconds, seconds >= 0 else { return nil }
    switch seconds {
    case 0: return 0
    case 1..<900: return 1
    case 900..<1800: return 2
    case 1800..<3600: return 3
    default: return 4
    }
  }
}

/// Civil dates are parsed in a fixed Gregorian calendar, never elapsed 24-hour
/// intervals or the host's current timezone. The snapshot owns the meaning of today.
enum ReadingWidgetCalendar {
  static let calendar: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.locale = Locale(identifier: "en_US_POSIX")
    value.timeZone = TimeZone(secondsFromGMT: 0)!
    value.firstWeekday = 2
    return value
  }()
  static func day(_ value: String) -> Date? {
    let bytes = Array(value.utf8)
    guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
      bytes.enumerated().allSatisfy({ [4, 7].contains($0.offset) || (48...57).contains($0.element) }) else { return nil }
    let parts = value.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, parts[0] >= 1,
      let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
      string(date) == value else { return nil }
    return date
  }
  static func string(_ date: Date) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
  }
  static func start(of today: Date) -> Date? {
    let mondayOffset = (calendar.component(.weekday, from: today) + 5) % 7
    return calendar.date(byAdding: .day, value: -mondayOffset - 25 * 7, to: today)
  }
}

enum ReadingWidgetStore {
  static let filename = "reading-snapshot-v1.json"
  static var group: String? { Bundle.main.object(forInfoDictionaryKey: "WenkuWidgetAppGroup") as? String }
  static var container: URL? {
    guard let group, !group.isEmpty else { return nil }
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
  }
  static func read() -> ReadingWidgetSnapshot {
    guard let file = container?.appendingPathComponent(filename),
      let bytes = try? Data(contentsOf: file),
      let snapshot = try? JSONDecoder().decode(ReadingWidgetSnapshot.self, from: bytes),
      snapshot.version == 1, snapshot.week.count == 7 else { return .empty }
    return snapshot
  }
}
