import SwiftUI

/// Stable IDs and exact 117 tokens from lib/reading_visual_theme.dart.
enum ReadingWidgetTheme: String, CaseIterable {
  case archive, shelf, editorial, constellation, signal, score, ink, festival

  private var tokens: [UInt32] {
    switch self {
    case .archive: return [0xf7f8f6, 0x18232c, 0x66727b, 0x2e769e, 0xc8d9e0]
    case .shelf: return [0xeef4f0, 0x183a30, 0x5c6c63, 0x3e7361, 0xbed3c7]
    case .editorial: return [0xfaf6e9, 0x353126, 0x6f6854, 0x9b8141, 0xdad0ad]
    case .constellation: return [0x101629, 0xe9edf7, 0xa5b0cd, 0xb4a3f5, 0x334267]
    case .signal: return [0xf0f1e8, 0x1c292a, 0x5f6f69, 0x4f7e6c, 0xc8d098]
    case .score: return [0xfff4f3, 0x352f44, 0x786275, 0xc84d76, 0xf0bacd]
    case .ink: return [0xf6f4e9, 0x233e3b, 0x607167, 0xa4473a, 0xb8d1c7]
    case .festival: return [0xf2f8fb, 0x1b3d54, 0x566f7d, 0xe47843, 0xaecedf]
    }
  }
  var background: Color { color(tokens[0]) }
  var foreground: Color { color(tokens[1]) }
  var muted: Color { color(tokens[2]) }
  var accent: Color { color(tokens[3]) }
  var secondary: Color { color(tokens[4]) }
  var isAcg: Bool { ![Self.archive, .shelf, .editorial].contains(self) }
  var isDark: Bool { self == .constellation }
  var label: String {
    switch self {
    case .archive: return "阅读档案"
    case .shelf: return "书架索引"
    case .editorial: return "阅读年表"
    case .constellation: return "星港夜航"
    case .signal: return "行动档案"
    case .score: return "青春频率"
    case .ink: return "云间书信"
    case .festival: return "晴空来信"
    }
  }
  func heading(_ size: CGFloat) -> Font {
    self == .editorial || self == .ink ? ReadingWidgetResources.title(size) : .system(size: size, weight: .semibold)
  }
  func heatmapColor(_ level: Int) -> Color {
    if level == 0 { return secondary.opacity(0.48) }
    return accent.opacity([0.0, 0.26, 0.48, 0.72, 1.0][level])
  }
  private func color(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 255) / 255,
      green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
  }
}

struct ReadingTicketShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: .zero)
    path.addLine(to: CGPoint(x: rect.width - 11, y: 0))
    path.addLine(to: CGPoint(x: rect.width, y: rect.height))
    path.addLine(to: CGPoint(x: 7, y: rect.height))
    path.closeSubpath()
    return path
  }
}

struct ReadingWidgetSkin {
  let id: String
  let date: String
  let fallback: ReadingWidgetTheme
  var season: Int { let month = Int(date.dropFirst(5).prefix(2)) ?? 1
    return (3...5).contains(month) ? 0 : (6...8).contains(month) ? 1 : (9...11).contains(month) ? 2 : 3 }
  static let seasons: [Color] = [hex(0xAF7D8B), hex(0x5786A2), hex(0xB18842), hex(0x4F8985)]
  var background: Color { id == "original" ? fallback.background : Self.hex(id == "night" ? 0x101419 : id == "film" ? 0x10100F : id == "paper" ? 0xECECE5 : 0xF4F0E6) }
  var foreground: Color { id == "original" ? fallback.foreground : Self.hex(id == "night" || id == "film" ? 0xF6F1E6 : 0x272C29) }
  var accent: Color { id == "original" ? fallback.accent : id == "seasons" ? Self.seasons[season] : Self.hex(id == "night" || id == "film" ? 0xDCB65E : id == "paper" ? 0x606D5D : 0x4F8985) }
  var muted: Color { id == "original" ? fallback.muted : foreground.opacity(0.65) }
  var secondary: Color { id == "original" ? fallback.secondary : foreground.opacity(0.12) }
  func heatmapColor(_ level: Int) -> Color { level == 0 ? secondary.opacity(0.48) : accent.opacity([0, 0.26, 0.48, 0.72, 1][level]) }
  static func hex(_ value: UInt32) -> Color { Color(red: Double(value >> 16 & 255)/255, green: Double(value >> 8 & 255)/255, blue: Double(value & 255)/255) }
}

struct ReadingWidgetSkinBackground: View {
  let skin: ReadingWidgetSkin
  var body: some View {
    GeometryReader { geometry in
      let w = geometry.size.width; let h = geometry.size.height
      ZStack(alignment: .topTrailing) {
        skin.background
        if skin.id == "seasons" {
          HStack(spacing: 0) { ForEach(0..<4) { index in Rectangle().fill(ReadingWidgetSkin.seasons[index]) } }
            .frame(height: 5).offset(y: h-5)
        } else if skin.id == "archive" {
          ReadingWidgetSkinMarks(kind: "archive").fill(skin.accent)
        } else if skin.id == "film" {
          ReadingWidgetSkinMarks(kind: "film").fill(ReadingWidgetSkin.hex(0xD6D2C7))
        } else if skin.id == "night" {
          ReadingWidgetSkinMarks(kind: "city").fill(skin.foreground.opacity(0.06))
          Circle().fill(skin.accent).frame(width: 16, height: 16).offset(x: -17, y: 17)
          Circle().fill(skin.background).frame(width: 16, height: 16).offset(x: -13, y: 13)
        }
        if skin.id == "seasons" {
          Text(["春", "夏", "秋", "冬"][skin.season]).font(.system(size: 62, weight: .bold, design: .serif))
            .foregroundColor(skin.accent.opacity(0.13)).padding(.trailing, 12).padding(.top, 4)
        } else if skin.id == "paper" {
          Rectangle().fill(skin.accent.opacity(0.3)).frame(width: 24, height: 13).rotationEffect(.degrees(7)).offset(x: -15, y: -2)
        }
      }
    }.accessibilityHidden(true)
  }
}

/// Shape paths also render on iOS 14; using Canvas would raise the minimum OS.
struct ReadingWidgetSkinMarks: Shape {
  let kind: String
  func path(in rect: CGRect) -> Path {
    var result = Path(); let w = rect.width; let h = rect.height
    if kind == "archive" {
      result.addRect(CGRect(x: 0, y: 0, width: 4, height: h))
      for x in stride(from: w-44, to: w-12, by: 3) { result.addRect(CGRect(x: x, y: h-26, width: 1, height: 12)) }
    } else if kind == "film" {
      for x in stride(from: 12.0, to: w-8, by: 14) { for y in [3.0, h-7] { result.addRect(CGRect(x: x, y: y, width: 6, height: 4)) } }
    } else {
      for i in 0..<8 { result.addRect(CGRect(x: CGFloat(i)*w/8, y: h-10-CGFloat(i%3)*6, width: w/10, height: 30)) }
    }
    return result
  }
}
