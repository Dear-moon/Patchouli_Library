import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The sole image-platform leaf; offscreen reviews render the production view.
func readingWidgetCover(at path: String) -> Image? {
  #if canImport(UIKit)
  guard let image = UIImage(contentsOfFile: path) else { return nil }
  return Image(uiImage: image)
  #elseif canImport(AppKit)
  guard let image = NSImage(contentsOfFile: path) else { return nil }
  return Image(nsImage: image)
  #else
  return nil
  #endif
}

/// Production assets are copied into the extension bundle. The review harness
/// supplies the same source resource folders, never a different painted face.
enum ReadingWidgetResources {
  static var reviewRoot: URL?
  static func url(_ name: String, extension ext: String, folder: String) -> URL? {
    if let root = reviewRoot { return root.appendingPathComponent(folder).appendingPathComponent("\(name).\(ext)") }
    return Bundle.main.url(forResource: name, withExtension: ext)
  }
  static let registerFonts: Void = {
    for name in ["ReadingDisplay-Bold", "ReadingDisplay-Medium", "ReadingSerifDisplay-Bold"] {
      if let url = url(name, extension: "ttf", folder: "fonts") {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
      }
    }
  }()
  static func artwork(_ theme: ReadingWidgetTheme) -> Image? {
    if let root = reviewRoot {
      return readingWidgetCover(at: root.appendingPathComponent("reading_art/\(theme.rawValue)-117.png").path)
    }
    return Image("ReadingArtwork_\(theme.rawValue)", bundle: .main)
  }
  static func number(_ size: CGFloat) -> Font {
    _ = registerFonts
    return .custom("BarlowCondensed-Bold", size: size, relativeTo: .largeTitle)
  }
  static func season(_ index: Int) -> Image? {
    let name = ["spring", "summer", "autumn", "winter"][index]
    if let root = reviewRoot {
      return readingWidgetCover(at: root.deletingLastPathComponent().appendingPathComponent("ios/ReadingWidgets/Assets.xcassets/WidgetSeason_\(name).imageset/art.png").path)
    }
    return Image("WidgetSeason_\(name)", bundle: .main)
  }
  static func label(_ size: CGFloat) -> Font {
    _ = registerFonts
    return .custom("BarlowCondensed-Medium", size: size, relativeTo: .caption)
  }
  static func title(_ size: CGFloat) -> Font {
    _ = registerFonts
    return .custom("ReadingSerifDisplay-Bold", size: size, relativeTo: .title2)
  }
}
