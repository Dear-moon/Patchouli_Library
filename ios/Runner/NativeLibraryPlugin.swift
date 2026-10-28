import Flutter
import UIKit
import UniformTypeIdentifiers

/// The reader clock has work only while its status is visible. Recreate the
/// timer on resume/time changes so it stays aligned to the current wall minute.
final class ReaderStatusClock {
  private let now: () -> Date
  private let publish: () -> Void
  private var generation = 0
  private(set) var timer: Timer?

  init(now: @escaping () -> Date = Date.init, publish: @escaping () -> Void) {
    self.now = now; self.publish = publish
  }
  func resume() {
    pause()
    let generation = self.generation
    let next = Date(timeIntervalSince1970: (floor(now().timeIntervalSince1970 / 60) + 1) * 60)
    let timer = Timer(fire: next, interval: 60, repeats: true) { [weak self] _ in
      guard let self, self.generation == generation else { return }
      self.publish()
    }
    timer.tolerance = 0.1
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
    publish()
  }
  func pause() { generation += 1; timer?.invalidate(); timer = nil }
  deinit { timer?.invalidate() }
}

/// iOS host capabilities for the existing Flutter library and reader. File I/O
/// runs serially off the main thread; picking and window changes stay on main.
final class NativeLibraryPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate, FlutterStreamHandler {
  private let registrar: FlutterPluginRegistrar
  private let io = DispatchQueue(label: "org.mewx.wenku8.document-io", qos: .userInitiated)
  private var documents: ManagedBookDocuments?
  private var folderScanner: BookFolderScanner?
  private var syncDocument: BookSyncDocument?
  private var linkedDocuments: LinkedBookDocuments?
  private var references = [String: URL]() // Access references, never a deletion list.
  private var pickerResult: FlutterResult?
  private var pickerKind = "pickBooks"
  private var deferred = false
  private var linkOriginals = false
  private var pickerExport: URL?
  private var originalBrightness: CGFloat?
  private var sink: FlutterEventSink?
  private lazy var statusClock = ReaderStatusClock { [weak self] in self?.publishStatus() }
  private var observers = [NSObjectProtocol]()
  private var originalBatteryMonitoring = false
  private var statusActive = false

