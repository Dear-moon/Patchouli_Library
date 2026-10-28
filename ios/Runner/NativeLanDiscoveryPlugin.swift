import Darwin
import Flutter
import Network
import UIKit

/// Same DNS-SD/TXT contract as the Android host. Discovery publishes no book,
/// account, pairing secret or user-assigned device name.
struct LanBonjourRecord: Equatable {
  let id: String
  let name: String
  let host: String
  let port: Int

  init?(txt: Data?, addresses: [Data]?, port: Int, ownID: String) {
    guard let txt else { return nil }
    // Foundation can return NSNull for a TXT key without a value, despite the
    // imported [String: Data] signature. Validate the Objective-C values before
    // asking Swift to bridge any individual field to Data.
    let values = NetService.dictionary(fromTXTRecord: txt) as NSDictionary
    guard let rawID = values["id"] as? Data, let id = String(data: rawID, encoding: .utf8),
          id != ownID, id.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
          values["v"] as? Data == Data("1".utf8), let rawName = values["name"] as? Data, let name = String(data: rawName, encoding: .utf8),
          !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf16.count <= 64,
          name.rangeOfCharacter(from: .controlCharacters) == nil, (1024...65535).contains(port),
          let host = addresses?.compactMap(Self.privateIPv4).first else { return nil }
    self.id = id; self.name = name; self.host = host; self.port = port
  }

