import SwiftUI
import WidgetKit
import AppIntents

struct ReadingEntry: TimelineEntry {
  let date: Date
  let snapshot: ReadingWidgetSnapshot
}

struct ReadingTimeline: TimelineProvider {
  func placeholder(in context: Context) -> ReadingEntry { ReadingEntry(date: Date(), snapshot: .empty) }
  func getSnapshot(in context: Context, completion: @escaping (ReadingEntry) -> Void) {
    completion(ReadingEntry(date: Date(), snapshot: ReadingWidgetStore.read()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<ReadingEntry>) -> Void) {
    let now = Date()
    let midnight = Calendar.current.startOfDay(for: now)
    let next = Calendar.current.date(byAdding: .day, value: 1, to: midnight) ?? now.addingTimeInterval(86400)
    completion(Timeline(entries: [ReadingEntry(date: now, snapshot: ReadingWidgetStore.read())], policy: .after(next)))
  }
}

struct ReadingWidgetView: View {
  @Environment(\.widgetFamily) var family
  let entry: ReadingEntry
  var theme: ReadingWidgetTheme { ReadingWidgetTheme(rawValue: entry.snapshot.designThemeId) ?? .archive }
  var link: URL? {
    guard let scheme = Bundle.main.object(forInfoDictionaryKey: "WenkuWidgetScheme") as? String else { return nil }
    return URL(string: "\(scheme)://reading/\(entry.snapshot.resolvedLayoutId == "memory" || entry.snapshot.resolvedLayoutId == "classic" && family == .systemLarge ? "moments" : "statistics")")
  }
  var body: some View {
    let background = entry.snapshot.resolvedLayoutId == "classic" ? theme.background :
      ReadingWidgetSkin(id: entry.snapshot.resolvedSkinId, date: entry.snapshot.localDay, fallback: theme).background
    if #available(iOS 17.0, macOS 14.0, *) {
      face.containerBackground(background, for: .widget)
    } else { face.background(background) }
  }
  var face: some View { ReadingWidgetFace(data: entry.snapshot, family: family).widgetURL(link) }
}

/// Offscreen reviews render this same production view and its native typography.
struct ReadingWidgetFace: View {
  let data: ReadingWidgetSnapshot
  let family: WidgetFamily
  var rendered: UIImage? {
    guard data.resolvedLayoutId != "classic", let root = ReadingWidgetStore.container,
      let path = data.desktopImages?[family == .systemSmall ? "small" : family == .systemMedium ? "medium" : "large"],
      URL(fileURLWithPath: path).deletingLastPathComponent() == root.appendingPathComponent("reading-desktop", isDirectory: true) else { return nil }
    return UIImage(contentsOfFile: path)
  }
  var body: some View {
    Group {
      if let image = rendered {
        ZStack(alignment: .bottomTrailing) {
          Image(uiImage: image).resizable()
            .accessibilityLabel("轻小说文库，阅读 \(ReadingWidgetSnapshot.minutes(data.verifiedTodaySeconds)) 分钟。\(data.dateCaption)")
          if !data.isToday {
            Text(data.dateCaption).font(.system(size: 10)).foregroundColor(.white).padding(3)
              .background(Color.black.opacity(0.8)).cornerRadius(3).padding(10)
          }
        }
      } else if data.resolvedLayoutId == "classic" { ReadingArtworkWidgetFace(data: data, family: family) }
      else { ReadingContentWidgetFace(data: data, family: family) }
    }.accessibilityElement(children: .combine)
  }
}

#if !READING_WIDGET_PREVIEW
@main
#endif
struct ReadingWidgetsBundle: WidgetBundle {
  var body: some Widget {
    if #available(iOS 17.0, macOS 14.0, *) { return WidgetBundleBuilder.buildBlock(ReadingConfiguredWidget()) }
    else { return ReadingQuietWidget() }
  }
}

struct ReadingQuietWidget: Widget {
  let kind = "ReadingQuiet"
  var configuration: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ReadingTimeline()) { ReadingWidgetView(entry: $0) }
      .configurationDisplayName("阅读留白")
      .description("此刻的阅读日、近七日的节律，和一本读过的余韵。")
      .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
  var body: some WidgetConfiguration { configuration }
}