  private init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = NativeLibraryPlugin(registrar: registrar)
    for name in ["book_documents", "reader_controls", "cloud_sources", "custom_speech", "lan_reading_config"] {
      let channel = FlutterMethodChannel(name: "org.mewx.wenku8/\(name)", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in plugin.handle(name, call, result) }
      if name == "book_documents" {
        BookOpenInbox.shared.onAvailable = { channel.invokeMethod("bookOpenAvailable", arguments: nil) }
      }
    }
    FlutterEventChannel(name: "org.mewx.wenku8/reader_status", binaryMessenger: registrar.messenger())
      .setStreamHandler(plugin)
    registrar.publish(plugin)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result(FlutterMethodNotImplemented)
  }

  private func handle(_ channel: String, _ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch channel {
    case "book_documents":
      if call.method == "pickBookOpenReference" {
        do {
          let source = try BookOpenInbox.shared.source(args["id"] as? String ?? "")
          presentPicker("pickOriginalReference", args, result, initialDirectory: source.deletingLastPathComponent())
        } catch { completeFailure(error, result) }
        return
      }
      if ["pickBook", "pickBooks", "pickDictionaryFiles", "pickImage", "pickFont", "pickTextReference", "pickOriginalReference", "selectScanFolder", "createSync", "openSync"].contains(call.method) {
        presentPicker(call.method, args, result)
        return
      }
      io.async {
        do {
          let value = try self.documentAction(call.method, args)
          DispatchQueue.main.async { result(value) }
        } catch { self.completeFailure(error, result) }
      }
    case "reader_controls":
      switch call.method {
      case "installedApp":
        result([
                "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                "appBuild": Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0])
      case "brightness": result(Double(UIScreen.main.brightness))
      case "apply":
        if let brightness = args["brightness"] as? Double {
          if originalBrightness == nil { originalBrightness = UIScreen.main.brightness }
          UIScreen.main.brightness = CGFloat(min(1, max(0, brightness)))
        } else if let previous = originalBrightness {
          UIScreen.main.brightness = previous
          originalBrightness = nil
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    case "cloud_sources", "custom_speech", "lan_reading_config":
      io.async {
        do {
          let storage: NativeSecureRecord
          switch channel {
          case "cloud_sources": storage = .cloudSources
          case "lan_reading_config": storage = .lanReading
          default: storage = .customSpeech
          }
          let value: Any?
          switch call.method {
          case "read": value = try storage.read()
          case "write":
            if channel == "lan_reading_config" {
              guard let text = call.arguments as? String, text.utf16.count <= 20_000 else {
                throw BookDocumentFailure(code: "pairing_storage", message: "本机配对配置无效，未更改已有连接")
              }
              try storage.write(text)
            } else { try storage.write(call.arguments as? String) }
            value = nil
          default: value = FlutterMethodNotImplemented
          }
          DispatchQueue.main.async { result(value) }
        } catch { self.completeFailure(error, result) }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func store() throws -> ManagedBookDocuments {
    if let documents { return documents }
    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let created = try ManagedBookDocuments(
      root: support.appendingPathComponent(".import-work", isDirectory: true),
      readableRoots: [cache.appendingPathComponent("cloud-book-import", isDirectory: true),
                      cache.appendingPathComponent("portable-book-import", isDirectory: true)])
    documents = created
    return created
  }

  private func documentAction(_ method: String, _ args: [String: Any]) throws -> Any? {
    switch method {
    case "pendingBookOpen": return BookOpenInbox.shared.pending()
    case "resolveBookOpen":
      let source = try BookOpenInbox.shared.source(args["id"] as? String ?? "")
      return args["copy"] as? Bool == true
        ? try stage(source, kind: "pickBook") : try links().retain(source)
    case "finishBookOpen": BookOpenInbox.shared.finish(args["id"] as? String ?? ""); return nil
    case "deleteBookOpenSource":
      try BookOpenInbox.shared.deleteSource(args["id"] as? String ?? "", copiedPath: args["path"] as? String ?? "")
      return nil
    case "openLinkedDocument": return try links().open(args)
    case "closeLinkedDocument": try links().close(args["lease"] as? String ?? ""); return nil
    case "inspectLinkedText": return try links().inspectText(args)
    case "readLinkedText":
      var value = try links().readText(args)
      value["textBytes"] = FlutterStandardTypedData(bytes: value["textBytes"] as! Data)
      return value
    case "readLinkedBytes": return FlutterStandardTypedData(bytes: try links().readBytes(args))
    case "releaseLinkedText": try links().release(args["reference"] as? String ?? ""); return nil
    case "stageLinkedDocument": return try links().stage(args["reference"] as? String ?? "", workspace: store())
    case "stagedTextReference":
      let source = try store().readableSourceURL(args["path"] as? String ?? "")
      return try links().retain(source, name: "原书.txt")["reference"]
    case "syncInfo": return try sync().info()
    case "readSync": return try sync().read()
    case "writeSync": return try sync().write(expectedPath: args["expectedPath"] as? String ?? "", path: args["path"] as? String ?? "")
    case "disconnectSync": try sync().disconnect(); return nil
    case "recoverSync": return try sync().recover(args["which"] as? String ?? "")
    case "scanFolderInfo": return try scanner().info()
    case "selectAllScan": return try scanner().selectApplicationDocuments()
    case "scanFormats": return try scanner().formats()
    case "setScanFormats": try scanner().setFormats(args["extensions"] as? [String] ?? []); return nil
    case "setScanAutomatic": try scanner().setAutomatic(args["value"] as? Bool == true); return nil
    case "disconnectScanFolder": try scanner().disconnect(); return nil
    case "scanBooks": return try scanner().scan()
    case "stageScanBook": return try scanner().stage(args["token"] as? String ?? "", documents: store())
    case "linkScanBook": return try scanner().link(args["token"] as? String ?? "", documents: links())
    case "markScanBook": try scanner().markImported(args["token"] as? String ?? ""); return nil
    case "finishBookScan": try scanner().finish(); return nil
    case "decodeBookNames":
      guard let values = args["names"] as? [FlutterStandardTypedData] else {
        throw BookDocumentFailure(code: "zip_name", message: "ZIP 文件名数据无效")
      }
      return try ManagedBookDocuments.decodeBookNames(values.map(\.data))
    case "stageImportBook":
      guard let token = args["token"] as? String, let source = references[token] else {
        throw BookDocumentFailure(code: "import_reference", message: "文件的访问授权已失效，请重新选择")
      }
      return try stage(source, kind: "pickBook")
    case "releaseBooks":
      for path in args["paths"] as? [String] ?? [] { _ = try store().release(path) }
      for token in args["tokens"] as? [String] ?? [] { references.removeValue(forKey: token) }
      return nil
    case "decodeText", "decodeTextFile":
      guard let path = args["path"] as? String else {
        throw BookDocumentFailure(code: "import_path", message: "缺少要解码的文件")
      }
      let output = try store().decodeTextFile(path, encoding: args["encoding"] as? String ?? "auto",
        maximumBytes: args["maximumInputBytes"] as? Int ?? 128 * 1024 * 1024,
        maximumOutputBytes: args["maximumOutputBytes"] as? Int ?? 384 * 1024 * 1024)
      if method == "decodeTextFile" { return output.path }
      defer { _ = try? store().release(output.path) }
      return try String(contentsOf: output, encoding: .utf8)
    case "extractKindle", "extractPdf":
      guard let path = args["path"] as? String, let output = args["output"] as? String else {
        throw BookDocumentFailure(code: "conversion_path", message: "缺少转换文件或暂存目录")
      }
      let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let conversion = try NativeBookConversion(documents: store(), portableRoot: cache.appendingPathComponent("portable-book-import", isDirectory: true))
      if method == "extractPdf" {
        try conversion.extractPdf(path, output: output, name: args["name"] as? String ?? "PDF")
        return nil
      }
      return try conversion.extractKindle(path, output: output)
    case "prepareBook", "prepareLinkedDocument":
      if (args["name"] as? String ?? "").lowercased().hasSuffix(".doc") {
        throw BookDocumentFailure(code: "format_unavailable", message: "此设备暂不支持二进制 DOC，请将原文件另存为 DOCX、RTF 或 EPUB 后导入")
      }
      throw BookDocumentFailure(code: "format_unavailable", message: "此平台正在适配此格式，请先导入 EPUB 或 TXT")
    default: return FlutterMethodNotImplemented
    }
  }

  private func scanner() throws -> BookFolderScanner {
    if let folderScanner { return folderScanner }
    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let created = try BookFolderScanner(stateFile: support.appendingPathComponent(".folder-scan/config.json"), documentsDirectory: documents)
    folderScanner = created
    return created
  }

  private func sync() throws -> BookSyncDocument {
    if let syncDocument { return syncDocument }
    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let created = try BookSyncDocument(root: support.appendingPathComponent(".document-sync", isDirectory: true), workspace: store())
    syncDocument = created
    return created
  }

  private func links() throws -> LinkedBookDocuments {
    if let linkedDocuments { return linkedDocuments }
    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let created = try LinkedBookDocuments(root: support.appendingPathComponent(".linked-originals", isDirectory: true))
    linkedDocuments = created
    return created
  }

  private func presentPicker(_ kind: String, _ args: [String: Any], _ result: @escaping FlutterResult, initialDirectory: URL? = nil) {
    guard pickerResult == nil else {
      result(FlutterError(code: "picker_busy", message: "请先完成当前文件选择", details: nil)); return
    }
    guard let controller = presenter() else {
      result(FlutterError(code: "picker_unavailable", message: "当前无法选择文件，请返回页面后重试", details: nil)); return
    }
    pickerResult = result
    pickerKind = kind
    deferred = kind != "pickDictionaryFiles" && args["deferred"] as? Bool == true
    linkOriginals = kind != "pickDictionaryFiles" && (args["linkOriginals"] as? Bool == true || kind == "pickTextReference" || kind == "pickOriginalReference")
    if kind == "createSync" {
      io.async {
        do {
          let source = try self.sync().prepareCreation()
          DispatchQueue.main.async {
            self.pickerExport = source
            let picker: UIDocumentPickerViewController
            if #available(iOS 14.0, *) { picker = UIDocumentPickerViewController(forExporting: [source], asCopy: false) }
            else { picker = UIDocumentPickerViewController(url: source, in: .moveToService) }
            picker.delegate = self
            controller.present(picker, animated: true)
          }
        } catch {
          DispatchQueue.main.async { self.pickerResult = nil }
          self.completeFailure(error, result)
        }
      }
      return
    }
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      let types: [UTType] = kind == "selectScanFolder" ? [.folder] : kind == "pickImage" ? [.image] : kind == "pickFont" ? [.font] : kind == "pickTextReference" ? [.plainText] : kind == "openSync" ? [UTType(filenameExtension: "wenku8sync") ?? .data] : [.content, .data]
      picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
    } else {
      let types = kind == "selectScanFolder" ? ["public.folder"] : kind == "pickImage" ? ["public.image"] : kind == "pickFont" ? ["public.font"] : kind == "pickTextReference" ? ["public.plain-text"] : ["public.content", "public.data"]
      picker = UIDocumentPickerViewController(documentTypes: types, in: .open)
    }
    if #available(iOS 13.0, *), let initialDirectory { picker.directoryURL = initialDirectory }
    picker.allowsMultipleSelection = kind == "pickBooks" || kind == "pickDictionaryFiles"
    picker.delegate = self
    controller.present(picker, animated: true)
  }

  private func presenter() -> UIViewController? {
    var controller = registrar.viewController
    while let presented = controller?.presentedViewController { controller = presented }
    return controller
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard let result = pickerResult else { return }
    let kind = pickerKind, export = pickerExport
    io.async {
      if let export { try? self.sync().releaseCreation(export) }
      DispatchQueue.main.async {
        self.pickerResult = nil
        self.pickerExport = nil
        result(kind == "pickBooks" || kind == "pickDictionaryFiles" ? [] : nil)
      }
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pickerResult else { return }
    let kind = pickerKind, deferred = self.deferred, export = pickerExport, linkOriginals = self.linkOriginals
    io.async {
      defer {
        if let export { try? self.sync().releaseCreation(export) }
      }
      do {
        if kind == "pickDictionaryFiles" && urls.count > 64 {
          throw BookDocumentFailure(code: "dictionary_selection", message: "一次最多选择 64 个词典文件")
        }
        if kind == "createSync" || kind == "openSync" {
          let value = try urls.first.map { try self.sync().select($0, created: kind == "createSync") }
          DispatchQueue.main.async { self.pickerResult = nil; self.pickerExport = nil; result(value) }
          return
        }
        if kind == "selectScanFolder" {
          let value = try urls.first.map { try self.scanner().select($0) }
          DispatchQueue.main.async { self.pickerResult = nil; result(value) }
          return
        }
        let values: [[String: Any]] = try urls.map { source in
          if linkOriginals {
            do { return try self.links().retain(source) }
            catch {
              if kind != "pickBooks" { throw error }
              return ["name": source.lastPathComponent, "error": error.localizedDescription]
            }
          }
          if deferred {
            let token = UUID().uuidString
            self.references[token] = source
            return ["name": source.lastPathComponent, "token": token]
          }
          do { return try self.stage(source, kind: kind) }
          catch {
            if kind != "pickBooks" && kind != "pickDictionaryFiles" { throw error }
            return ["name": source.lastPathComponent, "error": error.localizedDescription]
          }
        }
        DispatchQueue.main.async { self.pickerResult = nil; result(kind == "pickBooks" || kind == "pickDictionaryFiles" ? values : values.first) }
      } catch {
        DispatchQueue.main.async { self.pickerResult = nil; self.pickerExport = nil }
        self.completeFailure(error, result)
      }
    }
  }

  private func stage(_ source: URL, kind: String) throws -> [String: Any] {
    let scope = source.startAccessingSecurityScopedResource()
    defer { if scope { source.stopAccessingSecurityScopedResource() } }
    if kind == "pickDictionaryFiles" && source.lastPathComponent.range(of: #"\.(mdx|mdd|mobi|ifo|idx(?:\.gz)?|dict(?:\.dz)?|syn|zip)$"#, options: [.regularExpression, .caseInsensitive]) == nil {
      throw BookDocumentFailure(code: "dictionary_format", message: "请选择 MDX、MDD、MOBI 词典、StarDict 文件或 ZIP 词典包")
    }
    let maximum = kind == "pickDictionaryFiles" ? 512 * 1024 * 1024 : kind == "pickImage" ? 20 * 1024 * 1024 : kind == "pickFont" ? 32 * 1024 * 1024 : BookImportFormatPolicy.byteLimit(source.pathExtension)
    let workspace = try store()
    var staged: URL?, failure: Error?, coordinationError: NSError?
    NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
      do { staged = try workspace.copy(readable, maximumBytes: maximum) }
      catch { failure = error }
    }
    if let error = coordinationError ?? failure { throw error }
    guard let staged else { throw BookDocumentFailure(code: "import_read", message: "无法读取所选文件，请重新选择") }
    return ["name": source.lastPathComponent, "path": staged.path]
  }

  private func completeFailure(_ error: Error, _ result: @escaping FlutterResult) {
    let failure = error as? BookDocumentFailure
    let value = FlutterError(code: failure?.code ?? "document_io", message: error.localizedDescription,
      details: ["stage": "ios_document", "domain": (error as NSError).domain, "code": (error as NSError).code])
    DispatchQueue.main.async { result(value) }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    stopStatus()
    sink = events
    originalBatteryMonitoring = UIDevice.current.isBatteryMonitoringEnabled
    for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.publishStatus() })
    }
    for name in [UIApplication.significantTimeChangeNotification, UIApplication.didBecomeActiveNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        if UIApplication.shared.applicationState != .background { self?.resumeStatus() }
      })
    }
    observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.pauseStatus() })
    if UIApplication.shared.applicationState != .background { resumeStatus() }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? { stopStatus(); return nil }

  private func publishStatus() {
    guard statusActive else { return }
    let device = UIDevice.current
    sink?(["time": Int64(Date().timeIntervalSince1970 * 1000),
           "battery": device.batteryLevel < 0 ? -1 : Int((device.batteryLevel * 100).rounded()),
           "charging": device.batteryState == .charging || device.batteryState == .full])
  }

  private func resumeStatus() {
    guard sink != nil else { return }
    statusActive = true
    UIDevice.current.isBatteryMonitoringEnabled = true
    statusClock.resume()
  }

  private func pauseStatus() {
    statusActive = false
    statusClock.pause()
    UIDevice.current.isBatteryMonitoringEnabled = originalBatteryMonitoring
  }

  private func stopStatus() {
    guard sink != nil else { return }
    pauseStatus()
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers.removeAll()
    sink = nil
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) { stopStatus() }
}

