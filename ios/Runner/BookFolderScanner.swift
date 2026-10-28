import Foundation

enum BookImportFormatPolicy {
  static let extensions: Set<String> = ["epub", "txt", "mobi", "azw", "azw3", "prc", "fb2", "pdf", "docx", "rtf", "html", "htm", "xhtml", "md", "markdown", "zip"]

  static func byteLimit(_ suffix: String) -> Int {
    switch suffix.lowercased() {
    case "epub", "pdf", "docx", "zip": return 512 * 1024 * 1024
    case "mobi", "azw", "azw3", "prc": return 256 * 1024 * 1024
    case "html", "htm", "xhtml", "md", "markdown": return 32 * 1024 * 1024
    default: return 128 * 1024 * 1024
    }
  }
}

/// One read-only, user-authorized directory. All methods run on document-io.
/// Scanning reads metadata only; an explicit selection stages one working copy.
/// Provider URLs/bookmarks stay on this host and never become deletion owners.
final class BookFolderScanner {
  private struct Settings: Codable {
    var bookmark: Data?
    var name = "书籍文件夹"
    var applicationDocuments = false
    var automatic = false
    var formats = BookImportFormatPolicy.extensions
    var imported = [String: String]()
  }

  private struct Entry {
    let relativePath: String
    let name: String
    let size: Int?
    let modified: Date?
    var revision: String? {
      guard let size, let modified else { return nil }
      return "\(size):\(modified.timeIntervalSince1970)"
    }
  }

  private let stateFile: URL
  private let documentsDirectory: URL
  private let maximumDocuments: Int
  private let files: FileManager
  private var settings: Settings
  private var loadFailure = false
  private var entries = [String: Entry]()
  private var staged = Set<String>()
  private var pendingMarks = 0
  private static let keys: Set<URLResourceKey> = [
    .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey,
    .fileSizeKey, .contentModificationDateKey,
  ]