@available(iOS 17.0, macOS 14.0, *)
struct ReadingConfiguredWidget: Widget {
  let kind = "ReadingQuiet"
  var body: some WidgetConfiguration {
      AppIntentConfiguration(kind: kind, intent: ReadingCardIntent.self, provider: ReadingCardTimeline()) { ReadingConfiguredCard(entry: $0) }
        .configurationDisplayName("轻小说文库")
        .description("选择今日阅读、阅读纪念或摘录，每张卡片独立设置。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
  }
}

@available(iOS 17.0, macOS 14.0, *)
struct ReadingCardEntity: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "桌面内容"
  static var defaultQuery = ReadingCardQuery()
  var id: String; var name: String
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
@available(iOS 17.0, macOS 14.0, *)
struct ReadingCardQuery: EntityQuery {
  func entities(for identifiers: [String]) async throws -> [ReadingCardEntity] {
    ReadingCardStore.read().filter { identifiers.contains($0.id) }.map { ReadingCardEntity(id: $0.id, name: $0.name) }
  }
  func suggestedEntities() async throws -> [ReadingCardEntity] { ReadingCardStore.read().map { ReadingCardEntity(id: $0.id, name: $0.name) } }
  func defaultResult() async -> ReadingCardEntity? { ReadingCardStore.read().first.map { ReadingCardEntity(id: $0.id, name: $0.name) } }
}
@available(iOS 17.0, macOS 14.0, *)
struct ReadingCardIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "小组件"
  @Parameter(title: "桌面内容") var card: ReadingCardEntity?
  @Parameter(title: "实例标识") var instance: String
  static var parameterSummary: some ParameterSummary { Summary("显示 \(\.$card)") }
  init() { instance = UUID().uuidString }
}
@available(iOS 17.0, macOS 14.0, *)
struct ReadingCardNext: AppIntent {
  static var title: LocalizedStringResource = "换一条摘录"
  static var openAppWhenRun = false
  @Parameter(title: "卡片") var cardID: String
  @Parameter(title: "实例") var instance: String
  init() {}
  init(cardID: String, instance: String) { self.cardID = cardID; self.instance = instance }
  func perform() async throws -> some IntentResult {
    try ReadingCardStore.next(cardID, instance: instance)
    WidgetCenter.shared.reloadTimelines(ofKind: "ReadingQuiet")
    return .result()
  }
}
@available(iOS 17.0, macOS 14.0, *)
struct ReadingCardEntry: TimelineEntry { let date: Date; let card: ReadingCard?; let instance: String; let quote: ReadingCardQuote? }
@available(iOS 17.0, macOS 14.0, *)
struct ReadingCardTimeline: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> ReadingCardEntry { ReadingCardEntry(date: Date(), card: nil, instance: "", quote: nil) }
  func snapshot(for configuration: ReadingCardIntent, in context: Context) async -> ReadingCardEntry { entry(configuration) }
  func timeline(for configuration: ReadingCardIntent, in context: Context) async -> Timeline<ReadingCardEntry> {
    let now = Date()
    let next = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
    return Timeline(entries: [entry(configuration)], policy: .after(next))
  }
  private func entry(_ intent: ReadingCardIntent) -> ReadingCardEntry {
    let cards = ReadingCardStore.read(); let card = cards.first { $0.id == intent.card?.id } ?? cards.first
    let selected = ReadingCardStore.cursor(intent.instance)
    let quote = card?.quotes.first { $0.id == selected } ?? card?.quotes.first
    return ReadingCardEntry(date: Date(), card: card, instance: intent.instance, quote: quote)
  }
}
@available(iOS 17.0, macOS 14.0, *)
struct ReadingConfiguredCard: View {
  let entry: ReadingCardEntry
  @Environment(\.widgetFamily) var family
  @Environment(\.colorScheme) var scheme
  func link(_ destination: String) -> URL? {
    guard let scheme = Bundle.main.object(forInfoDictionaryKey: "WenkuWidgetScheme") as? String else { return nil }
    return URL(string: "\(scheme)://reading/\(destination)")
  }
  var body: some View {
    Group {
      if let card = entry.card {
        let small = family == .systemSmall, large = family == .systemLarge
        let mode = card.appearance == "system" ? (scheme == .dark ? "dark" : "light") : card.appearance
        let size = small ? "small" : large ? "large" : "medium"
        GeometryReader { geometry in
          let sx = geometry.size.width / (small ? 170 : 364)
          let sy = geometry.size.height / (large ? 382 : 170)
          ZStack(alignment: .bottomTrailing) {
            if let path = card.images["\(size)_\(mode)"], let root = ReadingWidgetStore.container,
              URL(fileURLWithPath: path).deletingLastPathComponent() == root.appendingPathComponent("reading-cards", isDirectory: true),
              let image = UIImage(contentsOfFile: path) { Image(uiImage: image).resizable() }
            if card.design == "quote" {
              VStack(alignment: .leading, spacing: 6) {
                Text(entry.quote?.text ?? "在阅读中留下喜欢的句子").font(.system(size: (large ? 20 : small ? 14 : 16) * sx, weight: .semibold, design: .serif)).lineLimit(3)
                Spacer(minLength: 0)
                if let source = entry.quote?.source, !source.isEmpty { Text(source).font(.system(size: 10 * sx)).lineLimit(1).opacity(0.7) }
              }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(mode == "dark" ? Color(red: 0.95, green: 0.94, blue: 0.91) : Color(red: 0.13, green: 0.14, blue: 0.16))
                .padding(.leading, (small || large ? 16 : 30) * sx).padding(.trailing, 16 * sx)
                .padding(.top, (large ? 230 : small ? 62 : 50) * sy).padding(.bottom, (large ? 44 : 36) * sy)
              if large && !card.quotes.isEmpty { HStack { Text("共 \(card.quotes.count) 条摘录").font(.system(size: 11)).foregroundStyle(mode == "dark" ? Color.white.opacity(0.7) : Color.black.opacity(0.6)); Spacer() }.padding(.leading, 16).padding(.bottom, 20) }
              if card.quotes.count > 1 {
                Button(intent: ReadingCardNext(cardID: card.id, instance: entry.instance)) { Label("换一条", systemImage: "arrow.clockwise").font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 5).background(Color(red: 0.28, green: 0.49, blue: 0.47), in: Capsule()).frame(width: 80, height: 44) }
                  .buttonStyle(.plain).foregroundStyle(Color.white)
              }
            }
            if large && card.hasRecent, let url = link("continue") {
              Link(destination: url) { Color.clear.frame(height: 54 * sy).contentShape(Rectangle()) }.accessibilityLabel("继续上次阅读")
            }
            if card.design != "quote" && !card.isToday {
              Text("截至 " + card.localDay.replacingOccurrences(of: "-", with: ".")).font(.system(size: 10)).foregroundStyle(.white).padding(3)
                .background(Color.black.opacity(0.8)).cornerRadius(3).padding(10).allowsHitTesting(false)
            }
          }
        }.widgetURL(link(card.design == "memory" ? "moments" : card.design == "quote" ? "excerpts" : "statistics"))
      } else { Text("打开轻小说文库，设置桌面内容").padding() }
    }.containerBackground(for: .widget) { Color.clear }
  }
}
