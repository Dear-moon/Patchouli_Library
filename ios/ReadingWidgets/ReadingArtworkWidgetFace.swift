import SwiftUI
import WidgetKit

/// Content leads the composition. No empty metrics or decorative placeholder charts.
struct ReadingContentWidgetFace: View {
  let data: ReadingWidgetSnapshot
  let family: WidgetFamily
  var theme: ReadingWidgetSkin { ReadingWidgetSkin(id: data.resolvedSkinId, date: data.localDay, fallback: ReadingWidgetTheme(rawValue: data.designThemeId) ?? .editorial) }
  var period: ReadingWidgetHeatmapPeriod { family == .systemSmall ? .small : family == .systemMedium ? .medium : .large }
  var illustrated: Bool { data.resolvedLayoutId == "focus" && data.resolvedSkinId == "seasons" && family != .systemSmall }
  var body: some View {
    Group {
      if illustrated {
        if family == .systemLarge {
          VStack(spacing: 0) { seasonArt.frame(height: 126); VStack(alignment: .leading, spacing: 8) { focus }.padding(16) }
        } else {
          HStack(spacing: 0) { seasonArt.frame(width: 116); VStack(alignment: .leading, spacing: 7) { focus }.padding(16) }
        }
      } else { content }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(ReadingWidgetSkinBackground(skin: theme)).foregroundColor(theme.foreground).clipped()
  }
  var seasonArt: some View {
    GeometryReader { geometry in
      if let art = ReadingWidgetResources.season(theme.season) {
        let scale = max(geometry.size.width / 720, geometry.size.height / 405)
        let width = 720 * scale; let height = 405 * scale
        art.resizable().frame(width: width, height: height)
          .offset(x: -(width - geometry.size.width) * 0.8, y: -(height - geometry.size.height) * 0.15)
      }
    }.clipped().accessibilityHidden(true)
  }
  var content: some View {
    VStack(alignment: .leading, spacing: data.resolvedLayoutId == "calendar" ? 4 : 8) {
      switch data.resolvedLayoutId {
      case "focus": focus
      case "week": week
      case "calendar": calendar
      default: memory
      }
    }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(ReadingWidgetSkinBackground(skin: theme)).foregroundColor(theme.foreground).clipped()
  }
  func caption(_ text: String) -> some View {
    Text(text).font(.system(size: 10)).foregroundColor(theme.muted).lineLimit(1).minimumScaleFactor(0.8)
  }
  var focus: some View {
    Group {
      caption(data.localDay.isEmpty ? "今日阅读" : String(data.localDay.suffix(5)).replacingOccurrences(of: "-", with: ".") + " / 阅读")
      Spacer(minLength: 0)
      if let seconds = data.verifiedTodaySeconds {
        Text(ReadingWidgetSnapshot.minutes(seconds)).font(ReadingWidgetResources.number(family == .systemLarge ? (illustrated ? 64 : 76) : (illustrated ? 44 : 48)))
          .foregroundColor(data.resolvedSkinId == "original" ? theme.foreground : theme.accent)
          .lineLimit(1).minimumScaleFactor(0.5)
        caption("分钟")
      }
      Spacer(minLength: 0)
      if data.dailyGoal > 0 {
        if let seconds = data.verifiedTodaySeconds {
          GeometryReader { geometry in
            ZStack(alignment: .leading) {
              Capsule().fill(theme.secondary)
              Capsule().fill(theme.accent).frame(width: geometry.size.width * min(1, CGFloat(seconds) / CGFloat(data.dailyGoal * 60)))
            }
          }.frame(height: 4)
        }
        caption(data.goalCaption)
      } else { Rectangle().fill(theme.secondary).frame(height: 1) }
      caption((data.qualifiedStreakDays ?? 0) > 0 ? "连续 \(data.qualifiedStreakDays!) 天" : data.dateCaption)
    }
  }
  var week: some View {
    Group {
      caption("近七日 / READING RHYTHM")
      if let seconds = data.weekSeconds {
        Text(ReadingWidgetSnapshot.minutes(seconds) + " 分钟").font(ReadingWidgetResources.number(32))
          .lineLimit(1).minimumScaleFactor(0.6)
        GeometryReader { geometry in
          let maximum = max(300, data.week.compactMap(\.verifiedSeconds).max() ?? 0)
          HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(data.week.enumerated()), id: \.offset) { index, day in
              VStack(spacing: 5) {
                Spacer(minLength: 0)
                if let seconds = day.verifiedSeconds {
                  RoundedRectangle(cornerRadius: 2).fill(theme.accent.opacity(index == 6 ? 1 : 0.55))
                    .frame(height: max(2, (geometry.size.height - 18) * CGFloat(seconds) / CGFloat(maximum)))
                } else {
                  RoundedRectangle(cornerRadius: 2).stroke(theme.secondary, lineWidth: 1).frame(height: 3)
                }
                caption(String(day.date.suffix(2)))
              }.frame(maxWidth: .infinity)
                .accessibilityLabel("\(day.date)：\(day.verifiedSeconds.map { ReadingWidgetSnapshot.minutes($0) + " 分钟" } ?? "未记录")")
            }
          }
        }.frame(maxHeight: .infinity)
      } else { Spacer(minLength: 0) }
      caption(data.dateCaption)
    }
  }
  var calendar: some View {
    Group {
      caption("阅读日历")
      if !data.localDay.isEmpty {
        Text(String(data.localDay.prefix(7)).replacingOccurrences(of: "-", with: " / "))
          .font(ReadingWidgetResources.number(23))
      }
      Spacer(minLength: 0)
      if data.heatmapCells(for: period).contains(where: { $0.seconds != nil }) {
        ReadingWidgetHeatmapView(data: data, theme: theme.fallback, period: period,
          gridHeight: family == .systemLarge ? 126 : 30, showLegend: false, skin: theme)
      }
      Spacer(minLength: 0)
      caption(data.dateCaption)
    }
  }
  var memory: some View {
    Group {
      caption(data.latestCompletion == nil ? "下一段故事" : "书页留念")
      Spacer(minLength: 0)
      HStack(alignment: .center, spacing: 10) {
        VStack(alignment: .leading, spacing: 8) {
          Text(data.showBookDetails && !(data.latestCompletion?.title ?? "").isEmpty
            ? data.latestCompletion!.title! : data.latestCompletion == nil ? "从这一页\n开始。" :
              data.latestCompletion!.finished ? "每一页，\n都算数。" : "故事未完，\n阅读继续。")
            .font(.system(size: family == .systemSmall ? 18 : 23, weight: .semibold, design: .serif))
            .lineLimit(2).minimumScaleFactor(0.65).fixedSize(horizontal: false, vertical: true)
          if data.showBookDetails, let author = data.latestCompletion?.author, !author.isEmpty { caption(author) }
        }.frame(maxWidth: .infinity, alignment: .leading)
        if data.showBookDetails, let path = data.latestCompletion?.coverPath, let cover = readingWidgetCover(at: path) {
          cover.resizable().scaledToFit().frame(width: 45, height: 68).accessibilityHidden(true)
        }
      }
      Spacer(minLength: 0)
      Rectangle().fill(theme.accent).frame(height: 3)
      caption(data.latestCompletion?.dateCaption ?? data.dateCaption)
    }
  }
}