/// A system file open owns only its temporary access scope. Library imports
/// retain their own bookmark; finishing or cancelling never deletes the source.
final class BookOpenInbox {
  static let shared = BookOpenInbox()
  private struct Request {
    let id: String
    let url: URL
    let scoped: Bool
  }
  private let lock = NSLock()
  private var requests = [Request]()
  var onAvailable: (() -> Void)?

  @discardableResult func offer(_ url: URL) -> Bool {
    guard url.isFileURL, BookImportFormatPolicy.extensions.contains(url.pathExtension.lowercased()) else { return false }
    lock.lock()
    if !requests.contains(where: { $0.url == url }) {
      requests.append(Request(id: UUID().uuidString, url: url, scoped: url.startAccessingSecurityScopedResource()))
    }
    lock.unlock()
    DispatchQueue.main.async { self.onAvailable?() }
    return true
  }

  func pending() -> [String: Any]? {
    lock.lock(); defer { lock.unlock() }
    guard let request = requests.first else { return nil }
    let canLocate: Bool
    if #available(iOS 13.0, *) { canLocate = request.scoped } else { canLocate = false }
    return ["id": request.id, "name": request.url.lastPathComponent, "canLink": true,
            "canLocate": canLocate, "canMove": canMove(request)]
  }

  private func canMove(_ request: Request) -> Bool {
    guard request.scoped, ["txt", "epub"].contains(request.url.pathExtension.lowercased()),
          FileManager.default.isDeletableFile(atPath: request.url.path),
          let values = try? request.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
    return values.isRegularFile == true && values.isSymbolicLink != true
  }

