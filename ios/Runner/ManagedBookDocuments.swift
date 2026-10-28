import Foundation
import CoreFoundation
import Darwin

struct BookDocumentFailure: LocalizedError {
  let code: String
  let message: String
  var errorDescription: String? { message }
}

/// Owns only working copies. Provider URLs and original user files never enter
/// the deletion set. Copies and text conversion use bounded streaming buffers.
final class ManagedBookDocuments {
  private static let processRun = UUID()
  private static let ownershipAttribute = "org.mewx.wenku8.import-work-v1"
  let root: URL
  private let files: FileManager
  private let readableRoots: [URL]
  private let runIdentifier: UUID
  private var owned = Set<String>()

  init(root: URL, readableRoots: [URL] = [], files: FileManager = .default,
    runIdentifier: UUID? = nil) throws {
    self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    self.files = files
    self.readableRoots = readableRoots.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
    self.runIdentifier = runIdentifier ?? Self.processRun
    try files.createDirectory(at: self.root, withIntermediateDirectories: true)
    var excluded = self.root
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try excluded.setResourceValues(values)
    reclaimAbandonedCopies()
  }

  func copy(_ source: URL, maximumBytes: Int, kind: String = "import") throws -> URL {
    let input = try FileHandle(forReadingFrom: source)
    defer { try? input.close() }
    return try copy(input, maximumBytes: maximumBytes, kind: kind)
  }

  func copy(_ input: FileHandle, maximumBytes: Int, kind: String = "import") throws -> URL {
    let output = try allocate(kind: kind, extension: "source")
    do {
      let sink = try FileHandle(forWritingTo: output)
      defer { try? sink.close() }
      var total = 0
      while case let bytes = try read(input, count: 262144), !bytes.isEmpty {
        total += bytes.count
        guard total <= maximumBytes else {
          throw BookDocumentFailure(code: "file_too_large", message: "文件超过此格式的导入大小限制")
        }
        try write(bytes, to: sink)
      }
      return output
    } catch {
      _ = try? release(output.path)
      throw error
    }
  }

