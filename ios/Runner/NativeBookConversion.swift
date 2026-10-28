import Foundation
import WenkuBookEngine

/// The Dart importer owns this quarantine. Native export may only write a fresh
/// empty OEBPS directory inside its job, never a selected source or arbitrary URL.
final class NativeBookConversion {
  let documents: ManagedBookDocuments
  let portableRoot: URL
  init(documents: ManagedBookDocuments, portableRoot: URL) {
    self.documents = documents
    self.portableRoot = portableRoot.standardizedFileURL.resolvingSymlinksInPath()
  }

  func destination(_ path: String, kind: String = "kindle") throws -> URL {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let prefix = portableRoot.path + "/"
    guard url.path.hasPrefix(prefix), url.resolvingSymlinksInPath().path == url.path else {
      throw BookDocumentFailure(code: "conversion_path", message: "转换暂存目录无效，请重新导入")
    }
    let parts = String(url.path.dropFirst(prefix.count)).split(separator: "/")
    guard ["kindle", "pdf"].contains(kind), parts.count == 3, parts[0].hasPrefix("job-"), parts[1].hasPrefix(kind + "-"), parts[2] == "OEBPS" else {
      throw BookDocumentFailure(code: "conversion_path", message: "转换只能写入本次导入的暂存目录")
    }
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    guard attrs[.type] as? FileAttributeType == .typeDirectory,
      try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty else {
      throw BookDocumentFailure(code: "conversion_path", message: "转换暂存目录不是空目录，请重试")
    }
    return url
  }

  func extractKindle(_ path: String, output: String) throws -> Int {
    let source = try documents.readableSourceURL(path)
    let attrs = try FileManager.default.attributesOfItem(atPath: source.path)
    guard attrs[.type] as? FileAttributeType == .typeRegular,
      let length = attrs[.size] as? NSNumber, length.int64Value > 0,
      length.int64Value <= 256 * 1024 * 1024 else {
      throw BookDocumentFailure(code: "file_too_large", message: "Kindle 原书为空或超过 256 MiB")
    }
    let directory = try destination(output)
    return Int(source.path.withCString { input in
      directory.path.withCString { destination in wenku_export_mobi(input, destination) }
    })
  }

  func extractPdf(_ path: String, output: String, name: String) throws {
    let source = try documents.readableSourceURL(path)
    let attrs = try FileManager.default.attributesOfItem(atPath: source.path)
    guard attrs[.type] as? FileAttributeType == .typeRegular,
      let length = attrs[.size] as? NSNumber, length.int64Value > 0,
      length.int64Value <= 512 * 1024 * 1024 else {
      throw BookDocumentFailure(code: "file_too_large", message: "PDF 原书为空或超过 512 MiB")
    }
    try NativePdfImport(source: source, name: name).write(to: destination(output, kind: "pdf"))
  }
}