  init(stateFile: URL, documentsDirectory: URL, maximumDocuments: Int = 20_000,
       files: FileManager = .default) throws {
    self.stateFile = stateFile
    self.documentsDirectory = documentsDirectory
    self.maximumDocuments = maximumDocuments
    self.files = files
    if files.fileExists(atPath: stateFile.path) {
      do { settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: stateFile)) }
      catch { settings = Settings(); loadFailure = true }
    } else { settings = Settings() }
  }

  func info() throws -> [String: Any]? {
    guard !loadFailure else {
      throw BookDocumentFailure(code: "scan_settings", message: "扫描配置无法读取，请重新选择扫描范围")
    }
    guard settings.applicationDocuments || settings.bookmark != nil else { return nil }
    let readable = (try? withRoot { _ in true }) ?? false
    return ["name": settings.name, "all": settings.applicationDocuments,
            "automatic": settings.automatic, "readable": readable]
  }

  func select(_ url: URL) throws -> [String: Any] {
    let scope = url.startAccessingSecurityScopedResource()
    defer { if scope { url.stopAccessingSecurityScopedResource() } }
    try requireDirectory(url)
    let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    // Finish the old successful acknowledgements before changing their scope.
    try checkpoint()
    var next = settings
    let old = try? resolvedRoot().url.standardizedFileURL.resolvingSymlinksInPath()
    if settings.applicationDocuments || old?.path != url.standardizedFileURL.resolvingSymlinksInPath().path {
      next.imported = [:]
    }
    next.bookmark = bookmark
    next.name = url.lastPathComponent
    next.applicationDocuments = false
    try commit(next)
    clearSession()
    return try info()!
  }

  func selectApplicationDocuments() throws -> [String: Any] {
    try files.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
    try checkpoint()
    var next = settings
    if !next.applicationDocuments { next.imported = [:] }
    next.bookmark = nil
    next.name = "全部应用文档"
    next.applicationDocuments = true
    try commit(next)
    clearSession()
    return try info()!
  }

  func formats() -> [String] { settings.formats.sorted() }

  func setFormats(_ values: [String]) throws {
    let chosen = Set(values.map { $0.lowercased() })
    guard !chosen.isEmpty, chosen.isSubset(of: BookImportFormatPolicy.extensions) else {
      throw BookDocumentFailure(code: "scan_formats", message: "请至少选择一种支持的格式")
    }
    try checkpoint()
    var next = settings
    next.formats = chosen
    try commit(next)
    clearSession()
  }

  func setAutomatic(_ value: Bool) throws {
    var next = settings
    next.automatic = value
    try commit(next)
  }

  func disconnect() throws {
    try commit(Settings())
    clearSession()
  }

  func scan() throws -> [String: Any] {
    try finish()
    return try withRoot { root in
      var records = [Entry](), warnings = [String](), visited = 0
      var coordinationError: NSError?, scanError: Error?
      NSFileCoordinator().coordinate(readingItemAt: root, options: [], error: &coordinationError) { readable in
        do {
          let base = readable.standardizedFileURL.resolvingSymlinksInPath()
          guard let enumerator = files.enumerator(at: base,
            includingPropertiesForKeys: Array(Self.keys), options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, _ in
              if warnings.count < 8 { warnings.append("\(url.lastPathComponent)：暂时无法读取，可稍后重新扫描") }
              return true
            }) else {
            throw BookDocumentFailure(code: "scan_read", message: "文件夹暂时无法读取，请重新选择或稍后重试")
          }
          while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited > maximumDocuments {
              warnings.append("文件过多，请选择更小的书籍文件夹继续扫描")
              break
            }
            if enumerator.level > 64 { enumerator.skipDescendants(); continue }
            do {
              let values = try url.resourceValues(forKeys: Self.keys)
              if values.isSymbolicLink == true || !url.resolvingSymlinksInPath().path.hasPrefix(base.path + "/") {
                // Calling skipDescendants on a file also skips the next
                // directory on Foundation's enumerator. Links aren't followed.
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
              }
              guard values.isRegularFile == true,
                settings.formats.contains(url.pathExtension.lowercased()) else { continue }
              let relative = String(url.path.dropFirst(base.path.count + 1))
              records.append(Entry(relativePath: relative, name: url.lastPathComponent,
                size: values.fileSize, modified: values.contentModificationDate))
            } catch {
              if warnings.count < 8 { warnings.append("\(url.lastPathComponent)：无法读取文件信息") }
            }
          }
        } catch { scanError = error }
      }
      if let error = coordinationError ?? scanError { throw error }
      var books = [[String: Any]](), unchanged = 0
      for entry in records.sorted(by: { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }) {
        if let revision = entry.revision, settings.imported[entry.relativePath] == revision {
          unchanged += 1
          continue
        }
        let token = UUID().uuidString
        entries[token] = entry
        var value: [String: Any] = ["token": token, "name": entry.name,
          "folder": String((entry.relativePath as NSString).deletingLastPathComponent.suffix(240))]
        if let size = entry.size { value["size"] = size }
        books.append(value)
      }
      return ["books": books, "total": records.count, "unchanged": unchanged, "warnings": warnings]
    }
  }

  func stage(_ token: String, documents: ManagedBookDocuments) throws -> [String: Any] {
    try selected(token) { source, _, name in
      let copied = try documents.copy(source, maximumBytes: BookImportFormatPolicy.byteLimit((name as NSString).pathExtension))
      return ["name": name, "path": copied.path]
    }
  }

  func link(_ token: String, documents: LinkedBookDocuments) throws -> [String: Any] {
    try selected(token) { source, root, name in
      try documents.retain(source, relativeTo: root, name: name)
    }
  }

  private func selected(_ token: String, read: (URL, URL, String) throws -> [String: Any]) throws -> [String: Any] {
    guard let entry = entries[token] else { throw expired() }
    let result: [String: Any] = try withRoot { root in
      let base = root.standardizedFileURL.resolvingSymlinksInPath()
      let source = base.appendingPathComponent(entry.relativePath)
      let canonical = source.standardizedFileURL.resolvingSymlinksInPath()
      guard canonical.path.hasPrefix(base.path + "/"),
        source.standardizedFileURL.path == canonical.path else { throw expired() }
      var selected: [String: Any]?, coordinationError: NSError?, copyError: Error?
      NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
        do {
          let values = try readable.resourceValues(forKeys: Self.keys)
          guard values.isRegularFile == true, values.isSymbolicLink != true,
            values.fileSize == entry.size, values.contentModificationDate == entry.modified else {
            throw BookDocumentFailure(code: "scan_changed", message: "文件在扫描后发生了变化，请重新扫描再导入")
          }
          selected = try read(readable, root, entry.name)
        } catch { copyError = error }
      }
      if let error = coordinationError ?? copyError { throw error }
      guard let selected else { throw expired() }
      return selected
    }
    staged.insert(token)
    return result
  }

  func markImported(_ token: String) throws {
    guard let entry = entries[token], staged.contains(token) else { throw expired() }
    // Missing provider timestamps are never treated as a reliable unchanged file.
    if let revision = entry.revision {
      settings.imported[entry.relativePath] = revision
      pendingMarks += 1
      if pendingMarks >= 16 { try checkpoint() }
    }
  }

  func finish() throws {
    try checkpoint()
    clearSession()
  }

  private func clearSession() { entries.removeAll(); staged.removeAll() }

  private func checkpoint() throws {
    guard pendingMarks > 0 else { return }
    try commit(settings)
    pendingMarks = 0
  }

  private func commit(_ next: Settings) throws {
    let directory = stateFile.deletingLastPathComponent()
    try files.createDirectory(at: directory, withIntermediateDirectories: true)
    var excluded = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try excluded.setResourceValues(values)
    try JSONEncoder().encode(next).write(to: stateFile, options: .atomic)
    settings = next
    loadFailure = false
  }

  private func resolvedRoot() throws -> (url: URL, stale: Bool) {
    guard !loadFailure else { throw expired() }
    if settings.applicationDocuments { return (documentsDirectory, false) }
    guard let bookmark = settings.bookmark else {
      throw BookDocumentFailure(code: "scan_folder", message: "请先选择扫描范围")
    }
    var stale = false
    let url = try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
    return (url, stale)
  }

  private func withRoot<T>(_ body: (URL) throws -> T) throws -> T {
    let resolved: (url: URL, stale: Bool)
    do { resolved = try resolvedRoot() }
    catch { throw BookDocumentFailure(code: "scan_permission", message: "文件夹访问权限已失效，请重新选择文件夹") }
    let url = resolved.url
    let scope = url.startAccessingSecurityScopedResource()
    defer { if scope { url.stopAccessingSecurityScopedResource() } }
    try requireDirectory(url)
    if resolved.stale {
      var next = settings
      next.bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
      try commit(next)
    }
    return try body(url)
  }

  private func requireDirectory(_ url: URL) throws {
    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values?.isDirectory == true, values?.isSymbolicLink != true, files.isReadableFile(atPath: url.path) else {
      throw BookDocumentFailure(code: "scan_permission", message: "文件夹访问权限已失效，请重新选择文件夹")
    }
  }

  private func expired() -> BookDocumentFailure {
    BookDocumentFailure(code: "scan_reference", message: "扫描结果已过期，请重新扫描")
  }
}