  func create(_ data: Data, name: String, preserveName: Bool = false) throws -> URL {
    let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters))
      .joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    let safe = String((cleaned.isEmpty ? "文库导出" : cleaned).prefix(100))
    let filename = URL(fileURLWithPath: safe)
    let suffix = filename.pathExtension.isEmpty ? "data" : filename.pathExtension
    let stem = filename.deletingPathExtension().lastPathComponent
    let output = preserveName
      ? try allocateFile(filename: "\(stem).\(suffix)")
      : try allocate(kind: stem, extension: suffix)
    do {
      let sink = try FileHandle(forWritingTo: output)
      defer { try? sink.close() }
      try write(data, to: sink)
      return output
    } catch {
      _ = try? release(output.path)
      throw error
    }
  }

  @discardableResult
  func release(_ path: String) throws -> Bool {
    let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    guard owned.contains(url.path), url.deletingLastPathComponent().path == root.path else { return false }
    if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
    owned.remove(url.path)
    return true
  }

  static func decodeBookNames(_ values: [Data]) throws -> [String] {
    guard values.count <= 64, values.allSatisfy({ !$0.isEmpty && $0.count <= 4096 }) else {
      throw BookDocumentFailure(code: "zip_name", message: "ZIP 文件名数据无效")
    }
    let encodings: [String.Encoding] = [.utf8,
      String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
      String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)))]
    return try values.map { data in
      for encoding in encodings { if let name = String(data: data, encoding: encoding) { return name } }
      throw BookDocumentFailure(code: "zip_name", message: "无法识别 ZIP 文件名编码，请使用 UTF-8 文件名重新压缩")
    }
  }

  func decodeTextFile(_ path: String, encoding: String,
    maximumBytes: Int = 128 * 1024 * 1024,
    maximumOutputBytes: Int = 384 * 1024 * 1024) throws -> URL {
    guard maximumBytes > 0, maximumBytes <= 1024 * 1024 * 1024,
      maximumOutputBytes > 0, maximumOutputBytes <= 1024 * 1024 * 1024 else {
      throw BookDocumentFailure(code: "file_limit", message: "文档转换大小限制无效")
    }
    let source = try readableSourceURL(path)
    let input = try FileHandle(forReadingFrom: source)
    defer { try? input.close() }
    let sample = try read(input, count: 65536)
    try input.seek(toOffset: 0)
    let selected = try Self.resolveEncoding(encoding, sample: sample)
    guard let converter = iconv_open("UTF-8", selected), converter != OpaquePointer(bitPattern: -1) else {
      throw BookDocumentFailure(code: "text_encoding", message: "系统不支持所选文字编码，请改用其他编码")
    }
    defer { iconv_close(converter) }
    let output = try allocate(kind: "decoded", extension: "txt")
    do {
      let sink = try FileHandle(forWritingTo: output)
      defer { try? sink.close() }
      var pending = Data(), total = 0, produced = 0
      while case let chunk = try read(input, count: 65536), !chunk.isEmpty {
        total += chunk.count
        guard total <= maximumBytes else {
          throw BookDocumentFailure(code: "file_too_large", message: "文本超过转换大小限制，请拆分后导入")
        }
        pending.append(chunk)
        var consumed = 0
        try pending.withUnsafeMutableBytes { raw in
          var pointer = raw.baseAddress?.assumingMemoryBound(to: Int8.self)
          var remaining = raw.count
          while remaining > 0 {
            var bytes = [Int8](repeating: 0, count: 65536)
            var available = bytes.count
            let result = bytes.withUnsafeMutableBufferPointer { destination -> Int in
              var next = destination.baseAddress
              return iconv(converter, &pointer, &remaining, &next, &available)
            }
            let conversionError = errno
            if available < bytes.count {
              produced += bytes.count - available
              guard produced <= maximumOutputBytes else {
                throw BookDocumentFailure(code: "file_too_large", message: "解码后的文档超过大小限制，请拆分后导入")
              }
              try bytes.withUnsafeBytes { buffer in
                try write(Data(buffer.prefix(bytes.count - available)), to: sink)
              }
            }
            if result == -1 {
              if conversionError == E2BIG { continue }
              if conversionError == EINVAL { break } // A multibyte character crosses the next chunk.
              throw BookDocumentFailure(code: "text_encoding", message: "文字编码不匹配，请在导入设置中选择原书编码")
            }
          }
          consumed = raw.count - remaining
        }
        pending.removeFirst(consumed)
      }
      guard pending.isEmpty else {
        throw BookDocumentFailure(code: "text_encoding", message: "文本末尾存在不完整字符，请检查文件或文字编码")
      }
      return output
    } catch {
      _ = try? release(output.path)
      throw error
    }
  }

  func readableSourceURL(_ path: String) throws -> URL {
    let source = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    guard owned.contains(source.path) || readableRoots.contains(where: {
      source.path.hasPrefix($0.path + "/")
    }) else {
      throw BookDocumentFailure(code: "unowned_document", message: "导入文件的访问授权已失效，请重新选择")
    }
    return source
  }

  // POSIX-backed bounded reads/writes also work on iOS 13.0–13.3, where the
  // throwing FileHandle convenience methods are unavailable.
  private func read(_ handle: FileHandle, count: Int) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    var length: Int
    repeat { length = Darwin.read(handle.fileDescriptor, &bytes, count) } while length < 0 && errno == EINTR
    guard length >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    return Data(bytes.prefix(length))
  }

  private func write(_ bytes: Data, to handle: FileHandle) throws {
    try bytes.withUnsafeBytes { raw in
      var offset = 0
      while offset < raw.count {
        let count = Darwin.write(handle.fileDescriptor, raw.baseAddress!.advanced(by: offset), raw.count - offset)
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        offset += count
      }
    }
  }

  private func allocate(kind: String, extension suffix: String) throws -> URL {
    try allocateFile(filename: "\(kind)-\(UUID().uuidString).\(suffix)")
  }

  private func allocateFile(filename: String) throws -> URL {
    let url = root.appendingPathComponent(filename)
    // A user-facing export keeps its proposed name. Reserve it exclusively;
    // another active export, unmarked file or symlink must never be replaced.
    let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    defer { Darwin.close(descriptor) }
    owned.insert(url.standardizedFileURL.resolvingSymlinksInPath().path)
    do {
      // Persist ownership before writing any book bytes. A new process may
      // reclaim this copy; another engine in the same process must leave it.
      let marker = Data(runIdentifier.uuidString.utf8)
      let status = marker.withUnsafeBytes { bytes in
        fsetxattr(descriptor, Self.ownershipAttribute, bytes.baseAddress, bytes.count, 0, 0)
      }
      guard status == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    } catch {
      _ = try? release(url.path)
      throw error
    }
    return url
  }

  private func reclaimAbandonedCopies() {
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
    guard let candidates = try? files.contentsOfDirectory(at: root,
      includingPropertiesForKeys: Array(keys)) else { return }
    for candidate in candidates {
      guard let values = try? candidate.resourceValues(forKeys: keys),
        values.isRegularFile == true, values.isSymbolicLink != true else { continue }
      // No filename/age heuristic and no recursive deletion. Older unmarked
      // files, provider URLs and other owners' directories remain untouched.
      var marker = [UInt8](repeating: 0, count: 36)
      let length = marker.withUnsafeMutableBytes { bytes in
        getxattr(candidate.path, Self.ownershipAttribute, bytes.baseAddress, bytes.count, 0, XATTR_NOFOLLOW)
      }
      guard length == marker.count,
        let text = String(bytes: marker, encoding: .utf8),
        let previous = UUID(uuidString: text), previous != runIdentifier else { continue }
      // Failure leaves its ownership marker available for the next opening;
      // it must not make an otherwise usable import fail at startup.
      try? files.removeItem(at: candidate)
    }
  }

  static func resolveEncoding(_ value: String, sample: Data) throws -> String {
    let supported = ["UTF-8", "GB18030", "Big5", "Big5-HKSCS", "UTF-16LE", "UTF-16BE",
      "SHIFT_JIS", "CP932", "EUC-JP", "KOI8-R", "ISO-8859-1",
      "WINDOWS-1250", "WINDOWS-1251", "WINDOWS-1252", "WINDOWS-1253", "WINDOWS-1254",
      "WINDOWS-1255", "WINDOWS-1256", "WINDOWS-1257", "WINDOWS-1258"]
    if value != "auto" {
      guard supported.contains(value) else {
        throw BookDocumentFailure(code: "text_encoding", message: "不支持此文字编码")
      }
      return value
    }
    if sample.starts(with: [0xff, 0xfe]) { return "UTF-16LE" }
    if sample.starts(with: [0xfe, 0xff]) { return "UTF-16BE" }
    for trailing in 0...min(3, sample.count) {
      if String(data: sample.dropLast(trailing), encoding: .utf8) != nil { return "UTF-8" }
    }
    var converted: NSString?
    let detected = NSString.stringEncoding(for: sample, encodingOptions: [
      .suggestedEncodingsKey: [
        String.Encoding.utf8.rawValue,
        CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)),
        CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
      ],
      .allowLossyKey: false
    ], convertedString: &converted, usedLossyConversion: nil)
    if detected != 0 {
      let cf = CFStringConvertNSStringEncodingToEncoding(detected)
      if let name = CFStringConvertEncodingToIANACharSetName(cf) as String?,
         supported.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
        return name
      }
    }
    throw BookDocumentFailure(code: "text_encoding", message: "无法识别文字编码，请在导入设置中选择")
  }
}
