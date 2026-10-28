import Flutter
import Foundation
import WidgetKit

final class ReadingWidgetsPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "org.mewx.wenku8/reading_widgets", binaryMessenger: registrar.messenger())
    ReadingWidgetOpenInbox.shared.deliver = { destination, completion in
      channel.invokeMethod("openReadingSurface", arguments: destination) { completion($0 == nil) }
    }
    registrar.addMethodCallDelegate(ReadingWidgetsPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "cardsSupported": result(true)
    case "completeConfiguration": result(nil) // WidgetKit owns the system configuration result.
    case "publishCards":
      do {
        guard let args = call.arguments as? [String: Any], let cards = args["cards"] else { throw CocoaError(.coderInvalidValue) }
        try ReadingCardStore.publish(cards)
        if #available(iOS 14.0, *) { WidgetCenter.shared.reloadAllTimelines() }
        result(nil)
      } catch { result(FlutterError(code: "WIDGET_WRITE_FAILED", message: "小组件暂未更新", details: nil)) }
    case "consumeOpenRequest":
      result(ReadingWidgetOpenInbox.shared.consume())
    case "publishSnapshot":
      guard let root = ReadingWidgetStore.container else {
        result(FlutterError(code: "WIDGET_GROUP_UNAVAILABLE", message: "桌面组件共享空间尚未启用", details: nil)); return
      }
      do {
        guard let args = call.arguments as? [String: Any], let json = args["json"] as? String,
          let bytes = json.data(using: .utf8) else { throw CocoaError(.coderInvalidValue) }
        var snapshot = try JSONDecoder().decode(ReadingWidgetSnapshot.self, from: bytes)
        guard snapshot.version == 1, snapshot.week.count == 7 else { throw CocoaError(.coderInvalidValue) }
        let cover = root.appendingPathComponent("reading-cover-v1.png")
        if !snapshot.showBookDetails {
          snapshot.latestCompletion?.bookId = nil
          snapshot.latestCompletion?.title = nil
          snapshot.latestCompletion?.author = nil
          snapshot.latestCompletion?.coverPath = nil
          try? FileManager.default.removeItem(at: cover)
        } else if let path = snapshot.latestCompletion?.coverPath {
          // Flutter has already made a small, local cover. Never fetch in WidgetKit.
          if let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count <= 4 * 1024 * 1024 {
            try data.write(to: cover, options: .atomic)
            snapshot.latestCompletion?.coverPath = cover.path
          } else { snapshot.latestCompletion?.coverPath = nil }
        }
        let directory = root.appendingPathComponent("reading-desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var owned: [String: String] = [:]
        do {
          if let incoming = snapshot.desktopImages {
            for size in ["small", "medium", "large"] {
              guard let path = incoming[size] else { throw CocoaError(.coderInvalidValue) }
              let source = URL(fileURLWithPath: path).resolvingSymlinksInPath()
              guard source.path.hasPrefix(URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path + "/") else { throw CocoaError(.fileReadNoPermission) }
              let bytes = try Data(contentsOf: source)
              guard bytes.count >= 8, bytes.count <= 2 * 1024 * 1024 else { throw CocoaError(.coderInvalidValue) }
              let target = directory.appendingPathComponent(UUID().uuidString + ".png")
              try bytes.write(to: target, options: .atomic)
              owned[size] = target.path
            }
          }
          snapshot.desktopImages = owned.isEmpty ? nil : owned
          let encoded = try JSONEncoder().encode(snapshot)
          try encoded.write(to: root.appendingPathComponent(ReadingWidgetStore.filename), options: .atomic)
        } catch {
          for path in owned.values { try? FileManager.default.removeItem(atPath: path) }
          throw error
        }
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where !owned.values.contains(file.path) {
          try? FileManager.default.removeItem(at: file)
        }
        if #available(iOS 14.0, *) { WidgetCenter.shared.reloadTimelines(ofKind: "ReadingQuiet") }
        result(nil)
      } catch {
        result(FlutterError(code: "WIDGET_WRITE_FAILED", message: "桌面组件暂未更新，请重试", details: nil))
      }
    default: result(FlutterMethodNotImplemented)
    }
  }
}
