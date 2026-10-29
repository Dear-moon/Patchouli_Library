import Foundation
import Darwin

/// One user-selected, editable document. Called only on document-io. Provider
/// URLs are persistent access references, never owners of removable copies.
final class BookSyncDocument {
  private struct Selection: Codable {
    var bookmark: Data
    var name: String
    var created: Bool
    let id: UUID
  }
  private struct Recovery: Codable {
    let id: UUID
    var before: String { "before-\(id.uuidString).wenku8sync" }
    var next: String { "next-\(id.uuidString).wenku8sync" }
  }
  private struct Transaction {
    let selection: UUID
    let before: URL
    let output: URL
  }

  private let root: URL
  private let files: FileManager
  private let workspace: ManagedBookDocuments
  private let maximumBytes: Int
  private let replace: (URL, URL) throws -> URL
  private var selection: Selection?
  private var loadFailure = false
  private var transaction: Transaction?
  private var recovered: URL?
  private var config: URL { root.appendingPathComponent("selection.json") }
  private var recoveryRoot: URL { root.appendingPathComponent("recovery", isDirectory: true) }
  private var recoveryIndex: URL { recoveryRoot.appendingPathComponent("current.json") }

  init(root: URL, workspace: ManagedBookDocuments, maximumBytes: Int = 256 * 1024 * 1024,
       files: FileManager = .default, replace: ((URL, URL) throws -> URL)? = nil) throws {
    self.root = root
    self.workspace = workspace
    self.maximumBytes = maximumBytes
    self.files = files
    self.replace = replace ?? { original, next in
      try files.replaceItemAt(original, withItemAt: next) ?? original
    }
    try files.createDirectory(at: root, withIntermediateDirectories: true)
    var excluded = root
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try excluded.setResourceValues(values)
    if files.fileExists(atPath: config.path) {
      do { selection = try JSONDecoder().decode(Selection.self, from: Data(contentsOf: config)) }
      catch { loadFailure = true }
    }
  }

  func prepareCreation() throws -> URL {
    try workspace.create(Data(), name: "文库同步.wenku8sync", preserveName: true)
  }

  func releaseCreation(_ url: URL) { _ = try? workspace.release(url.path) }

  func select(_ url: URL, created: Bool) throws -> [String: Any] {
    guard url.pathExtension.lowercased() == "wenku8sync" else {
      throw failure("sync_format", "请选择文库生成的 .wenku8sync 同步文件")
    }
    let scope = url.startAccessingSecurityScopedResource()
    defer { if scope { url.stopAccessingSecurityScopedResource() } }
    try coordinate(url, writing: false) { readable in _ = try self.size(readable) }
    let value = Selection(bookmark: try bookmark(url), name: url.lastPathComponent,
                          created: created, id: UUID())
    try commit(value)
    clearTransaction()
    return try info()!
  }

