import Foundation
import CryptoKit
import Darwin

/// Durable, read-only grants. A live lease owns the descriptor and security
/// scope until Dart has finished reading it; revocation never deletes a book.
final class LinkedBookDocuments {
  private struct Grant: Codable {
    let version: Int
    var bookmark: Data
    let relativePath: String?
    let name: String
  }
  private struct Lease {
    let handle: FileHandle
    let scope: URL
    let scoped: Bool
    let name: String
    let size: Int
    let modified: Int64
    func close() {
      try? handle.close()
      if scoped { scope.stopAccessingSecurityScopedResource() }
    }
  }
  private let root: URL
  private let files: FileManager
  private var leases = [String: Lease]()

  init(root: URL, files: FileManager = .default) throws {
    self.root = root
    self.files = files
    try files.createDirectory(at: root, withIntermediateDirectories: true)
  }
  deinit { for lease in leases.values { lease.close() } }

  func retain(_ source: URL, relativeTo parent: URL? = nil, name: String? = nil) throws -> [String: Any] {
    let scope = parent ?? source
    let scoped = scope.startAccessingSecurityScopedResource()
    defer { if scoped { scope.stopAccessingSecurityScopedResource() } }
    let canonical = source.standardizedFileURL.resolvingSymlinksInPath()
    guard source.isFileURL, canonical.path == source.standardizedFileURL.path else { throw unavailable() }
    let relative: String?
    if let parent {
      let base = parent.standardizedFileURL.resolvingSymlinksInPath().path
      guard canonical.path.hasPrefix(base + "/") else { throw unavailable() }
      relative = String(canonical.path.dropFirst(base.count + 1))
    } else { relative = nil }
    let label = name ?? source.lastPathComponent
    let grant = Grant(version: 1,
      bookmark: try scope.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil),
      relativePath: relative, name: label)
    // Validate the selection before persisting an otherwise unused grant.
    let probe = try openURL(source, scope: scope, scoped: false, name: label, expected: [:])
    probe.close()
    let reference = UUID().uuidString
    try JSONEncoder().encode(grant).write(to: record(reference), options: .atomic)
    return ["name": label, "reference": reference]
  }

  func open(_ args: [String: Any]) throws -> [String: Any] {
    if args["purpose"] != nil && args["purpose"] as? String != "text-index" {
      throw BookDocumentFailure(code: "linked_input", message: "原文件读取用途无效")
    }
    let lease = try acquire(args)
    let token = UUID().uuidString
    leases[token] = lease
    var result: [String: Any] = ["lease": token, "descriptor": Int(lease.handle.fileDescriptor),
                                "size": lease.size, "modified": lease.modified]
    if args["purpose"] as? String == "text-index" { result["offset"] = 0 }
    return result
  }
  func close(_ token: String) { leases.removeValue(forKey: token)?.close() }
  func release(_ reference: String) throws {
    let file = try record(reference)
    if files.fileExists(atPath: file.path) { try files.removeItem(at: file) }
  }
  func stage(_ reference: String, workspace: ManagedBookDocuments) throws -> [String: Any] {
    let lease = try acquire(["reference": reference])
    defer { lease.close() }
    let copy = try workspace.copy(lease.handle, maximumBytes: BookImportFormatPolicy.byteLimit((lease.name as NSString).pathExtension))
    return ["name": lease.name, "path": copy.path]
  }

  func inspectText(_ args: [String: Any]) throws -> [String: Any] {
    let lease = try acquire(args)
    defer { lease.close() }
    guard lease.size <= 128 * 1024 * 1024 else {
      throw BookDocumentFailure(code: "file_too_large", message: "TXT 超过 128 MiB，请拆分原文件后导入")
    }
    let sample = try bytes(lease, offset: 0, count: min(65536, lease.size))
    let encoding = try ManagedBookDocuments.resolveEncoding(args["encoding"] as? String ?? "auto", sample: sample)
    var digest = SHA256()
    digest.update(data: sample)
    var offset = sample.count
    while offset < lease.size {
      let chunk = try bytes(lease, offset: offset, count: min(65536, lease.size - offset))
      guard !chunk.isEmpty else { throw changed() }
      digest.update(data: chunk)
      offset += chunk.count
    }
    try verify(lease, expected: ["size": lease.size, "modified": lease.modified])
    return ["reference": args["reference"] as? String ?? "", "encoding": encoding,
            "size": lease.size, "modified": lease.modified,
            "digest": digest.finalize().map { String(format: "%02x", $0) }.joined()]
  }

  func readBytes(_ args: [String: Any]) throws -> Data {
    let lease = try acquire(args)
    defer { lease.close() }
    let offset = try validOffset(args, size: lease.size)
    return try bytes(lease, offset: offset, count: min(65536, lease.size - offset))
  }

  func readText(_ args: [String: Any]) throws -> [String: Any] {
    let lease = try acquire(args)
    defer { lease.close() }
    let offset = try validOffset(args, size: lease.size)
    let input = try bytes(lease, offset: offset, count: min(65536, lease.size - offset))
    let encoding = try ManagedBookDocuments.resolveEncoding(args["encoding"] as? String ?? "auto", sample: input)
    guard let converter = iconv_open("UTF-16LE", encoding), converter != OpaquePointer(bitPattern: -1) else {
      throw BookDocumentFailure(code: "text_encoding", message: "系统不支持所选文字编码，请重新选择编码")
    }
    defer { iconv_close(converter) }
    var units = [UInt16](repeating: 0, count: 32768)
    var remaining = input.count, available = units.count * 2
    let status = input.withUnsafeBytes { raw -> Int in
      var source = UnsafeMutablePointer(mutating: raw.baseAddress?.assumingMemoryBound(to: Int8.self))
      return units.withUnsafeMutableBytes { output in
        var target = output.baseAddress?.assumingMemoryBound(to: Int8.self)
        return iconv(converter, &source, &remaining, &target, &available)
      }
    }
    let code = errno
    let consumed = input.count - remaining
    guard consumed > 0, available < units.count * 2,
      status != -1 || code == E2BIG || code == EINVAL && offset + input.count < lease.size else {
      throw BookDocumentFailure(code: "text_encoding", message: "原文件或文字编码已变化，请重新定位原文件或选择正确编码")
    }
    let text = String(decoding: units.prefix((units.count * 2 - available) / 2).map(UInt16.init(littleEndian:)), as: UTF16.self)
    try verify(lease, expected: ["size": lease.size, "modified": lease.modified])
    return ["textBytes": Data(text.utf8), "next": offset + consumed]
  }

  private func acquire(_ args: [String: Any]) throws -> Lease {
    guard let reference = args["reference"] as? String else { throw unavailable() }
    let file = try record(reference)
    let grant: Grant
    do {
      let data = try Data(contentsOf: file)
      guard data.count <= 64 * 1024 else { throw unavailable() }
      grant = try JSONDecoder().decode(Grant.self, from: data)
      guard grant.version == 1 else { throw unavailable() }
    } catch { throw unavailable() }
    var stale = false
    let scope: URL
    do { scope = try URL(resolvingBookmarkData: grant.bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale) }
    catch { throw unavailable() }
    let scoped = scope.startAccessingSecurityScopedResource()
    do {
      let source: URL
      if let relative = grant.relativePath {
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else { throw unavailable() }
        source = scope.appendingPathComponent(relative)
        guard source.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(scope.standardizedFileURL.resolvingSymlinksInPath().path + "/") else { throw unavailable() }
      } else { source = scope }
      let lease = try openURL(source, scope: scope, scoped: scoped, name: grant.name, expected: args)
      if stale {
        do {
          var updated = grant
          updated.bookmark = try scope.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
          try JSONEncoder().encode(updated).write(to: file, options: .atomic)
        } catch { try? lease.handle.close(); throw error }
      }
      return lease
    } catch {
      if scoped { scope.stopAccessingSecurityScopedResource() }
      if let failure = error as? BookDocumentFailure { throw failure }
      throw unavailable()
    }
  }

  private func openURL(_ source: URL, scope: URL, scoped: Bool, name: String, expected: [String: Any]) throws -> Lease {
    var value: Lease?, failure: Error?, coordination: NSError?
    NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordination) { readable in
      do {
        let fd = Darwin.open(readable.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw unavailable() }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
          var stat = Darwin.stat()
          guard fstat(fd, &stat) == 0, stat.st_mode & S_IFMT == S_IFREG,
            stat.st_size > 0, stat.st_size <= BookImportFormatPolicy.byteLimit((name as NSString).pathExtension) else {
            throw unavailable()
          }
          let candidate = Lease(handle: handle, scope: scope, scoped: scoped, name: name,
            size: Int(stat.st_size), modified: Self.modified(stat))
          try verify(candidate, expected: expected)
          value = candidate
        } catch { try? handle.close(); throw error }
      } catch { failure = error }
    }
    if let failure { throw failure }
    guard coordination == nil, let value else { throw unavailable() }
    return value
  }

  private func verify(_ lease: Lease, expected: [String: Any]) throws {
    var stat = Darwin.stat()
    guard fstat(lease.handle.fileDescriptor, &stat) == 0,
      stat.st_size == lease.size, Self.modified(stat) == lease.modified,
      expected["size"] == nil || (expected["size"] as? NSNumber)?.intValue == lease.size,
      expected["modified"] == nil || (expected["modified"] as? NSNumber)?.int64Value == lease.modified else { throw changed() }
  }
  private func bytes(_ lease: Lease, offset: Int, count: Int) throws -> Data {
    var output = [UInt8](repeating: 0, count: count), done = 0
    try output.withUnsafeMutableBytes { raw in
      while done < count {
        let size = pread(lease.handle.fileDescriptor, raw.baseAddress!.advanced(by: done), count - done, off_t(offset + done))
        if size < 0 && errno == EINTR { continue }
        guard size > 0 else { throw changed() }
        done += size
      }
    }
    return Data(output)
  }
  private func validOffset(_ args: [String: Any], size: Int) throws -> Int {
    guard let offset = args["offset"] as? Int, offset >= 0, offset < size else { throw changed() }
    return offset
  }
  private static func modified(_ stat: Darwin.stat) -> Int64 {
    Int64(stat.st_mtimespec.tv_sec) * 1000 + Int64(stat.st_mtimespec.tv_nsec) / 1_000_000
  }
  private func record(_ reference: String) throws -> URL {
    guard UUID(uuidString: reference) != nil else { throw unavailable() }
    return root.appendingPathComponent(reference + ".json")
  }
  private func unavailable() -> BookDocumentFailure {
    BookDocumentFailure(code: "linked_permission", message: "无法访问原文件，请重新定位原文件，或选择「复制到应用」")
  }
  private func changed() -> BookDocumentFailure {
    BookDocumentFailure(code: "linked_changed", message: "原文件已变化，请重新定位；原有阅读进度与书签仍保留")
  }
}