  /// Called only after the shared importer has committed and reopened its copy.
  /// Finishing the inbox and staging an import never imply deletion consent.
  func deleteSource(_ id: String, copiedPath: String) throws {
    lock.lock()
    let request = requests.first(where: { $0.id == id })
    lock.unlock()
    guard let request, canMove(request) else {
      throw BookDocumentFailure(code: "move_unavailable", message: "文件来源未允许删除原文件，已保留书库副本")
    }
    let files = FileManager.default
    let copy = URL(fileURLWithPath: copiedPath).standardizedFileURL.resolvingSymlinksInPath()
    let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).resolvingSymlinksInPath()
    guard !copiedPath.isEmpty, copy.path.hasPrefix(home.path + "/"), copy.lastPathComponent == "original",
          copy != request.url.standardizedFileURL.resolvingSymlinksInPath(),
          files.fileExists(atPath: copy.deletingLastPathComponent().appendingPathComponent("book.json").path),
          let values = try? copy.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
          values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
      throw BookDocumentFailure(code: "move_not_deleted", message: "未能确认完整的书库副本，原文件未删除")
    }
    var failure: Error?, coordinationError: NSError?
    var deletionAttempted = false
    NSFileCoordinator().coordinate(readingItemAt: copy, options: [], writingItemAt: request.url,
                                   options: .forDeleting, error: &coordinationError) { saved, source in
      do {
        guard self.canMove(request), try BookOpenMoveFiles.matches(source, saved) else {
          throw BookDocumentFailure(code: "move_not_deleted", message: "原文件已变化或无法核对，原文件未删除")
        }
        deletionAttempted = true
        try files.removeItem(at: source)
      } catch { failure = error }
    }
    if coordinationError != nil || failure != nil || !deletionAttempted {
      throw BookOpenMoveFiles.deletionFailure(attempted: deletionAttempted)
    }
  }

  func source(_ id: String) throws -> URL {
    lock.lock(); defer { lock.unlock() }
    guard let request = requests.first(where: { $0.id == id }) else {
      throw BookDocumentFailure(code: "import_reference", message: "文件打开请求已结束，请从文件应用重新打开")
    }
    return request.url
  }

  func finish(_ id: String) {
    lock.lock()
    let index = requests.firstIndex(where: { $0.id == id })
    let request = index.map { requests.remove(at: $0) }
    lock.unlock()
    if let request, request.scoped { request.url.stopAccessingSecurityScopedResource() }
  }

  deinit {
    for request in requests where request.scoped { request.url.stopAccessingSecurityScopedResource() }
  }
}

