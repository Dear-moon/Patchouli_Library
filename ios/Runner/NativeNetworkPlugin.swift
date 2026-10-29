import Flutter
import Network

/// Route availability, not periodic requests to a website. No SSID, addresses
/// or traffic are collected; the shared Dart handover policy handles flicker.
final class NativeNetworkPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let queue = DispatchQueue(label: "org.mewx.wenku8.network-path")
  private var monitor: NWPathMonitor?
  private var sink: FlutterEventSink?
  private var current = "unknown"

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = NativeNetworkPlugin()
    let methods = FlutterMethodChannel(name: "org.mewx.wenku8/network_status", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: methods)
    FlutterEventChannel(name: "org.mewx.wenku8/network_events", binaryMessenger: registrar.messenger()).setStreamHandler(plugin)
    registrar.publish(plugin)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "current" { result(current) }
    else { result(FlutterMethodNotImplemented) }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    monitor?.cancel()
    sink = events
    let path = NWPathMonitor()
    monitor = path
    path.pathUpdateHandler = { [weak self, weak path] update in
      let value: String
      switch update.status {
      case .satisfied: value = "online"
      case .unsatisfied: value = "offline"
      case .requiresConnection: value = "checking"
      @unknown default: value = "unknown"
      }
      DispatchQueue.main.async {
        guard let self, let path, self.monitor === path else { return }
        self.current = value
        self.sink?(value)
      }
    }
    path.start(queue: queue)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    monitor?.cancel()
    monitor = nil
    sink = nil
    return nil
  }
}