struct ReadingWidgetArtwork: View {
  let theme: ReadingWidgetTheme
  var alignment: Alignment = .center
  var body: some View {
    GeometryReader { geometry in
      if let image = ReadingWidgetResources.artwork(theme) {
        image.resizable().scaledToFill()
          .frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment).clipped()
      }
    }.accessibilityHidden(true)
  }
}

struct ReadingArtworkWidgetFace: View {
  let data: ReadingWidgetSnapshot
  let family: WidgetFamily
  var theme: ReadingWidgetTheme { ReadingWidgetTheme(rawValue: data.resolvedThemeId) ?? .archive }
  var date: String { data.localDay.isEmpty ? "尚未记录" : String(data.localDay.suffix(5)).replacingOccurrences(of: "-", with: ".") }
  var todayCaption: String { "\(date) · \(ReadingWidgetSnapshot.minutes(data.verifiedTodaySeconds)) 分钟" }
  var completion: ReadingWidgetCompletion? { data.latestCompletion }
  var bookTitle: String {
    if data.showBookDetails, let title = completion?.title, !title.isEmpty { return title }
    return completion == nil ? "下一段故事" : "与故事相伴"
  }
  var momentLabel: String { completion?.momentCaption ?? "尚无阅读纪念" }
  var completionDate: String { completion?.dateCaption ?? "截至 \(date)" }