  func info() throws -> [String: Any]? {
    if loadFailure { throw failure("sync_settings", "同步文件连接无法读取，请重新选择文件") }
    guard let selection else { return nil }
    return try withSelected { url in
      let ubiquitous = (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
      return ["name": url.lastPathComponent, "created": selection.created,
              "authority": "", "provider": ubiquitous ? "iCloud Drive" : "系统文档"]
    }
  }

  func read() throws -> [String: Any] {
    clearTransaction()
    return try withSelected { url in
      var before: URL?, output: URL?
      do {
        try coordinate(url, writing: false) { readable in
          _ = try self.size(readable)
          before = try self.workspace.copy(readable, maximumBytes: self.maximumBytes, kind: "sync-before")
        }
        output = try workspace.create(Data(), name: "sync-next.wenku8sync")
        guard let before, let output, let selection else { throw missing() }
        transaction = Transaction(selection: selection.id, before: before, output: output)
        return ["path": before.path, "size": try size(before), "outputPath": output.path]
      } catch {
        if let before { _ = try? workspace.release(before.path) }
        if let output { _ = try? workspace.release(output.path) }
        throw error
      }
    }
  }

  func write(expectedPath: String, path: String) throws -> Bool {
    guard let transaction, transaction.selection == selection?.id,
      expectedPath == transaction.before.path, path == transaction.output.path else {
      throw failure("sync_transaction", "同步文件连接或暂存已变化，请重新同步")
    }
    guard try size(transaction.output) > 0 else { throw failure("sync_empty", "同步内容为空，未更改云端文件") }
    _ = try size(transaction.before)
    // Freeze Dart's output before examining or writing the provider document.
    let next = try workspace.copy(transaction.output, maximumBytes: maximumBytes, kind: "sync-frozen")
    defer { _ = try? workspace.release(next.path) }
    try withSelected { url in
      try coordinate(url, writing: true) { writable in
        guard try self.equal(transaction.before, writable) else {
          throw self.failure("sync_conflict", "云端文件已发生变化，请重新同步；本地书籍与阅读记录已保留")
        }
        try self.saveRecovery(before: transaction.before, next: next)
        // Use a same-volume replacement so interruption cannot leave a locally
        // truncated document. Both recovery copies are durable before this step.
        do {
          let temporary = try self.files.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                             appropriateFor: writable, create: true)
          defer { try? self.files.removeItem(at: temporary) }
          let replacement = temporary.appendingPathComponent("document.wenku8sync")
          try self.copy(next, to: replacement)
          let actual = try self.replace(writable, replacement)
          guard try self.equal(next, actual) else {
            throw self.failure("sync_write_unconfirmed", "同步文件写入未完整确认，恢复副本已保留，请勿重复覆盖")
          }
          guard var saved = self.selection else { throw self.missing() }
          saved.bookmark = try self.bookmark(actual)
          saved.name = actual.lastPathComponent
          saved.created = false
          try self.commit(saved)
        } catch let error as BookDocumentFailure where error.code == "sync_write_unconfirmed" { throw error }
        catch {
          throw self.failure("sync_write", "同步文件未能完成写入或确认，恢复副本已保留；请检查文件提供器或重新选择文件")
        }
      }
    }
    clearTransaction()
    return true
  }

  func disconnect() throws {
    if files.fileExists(atPath: config.path) { try files.removeItem(at: config) }
    selection = nil
    loadFailure = false
    clearTransaction()
    if let recovered { _ = try? workspace.release(recovered.path) }
    recovered = nil
    // Only the local authorization is removed. The selected file and complete
    // recovery pair remain available, including after relaunch or disconnection.
  }

  func recover(_ which: String) throws -> String? {
    guard ["before", "next"].contains(which) else { throw failure("sync_recovery", "恢复副本类型无效") }
    guard files.fileExists(atPath: recoveryIndex.path) else { return nil }
    let record = try JSONDecoder().decode(Recovery.self, from: Data(contentsOf: recoveryIndex))
    let source = recoveryRoot.appendingPathComponent(which == "before" ? record.before : record.next)
    _ = try size(source)
    let copy = try workspace.copy(source, maximumBytes: maximumBytes, kind: "sync-recovery")
    if let recovered { _ = try? workspace.release(recovered.path) }
    recovered = copy
    return copy.path
  }

  private func saveRecovery(before: URL, next: URL) throws {
    try files.createDirectory(at: recoveryRoot, withIntermediateDirectories: true)
    let old = try? JSONDecoder().decode(Recovery.self, from: Data(contentsOf: recoveryIndex))
    let record = Recovery(id: UUID())
    let first = recoveryRoot.appendingPathComponent(record.before)
    let second = recoveryRoot.appendingPathComponent(record.next)
    var copiedFirst = false, copiedSecond = false
    do {
      try copy(before, to: first)
      copiedFirst = true
      try copy(next, to: second)
      copiedSecond = true
      // Publish one complete pair, never a new "before" with an old "next".
      try JSONEncoder().encode(record).write(to: recoveryIndex, options: .atomic)
    } catch {
      if copiedFirst { try? files.removeItem(at: first) }
      if copiedSecond { try? files.removeItem(at: second) }
      throw error
    }
    if let old {
      try? files.removeItem(at: recoveryRoot.appendingPathComponent(old.before))
      try? files.removeItem(at: recoveryRoot.appendingPathComponent(old.next))
    }
  }

  private func withSelected<T>(_ body: (URL) throws -> T) throws -> T {
    guard !loadFailure, var saved = selection else { throw missing() }
    var stale = false
    let url: URL
    do { url = try URL(resolvingBookmarkData: saved.bookmark, options: .withoutUI,
                        relativeTo: nil, bookmarkDataIsStale: &stale) }
    catch { throw failure("sync_permission", "同步文件访问权限已失效，请重新选择文件；本地数据未删除") }
    let scope = url.startAccessingSecurityScopedResource()
    defer { if scope { url.stopAccessingSecurityScopedResource() } }
    if stale {
      saved.bookmark = try bookmark(url)
      saved.name = url.lastPathComponent
      try commit(saved)
    }
    return try body(url)
  }