  static func privateIPv4(_ data: Data) -> String? {
    guard data.count >= MemoryLayout<sockaddr_in>.size else { return nil }
    var address = data.withUnsafeBytes { $0.loadUnaligned(as: sockaddr_in.self) }
    guard address.sin_family == sa_family_t(AF_INET) else { return nil }
    let ip = UInt32(bigEndian: address.sin_addr.s_addr)
    let first = ip >> 24, second = (ip >> 16) & 255
    guard first == 127 || first == 10 || first == 192 && second == 168 ||
      first == 172 && (16...31).contains(second) || first == 169 && second == 254 else { return nil }
    var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    guard inet_ntop(AF_INET, &address.sin_addr, &text, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
    return String(cString: text)
  }

  var value: [String: Any] { ["id": id, "name": name, "host": host, "port": port] }
}

/// System Bonjour on the declared service only: no raw multicast entitlement,
/// subnet scans, cloud registry or polling. NWBrowser waits for the user's
/// local-network decision; NetService resolves numeric addresses for Dart's
/// existing authenticated/encrypted TCP protocol.
final class NativeLanDiscoveryPlugin: NSObject, FlutterPlugin, NetServiceDelegate {
  static let serviceType = "_wenkuread._tcp."
  private var channel: FlutterMethodChannel?
  private var browser: NWBrowser?
  private var publisher: NetService?
  private var services = [String: NetService]()
  private var resolving = Set<String>()
  private var monitoring = Set<String>()
  private var found = [String: LanBonjourRecord]()
  private var ownID = ""
  private var label = ""
  private var port: Int32 = 0

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = NativeLanDiscoveryPlugin()
    let channel = FlutterMethodChannel(name: "org.mewx.wenku8/lan_discovery", binaryMessenger: registrar.messenger())
    plugin.channel = channel
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.publish(plugin)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      let args = call.arguments as? [String: Any] ?? [:]
      guard let id = args["id"] as? String, id.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
            let port = args["port"] as? Int, (1024...65535).contains(port) else {
        result(FlutterError(code: "LAN_DISCOVERY", message: "设备发现参数无效，请重新开启局域网续读", details: nil)); return
      }
      stop()
      ownID = id
      label = "\(UIDevice.current.model) · \(id.suffix(4))"
      self.port = Int32(port)
      let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: "local."), using: .tcp)
      self.browser = browser
      browser.stateUpdateHandler = { [weak self, weak browser] state in
        guard let self, let browser, self.browser === browser else { return }
        switch state {
        case .ready:
          self.advertise()
          self.channel?.invokeMethod("ready", arguments: nil)
        case .waiting:
          // Keep the browser alive: approving the system prompt can move the
          // same browser to ready without another tap or repeated prompt.
          self.found.removeAll()
          self.publishDevices()
          self.channel?.invokeMethod("failure", arguments: nil)
        case .failed:
          self.stop()
          self.channel?.invokeMethod("failure", arguments: nil)
        default: break
        }
      }
      browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
        guard let self, let browser, self.browser === browser else { return }
        self.update(results)
      }
      browser.start(queue: .main)
      result(label)
    case "stop": stop(); result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func advertise() {
    guard publisher == nil, !ownID.isEmpty else { return }
    let service = NetService(domain: "local.", type: Self.serviceType, name: "wenku-\(ownID.prefix(12))", port: port)
    service.delegate = self
    service.setTXTRecord(NetService.data(fromTXTRecord: ["id": Data(ownID.utf8), "name": Data(label.utf8), "v": Data("1".utf8)]))
    publisher = service
    service.schedule(in: .main, forMode: .common)
    service.publish()
  }

  private func key(_ service: NetService) -> String { "\(service.domain)|\(service.type)|\(service.name)" }

  private func update(_ results: Set<NWBrowser.Result>) {
    var present = Set<String>()
    for result in results.sorted(by: { String(describing: $0.endpoint) < String(describing: $1.endpoint) }) {
      guard case let .service(name, type, domain, _) = result.endpoint,
            type.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == Self.serviceType.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            name.hasPrefix("wenku-"), present.count < 64 else { continue }
      let candidate = NetService(domain: domain, type: Self.serviceType, name: name)
      let key = key(candidate)
      present.insert(key)
      let service = services[key] ?? candidate
      if services[key] == nil {
        services[key] = service
        service.delegate = self
        service.schedule(in: .main, forMode: .common)
      }
      if resolving.insert(key).inserted { service.resolve(withTimeout: 6) }
    }
    for key in services.keys.filter({ !present.contains($0) }) {
      if let service = services.removeValue(forKey: key) { release(service) }
      found.removeValue(forKey: key)
      resolving.remove(key)
      monitoring.remove(key)
    }
    publishDevices()
  }

  func netServiceDidResolveAddress(_ sender: NetService) {
    let key = key(sender)
    guard services[key] === sender else { return }
    resolving.remove(key)
    accept(sender)
    if monitoring.insert(key).inserted { sender.startMonitoring() }
  }

  func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
    accept(sender, txt: data)
  }

  private func accept(_ service: NetService, txt: Data? = nil) {
    let key = key(service)
    guard services[key] === service, browser != nil else { return }
    let value = LanBonjourRecord(txt: txt ?? service.txtRecordData(), addresses: service.addresses, port: service.port, ownID: ownID)
    if found[key] != value { found[key] = value; publishDevices() }
  }

  func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
    let key = key(sender)
    if services[key] === sender { resolving.remove(key) }
  }

  func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
    guard publisher === sender else { return }
    release(sender)
    publisher = nil
    channel?.invokeMethod("failure", arguments: nil)
  }

  private func publishDevices() {
    var unique = [String: LanBonjourRecord]()
    for key in found.keys.sorted() { if let device = found[key] { unique[device.id] = device } }
    channel?.invokeMethod("devices", arguments: unique.values.sorted { $0.id < $1.id }.map(\.value))
  }

  private func release(_ service: NetService) {
    service.delegate = nil
    service.stopMonitoring()
    service.stop()
    service.remove(from: .main, forMode: .common)
  }

  private func stop() {
    let old = browser
    browser = nil
    old?.cancel()
    if let service = publisher { release(service) }
    publisher = nil
    for service in services.values { release(service) }
    services.removeAll(); resolving.removeAll(); monitoring.removeAll(); found.removeAll()
    ownID = ""; port = 0
    publishDevices()
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    stop()
    channel?.setMethodCallHandler(nil)
    channel = nil
  }
}