/// Compare the committed original with the current source using bounded memory.
/// Short stream reads are filled before comparing; a changed source is retained.
enum BookOpenMoveFiles {
  /// A throwing deletion may have changed the provider; never retry it or
  /// describe its result as a confirmed retained original.
  static func deletionFailure(attempted: Bool) -> BookDocumentFailure {
    BookDocumentFailure(
      code: attempted ? "move_unconfirmed" : "move_not_deleted",
      message: attempted ? "已导入书库，但未能确认原文件是否删除" : "已复制到书库，原文件未删除")
  }

  static func matches(_ source: URL, _ copy: URL) throws -> Bool {
    guard let left = InputStream(url: source), let right = InputStream(url: copy) else {
      throw BookDocumentFailure(code: "move_read", message: "无法核对原文件，原文件未删除")
    }
    left.open(); right.open()
    defer { left.close(); right.close() }
    var sourceBytes = [UInt8](repeating: 0, count: 64 * 1024)
    var copyBytes = sourceBytes
    while true {
      let sourceCount = try readBlock(left, into: &sourceBytes)
      let copyCount = try readBlock(right, into: &copyBytes)
      guard sourceCount == copyCount else { return false }
      if sourceCount == 0 { return true }
      guard sourceBytes.prefix(sourceCount).elementsEqual(copyBytes.prefix(copyCount)) else { return false }
    }
  }

  private static func readBlock(_ stream: InputStream, into bytes: inout [UInt8]) throws -> Int {
    try bytes.withUnsafeMutableBufferPointer { buffer in
      var count = 0
      while count < buffer.count {
        let read = stream.read(buffer.baseAddress!.advanced(by: count), maxLength: buffer.count - count)
        if read < 0 { throw BookDocumentFailure(code: "move_read", message: "无法核对原文件，原文件未删除") }
        if read == 0 { break }
        count += read
      }
      return count
    }
  }
}
