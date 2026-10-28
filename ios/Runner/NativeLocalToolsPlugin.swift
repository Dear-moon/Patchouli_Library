import Flutter
import UIKit
import UniformTypeIdentifiers

/// Owns one document/share/album operation. Every completion path releases only its
/// private working copy; cancellation never removes the source document.
final class NativeLocalToolsPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private enum Operation { case importBackup, exportFile, share, saveImage }
  private let registrar: FlutterPluginRegistrar
  private let io = DispatchQueue(label: "org.mewx.wenku8.local-export", qos: .userInitiated)
  private var documents: ManagedBookDocuments?
  private var pending: FlutterResult?
  private var operation: Operation?
  private var output: URL?
  private var originalIdleDisabled: Bool?
  private let photoLibrary = PhotoLibraryImageSaver()

  private init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = NativeLocalToolsPlugin(registrar: registrar)
    let channel = FlutterMethodChannel(name: "org.mewx.wenku8/local_tools", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.publish(plugin)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "keepScreenOn" {
      if call.arguments as? Bool == true {
        if originalIdleDisabled == nil { originalIdleDisabled = UIApplication.shared.isIdleTimerDisabled }
        UIApplication.shared.isIdleTimerDisabled = true
      } else if let previous = originalIdleDisabled {
        UIApplication.shared.isIdleTimerDisabled = previous
        originalIdleDisabled = nil
      }
      result(nil)
      return
    }
    guard ["exportBackup", "importBackup", "shareText", "shareImage", "exportImage", "saveBookImage", "saveImageToGallery"].contains(call.method) else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard pending == nil else {
      result(FlutterError(code: "document_busy", message: "请先完成当前文件或分享操作", details: nil))
      return
    }
    guard presenter() != nil else {
      result(FlutterError(code: "document_unavailable", message: "当前无法打开文件或分享窗口，请返回页面后重试", details: nil))
      return
    }
    pending = result
    let args = call.arguments as? [String: Any] ?? [:]
    if call.method == "importBackup" {
      operation = .importBackup
      let picker: UIDocumentPickerViewController
      if #available(iOS 14.0, *) {
        picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .text, .data], asCopy: false)
      } else { picker = UIDocumentPickerViewController(documentTypes: ["public.json", "public.text", "public.data"], in: .open) }
      present(picker)
      return
    }
    if call.method == "shareText" {
      guard let text = args["text"] as? String else {
        finish(failure: BookDocumentFailure(code: "share_input", message: "缺少要分享的文字")); return
      }
      operation = .share
      share([text])
      return
    }
    let saveToAlbum = ["saveImageToGallery", "exportImage", "saveBookImage"].contains(call.method)
    operation = saveToAlbum ? .saveImage : call.method == "shareImage" ? .share : .exportFile
    let method = call.method
    io.async {
      do {
        let data: Data, name: String
        if method == "exportBackup", let text = args["text"] as? String {
          data = try LibraryExportPolicy.backup(text)
          name = args["name"] as? String ?? "文库备份.json"
        } else if let typed = args["bytes"] as? FlutterStandardTypedData {
          let image = try LibraryExportPolicy.image(typed.data, name: args["name"] as? String ?? "", original: method == "saveBookImage")
          data = image.data
          name = image.name
        } else { throw BookDocumentFailure(code: "export_input", message: "缺少要导出的内容") }
        if saveToAlbum {
          let image = LibraryImageExport(data: data, name: name)
          DispatchQueue.main.async {
            self.photoLibrary.save(image) { response in
              DispatchQueue.main.async {
                switch response {
                case .success: self.finish(value: true)
                case .failure(let failure): self.finish(failure: failure)
                }
              }
            }
          }
          return
        }
        let url = try self.store().create(data, name: name, preserveName: true)
        DispatchQueue.main.async {
          self.output = url
          if method == "shareImage" { self.share([url]); return }
          let picker: UIDocumentPickerViewController
          if #available(iOS 14.0, *) { picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true) }
          else { picker = UIDocumentPickerViewController(url: url, in: .exportToService) }
          self.present(picker)
        }
      } catch { DispatchQueue.main.async { self.finish(failure: error) } }
    }
  }

  private func store() throws -> ManagedBookDocuments {
    if let documents { return documents }
    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let created = try ManagedBookDocuments(root: support.appendingPathComponent(".export-work", isDirectory: true))
    documents = created
    return created
  }

  private func presenter() -> UIViewController? {
    var controller = registrar.viewController
    while let next = controller?.presentedViewController { controller = next }
    return controller
  }

  private func present(_ picker: UIDocumentPickerViewController) {
    guard let controller = presenter() else {
      finish(failure: BookDocumentFailure(code: "document_unavailable", message: "页面已关闭，请返回后重试")); return
    }
    picker.delegate = self
    controller.present(picker, animated: true)
  }

  private func share(_ items: [Any]) {
    guard let controller = presenter() else {
      finish(failure: BookDocumentFailure(code: "share_unavailable", message: "页面已关闭，请返回后重试")); return
    }
    let share = UIActivityViewController(activityItems: items, applicationActivities: nil)
    share.popoverPresentationController?.sourceView = controller.view
    share.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
    share.completionWithItemsHandler = { [weak self] _, _, _, error in
      DispatchQueue.main.async { self?.finish(failure: error) }
    }
    controller.present(share, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(value: operation == .importBackup ? nil : false)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard pending != nil else { return }
    if operation == .exportFile { finish(value: !urls.isEmpty); return }
    guard operation == .importBackup, let source = urls.first else { finish(); return }
    io.async {
      do {
        let scope = source.startAccessingSecurityScopedResource()
        defer { if scope { source.stopAccessingSecurityScopedResource() } }
        let workspace = try self.store()
        var staged: URL?, failure: Error?, coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
          do { staged = try workspace.copy(readable, maximumBytes: LibraryExportPolicy.backupLimit) }
          catch { failure = error }
        }
        defer { if let url = staged { _ = try? workspace.release(url.path) } }
        if let error = coordinationError ?? failure { throw error }
        guard let staged, let text = String(data: try Data(contentsOf: staged), encoding: .utf8) else {
          throw BookDocumentFailure(code: "backup_encoding", message: "备份不是有效的 UTF-8 文本，请重新选择文库备份")
        }
        DispatchQueue.main.async { self.finish(value: text) }
      } catch { DispatchQueue.main.async { self.finish(failure: error) } }
    }
  }

  private func finish(value: Any? = nil, failure: Error? = nil) {
    guard let result = pending else { return }
    let original = output
    output = nil
    pending = nil
    operation = nil
    if let url = original { io.async { _ = try? self.store().release(url.path) } }
    if let failure {
      let error = failure as NSError
      result(FlutterError(code: (failure as? BookDocumentFailure)?.code ?? "local_document", message: failure.localizedDescription,
        details: ["stage": "ios_local_tools", "domain": error.domain, "code": error.code]))
    } else { result(value) }
  }
}
