import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppHapticsPlugin") {
      AppHapticsPlugin.register(with: registrar)
    }
  }
}

private final class AppHapticsPlugin: NSObject, FlutterPlugin {
  private let selection = UISelectionFeedbackGenerator()
  private let impact = UIImpactFeedbackGenerator(style: .light)
  private let hold = UIImpactFeedbackGenerator(style: .medium)
  private let boundary = UIImpactFeedbackGenerator(style: .rigid)
  private let strongImpact = UIImpactFeedbackGenerator(style: .heavy)
  private let outcome = UINotificationFeedbackGenerator()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "org.mewx.wenku8_flutter/haptics", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AppHapticsPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "play" else { result(FlutterMethodNotImplemented); return }
    guard UIApplication.shared.applicationState == .active else { result(false); return }
    let options = call.arguments as? [String: Any]
    let cue = options?["cue"] as? String ?? call.arguments as? String
    let strength = options?["strength"] as? String ?? "standard"
    guard ["light", "standard", "strong"].contains(strength) else {
      result(FlutterError(code: "BAD_STRENGTH", message: "Unknown haptic strength", details: nil))
      return
    }
    let adjustable = ["selection", "shelfStep", "detent", "pageTurn", "action", "longPress", "boundary"]
    if let cue, adjustable.contains(cue), strength != "standard" {
      let generator = strength == "light" ? impact : strongImpact
      let lightIntensity: CGFloat = cue == "pageTurn" ? 0.25 : 0.5
      generator.impactOccurred(intensity: strength == "light" ? lightIntensity : 1.0)
      generator.prepare()
      result(true)
      return
    }
    // Notifications have no intensity control: preserve their system meaning.
    switch cue {
    case "selection", "shelfStep", "detent":
      selection.selectionChanged()
      selection.prepare()
    case "pageTurn":
      impact.impactOccurred(intensity: 0.45)
      impact.prepare()
    case "action":
      impact.impactOccurred()
      impact.prepare()
    case "success":
      outcome.notificationOccurred(.success)
      outcome.prepare()
    case "longPress":
      hold.impactOccurred()
      hold.prepare()
    case "boundary":
      boundary.impactOccurred(intensity: 0.6)
      boundary.prepare()
    case "warning":
      outcome.notificationOccurred(.warning)
      outcome.prepare()
    case "error":
      outcome.notificationOccurred(.error)
      outcome.prepare()
    default:
      result(FlutterError(code: "BAD_CUE", message: "Unknown haptic cue", details: nil))
      return
    }
    result(true)
  }
}
