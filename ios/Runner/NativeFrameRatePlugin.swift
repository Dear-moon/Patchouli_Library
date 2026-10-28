import Flutter
import UIKit

/// Reports the attached screen's capability, not a simulated current frame rate.
/// Flutter owns its iOS CADisplayLink; no public embedding API can set its rate.
/// Keep that automatic high-refresh path and do not add a second display link.
final class NativeFrameRatePlugin: NSObject, FlutterPlugin {
  private let maximumRate: () -> Int?

  init(maximumRate: @escaping () -> Int?) {
    self.maximumRate = maximumRate
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = NativeFrameRatePlugin { [weak registrar] in
      registrar?.viewController?.viewIfLoaded?.window?.windowScene?.screen.maximumFramesPerSecond
    }
    let channel = FlutterMethodChannel(name: "org.mewx.wenku8/frame_rate", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.publish(plugin)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "info":
      guard let maximum = maximumRate(), maximum > 0 else {
        result(FlutterError(code: "display_unavailable", message: "当前无法读取屏幕信息，请返回页面后重试", details: nil))
        return
      }
      result([
        "target": -1.0,
        "rates": [Double](),
        "maximum": Double(maximum),
        "canSelect": false,
        "requestStatusAvailable": false,
        "surfaceRequestState": "system_managed",
      ] as [String: Any])
    case "set":
      result(FlutterError(code: "frame_rate_unavailable", message: "iOS 自动调度帧率，当前不支持手动锁定", details: nil))
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