  var body: some View {
    Group {
      if family == .systemSmall { small }
      else if family == .systemMedium { medium }
      else { large }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(theme.background).foregroundColor(theme.foreground).clipped()
  }
  func count(_ size: CGFloat, unitSize: CGFloat = 10) -> some View {
    (Text(data.qualifiedStreakDays.map(String.init) ?? "—").font(ReadingWidgetResources.number(size))
      + Text(" 天").font(.system(size: unitSize)))
      .lineLimit(1).minimumScaleFactor(0.4)
      .accessibilityLabel("连续有效阅读 \(data.qualifiedStreakDays.map(String.init) ?? "未测量") 天")
  }
  func label(_ text: String, size: CGFloat = 10) -> some View {
    Text(text).font(.system(size: size)).foregroundColor(theme.muted).lineLimit(1)
  }
  func heading(_ size: CGFloat = 11) -> some View {
    Text(theme.label).font(theme.heading(size)).foregroundColor(theme.foreground).lineLimit(1)
  }
  func today(_ size: CGFloat = 9) -> some View {
    Text(todayCaption).font(.system(size: size)).foregroundColor(theme.muted)
      .lineLimit(1).minimumScaleFactor(0.85)
  }
  func heatmap(_ period: ReadingWidgetHeatmapPeriod, height: CGFloat = 49, legend: Bool = false,
               week: Bool = false) -> some View {
    ReadingWidgetHeatmapView(data: data, theme: theme, period: period, gridHeight: height,
      showLegend: legend, trailingCaption: week ? data.rollingWeekCaption : nil)
  }
  var rule: some View { Rectangle().fill(theme.secondary).frame(height: 1) }

  // Normal identities put measured data before their supporting art.
  @ViewBuilder var small: some View {
    switch theme {
    case .archive: archiveSmall
    case .shelf: shelfSmall
    case .editorial: editorialSmall
    case .constellation, .signal, .ink: portraitSmall
    case .score, .festival: stripSmall
    }
  }
  var archiveSmall: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack { heading(); Spacer(); Rectangle().fill(theme.accent).frame(width: 18, height: 2) }
      HStack(alignment: .lastTextBaseline, spacing: 8) {
        count(37); Spacer(minLength: 0); label("连续阅读", size: 9)
      }.frame(height: 35)
      HStack(alignment: .bottom, spacing: 4) {
        heatmap(.small, height: 44)
        ReadingWidgetArtwork(theme: theme, alignment: .trailing).frame(width: 38, height: 54)
      }
      today()
    }.padding(12)
  }
  var shelfSmall: some View {
    VStack(alignment: .leading, spacing: 5) {
      heading()
      HStack(alignment: .top, spacing: 7) {
        VStack(alignment: .leading, spacing: 2) {
          label("连续阅读", size: 9)
          count(35).frame(height: 37, alignment: .leading)
        }.frame(width: 52, alignment: .leading)
        heatmap(.small, height: 45)
      }
      rule; today()
      ReadingWidgetArtwork(theme: theme, alignment: .trailing).frame(height: 24)
    }.padding(12)
  }
  var editorialSmall: some View {
    HStack(spacing: 9) {
      Rectangle().fill(theme.accent).frame(width: 2)
      VStack(alignment: .leading, spacing: 4) {
        heading()
        HStack(alignment: .bottom, spacing: 6) {
          VStack(alignment: .leading, spacing: 0) {
            count(36).frame(height: 37, alignment: .leading); label("连续阅读", size: 8)
          }
          Spacer(minLength: 0)
          ReadingWidgetArtwork(theme: theme, alignment: .trailing).frame(width: 38, height: 42)
        }
        heatmap(.small, height: 42); today()
      }
    }.padding(12)
  }
  // Portraits retain a right-hand silhouette; chart text has a quiet paper field.
  var portraitSmall: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        ReadingWidgetArtwork(theme: theme)
        if theme == .signal {
          ReadingTicketShape().fill(theme.background).frame(width: geometry.size.width * 0.65)
        } else {
          LinearGradient(stops: [.init(color: theme.background, location: 0),
            .init(color: theme.background.opacity(0.97), location: 0.54),
            .init(color: .clear, location: 0.81)], startPoint: .leading, endPoint: .trailing)
        }
        VStack(alignment: .leading, spacing: 3) {
          heading(10)
          count(35, unitSize: 9).frame(height: 36, alignment: .leading)
          label("连续阅读", size: 8)
          heatmap(.small, height: 42)
          Text(todayCaption).font(.system(size: 8)).foregroundColor(theme.muted)
            .lineLimit(1).minimumScaleFactor(0.85)
        }.frame(width: geometry.size.width * 0.52, alignment: .leading).padding(11)
        if theme == .ink {
          Rectangle().fill(theme.accent).frame(width: 2, height: 21)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(11)
        }
      }
    }
  }
  var stripSmall: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .topLeading) {
        ReadingWidgetArtwork(theme: theme, alignment: .top)
        LinearGradient(colors: [theme.background.opacity(0.96), .clear], startPoint: .leading, endPoint: .trailing)
        VStack(alignment: .leading, spacing: 1) {
          heading(10); count(34).frame(height: 36, alignment: .leading); label("连续阅读", size: 8)
        }.frame(width: 75, alignment: .leading).padding(.horizontal, 12).padding(.top, 8)
      }.frame(height: 72)
      VStack(alignment: .leading, spacing: 3) {
        heatmap(.small, height: 43); today()
      }.padding(.horizontal, 12).padding(.top, 5).padding(.bottom, 9).background(theme.background)
    }
  }

  @ViewBuilder var medium: some View {
    if !theme.isAcg { normalMedium }
    else if theme == .score { scoreMedium }
    else { portraitMedium }
  }
  var normalMedium: some View {
    HStack(spacing: theme == .shelf ? 14 : 18) {
      if theme == .shelf { mediumChart }
      VStack(alignment: .leading, spacing: 3) {
        heading(12); count(47).frame(height: 49, alignment: .leading); label("连续阅读")
        Spacer(minLength: 0); today()
      }.frame(width: 94, alignment: .leading)
      if theme != .shelf {
        Rectangle().fill(theme == .editorial ? theme.accent : theme.secondary).frame(width: theme == .editorial ? 2 : 1)
        mediumChart
      }
    }.padding(15)
  }
  var mediumChart: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .center, spacing: 3) {
        Text(data.rollingWeekCaption).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
        Spacer(minLength: 0)
        ReadingWidgetArtwork(theme: theme, alignment: .trailing).frame(width: 34, height: 20)
      }
      heatmap(.medium, height: 44)
      ReadingWidgetWeekRhythm(data: data, theme: theme)
      label("截至 \(date)", size: 9)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  var portraitMedium: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        ReadingWidgetArtwork(theme: theme, alignment: .top)
        if theme == .festival || theme == .signal {
          ReadingTicketShape().fill(theme.background).frame(width: geometry.size.width * 0.6)
        } else {
          LinearGradient(stops: [.init(color: theme.background, location: 0),
            .init(color: theme.background.opacity(0.98), location: 0.49),
            .init(color: .clear, location: 0.69)], startPoint: .leading, endPoint: .trailing)
        }
        mediumSummary.frame(width: geometry.size.width * 0.51, alignment: .leading).padding(13)
      }
    }
  }
  var mediumSummary: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack { heading(11); Spacer(minLength: 0) }
      HStack(alignment: .center, spacing: 8) {
        count(32).frame(height: 32, alignment: .leading)
        VStack(alignment: .leading, spacing: 3) { label("连续阅读", size: 9); today(8) }
      }
      heatmap(.medium, height: 43, week: true)
      ReadingWidgetWeekRhythm(data: data, theme: theme)
    }
  }
  var scoreMedium: some View {
    HStack(spacing: 0) {
      ReadingWidgetArtwork(theme: theme, alignment: .trailing).frame(width: 118)
      mediumSummary.padding(13)
    }
  }

  // Arbitrary book metadata uses system fonts, not the fixed-heading serif subset.
  func bookDetails(centered: Bool = false, coverFirst: Bool = false) -> some View {
    HStack(alignment: .center, spacing: 11) {
      if coverFirst { cover }
      VStack(alignment: centered ? .center : .leading, spacing: 3) {
        Text(momentLabel).font(.system(size: 9)).foregroundColor(theme.accent)
        Text(bookTitle).font(.system(size: 15, weight: .medium)).lineLimit(2).minimumScaleFactor(0.8)
          .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(centered ? .center : .leading)
        if data.showBookDetails, let author = completion?.author, !author.isEmpty {
          Text(author).font(.system(size: 9)).foregroundColor(theme.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        Text(completionDate).font(.system(size: 9)).foregroundColor(theme.muted).lineLimit(1).minimumScaleFactor(0.85)
      }.frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
      if !coverFirst { cover }
    }
  }
  @ViewBuilder var cover: some View {
    if data.showBookDetails, let path = completion?.coverPath, let image = readingWidgetCover(at: path) {
      image.resizable().scaledToFill().frame(width: 43, height: 61).clipped().accessibilityHidden(true)
    }
  }
  var stats: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      VStack(alignment: .leading, spacing: 1) { count(25, unitSize: 9); label("连续阅读", size: 8) }
      Spacer(minLength: 0); compactMetric("当日", seconds: data.verifiedTodaySeconds)
      Spacer(minLength: 0); compactMetric("近7日", seconds: data.weekSeconds)
    }
  }
  func compactMetric(_ title: String, seconds: Int?) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      (Text(ReadingWidgetSnapshot.minutes(seconds)).font(ReadingWidgetResources.number(25))
        + Text(" 分钟").font(.system(size: 9))).lineLimit(1).minimumScaleFactor(0.6)
      label(title, size: 8)
    }
  }
  @ViewBuilder var large: some View {
    if !theme.isAcg { normalLarge } else { illustratedLarge }
  }
  var normalLarge: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack { heading(14); Spacer(minLength: 8); label("截至 \(date)") }
      if theme == .shelf {
        rule; bookDetails(coverFirst: true).frame(minHeight: 77)
      } else if theme == .editorial {
        HStack(spacing: 12) {
          Rectangle().fill(theme.accent).frame(width: 2)
          bookDetails().padding(.vertical, 7)
        }.frame(minHeight: 87)
      } else {
        bookDetails().frame(minHeight: 85); rule
      }
      stats
      if theme != .archive { rule }
      Spacer(minLength: 0)
      heatmap(.large, height: 65, legend: true)
    }.padding(18)
      .background(ReadingWidgetArtwork(theme: theme, alignment: .trailing).opacity(0.09)
        .frame(width: 110, height: 95).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing))
  }
  var illustratedLarge: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .topLeading) {
        ReadingWidgetArtwork(theme: theme, alignment: .top)
        LinearGradient(stops: [.init(color: theme.background.opacity(0.96), location: 0),
          .init(color: theme.background.opacity(theme == .constellation ? 0.86 : 0.50), location: 0.40),
          .init(color: .clear, location: 0.65)], startPoint: .leading, endPoint: .trailing)
        VStack(alignment: .leading, spacing: 6) {
          heading(15)
          Text(completion == nil ? "新的故事，\n从这一页开始。" : completion?.finished == false ? "读到此刻，\n继续前行。" : "每一页，\n都算数。")
            .font(theme.heading(18)).lineSpacing(2).lineLimit(2).fixedSize(horizontal: false, vertical: true)
          label("截至 \(date)", size: 9)
        }.padding(.horizontal, 17).padding(.top, 12)
      }.frame(height: 111)
      VStack(alignment: .leading, spacing: 7) {
        bookDetails(centered: theme == .score, coverFirst: theme == .ink).frame(minHeight: 62)
        stats
        heatmap(.large, height: 56, legend: true)
      }.padding(.horizontal, 17).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(theme.background)
        .overlay(Rectangle().fill(theme.accent).frame(height: theme == .signal ? 3 : 1), alignment: .top)
    }
  }
}