  private func bookmark(_ url: URL) throws -> Data {
    try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
  }

  private func commit(_ value: Selection) throws {
    try JSONEncoder().encode(value).write(to: config, options: .atomic)
    selection = value
    loadFailure = false
  }

  private func clearTransaction() {
    if let transaction {
      _ = try? workspace.release(transaction.before.path)
      _ = try? workspace.release(transaction.output.path)
    }
    transaction = nil
  }

  private func coordinate(_ url: URL, writing: Bool, _ body: (URL) throws -> Void) throws {
    var coordinationError: NSError?, bodyError: Error?, completed = false
    let accessor: (URL) -> Void = { actual in
      do { try body(actual); completed = true } catch { bodyError = error }
    }
    let coordinator = NSFileCoordinator()
    // This updates the same logical document, not a Save-As over another one.
    if writing { coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError, byAccessor: accessor) }
    else { coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError, byAccessor: accessor) }
    if let error = bodyError ?? coordinationError { throw error }
    if !completed { throw failure("sync_provider", "文件提供器未完成操作，请稍后重试") }
  }

  private func size(_ url: URL) throws -> Int {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    guard info.st_mode & S_IFMT == S_IFREG else { throw failure("sync_file", "所选同步文件不是普通文件，请重新选择") }
    guard info.st_size >= 0, info.st_size <= maximumBytes else { throw failure("sync_limit", "同步文件超过 256 MB，请减少本地书籍后重试") }
    return Int(info.st_size)
  }

  private func openRead(_ url: URL) throws -> Int32 {
    _ = try size(url)
    let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
    guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    return fd
  }

  private func read(_ fd: Int32, _ buffer: inout [UInt8]) throws -> Int {
    var count: Int
    repeat { count = Darwin.read(fd, &buffer, buffer.count) } while count < 0 && errno == EINTR
    guard count >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    return count
  }

  private func copy(_ source: URL, to destination: URL) throws {
    let input = try openRead(source)
    defer { Darwin.close(input) }
    let output = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard output >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { Darwin.close(output) }
    do {
      var buffer = [UInt8](repeating: 0, count: 65536), total = 0
      while true {
        let count = try read(input, &buffer)
        if count == 0 { break }
        total += count
        guard total <= maximumBytes else { throw failure("sync_limit", "同步文件超过大小限制") }
        try buffer.withUnsafeBytes { raw in
          var offset = 0
          while offset < count {
            let written = Darwin.write(output, raw.baseAddress!.advanced(by: offset), count - offset)
            if written < 0 && errno == EINTR { continue }
            guard written > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            offset += written
          }
        }
      }
      guard fsync(output) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    } catch { try? files.removeItem(at: destination); throw error }
  }

  private func equal(_ left: URL, _ right: URL) throws -> Bool {
    guard try size(left) == size(right) else { return false }
    let a = try openRead(left)
    defer { Darwin.close(a) }
    let b = try openRead(right)
    defer { Darwin.close(b) }
    var x = [UInt8](repeating: 0, count: 65536), y = x, total = 0
    while true {
      let n = try read(a, &x)
      // Regular local files can still have short reads. Fill the other side to
      // the same block length instead of assuming identical read boundaries.
      var offset = 0
      while offset < n {
        var m: Int = 0
        y.withUnsafeMutableBytes { raw in
          repeat { m = Darwin.read(b, raw.baseAddress!.advanced(by: offset), n - offset) } while m < 0 && errno == EINTR
        }
        guard m >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        if m == 0 { return false }
        offset += m
      }
      if n == 0 { return try read(b, &y) == 0 }
      total += n
      guard total <= maximumBytes else { throw failure("sync_limit", "同步文件超过大小限制") }
      if !x.prefix(n).elementsEqual(y.prefix(n)) { return false }
    }
  }

  private func missing() -> BookDocumentFailure { failure("sync_connection", "请先选择同步文件") }
  private func failure(_ code: String, _ text: String) -> BookDocumentFailure { BookDocumentFailure(code: code, message: text) }
}
