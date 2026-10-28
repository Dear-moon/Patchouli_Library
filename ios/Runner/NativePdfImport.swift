import Foundation
import CoreGraphics
import ImageIO
import PDFKit

/// Uses the system PDF engine; no PDF renderer, fonts or Java runtime is bundled.
/// PDF pages become the existing EPUB reader's text and illustrations. Scanned
/// pages retain their visible content as bounded, page-at-a-time images.
final class NativePdfImport {
  let document: PDFDocument
  let name: String

  init(source: URL, name: String) throws {
    guard let document = PDFDocument(url: source) else {
      throw BookDocumentFailure(code: "pdf_parse", message: "PDF 结构损坏或无法识别，请检查完整原文件")
    }
    guard !document.isEncrypted, !document.isLocked, document.allowsCopying else {
      throw BookDocumentFailure(code: "pdf_protected", message: "不支持加密或禁止提取内容的 PDF")
    }
    guard document.pageCount > 0, document.pageCount <= 10000 else {
      throw BookDocumentFailure(code: "pdf_pages", message: "PDF 页数无效或超过 10000 页")
    }
    self.document = document
    self.name = name
  }

  func write(to directory: URL) throws {
    let fallback = (name as NSString).deletingPathExtension
    let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let author = document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String ?? ""
    let writer = PdfEpubResources(directory: directory, title: title?.isEmpty == false ? title! : fallback, author: author)
    for index in 0..<document.pageCount {
      try autoreleasepool {
        do {
          guard let page = document.page(at: index), let ref = page.pageRef else {
            throw BookDocumentFailure(code: "pdf_page", message: "无法读取页面对象")
          }
          let geometry = try PdfPageGeometry(page: ref)
          let scan = try PdfImageScanner.read(ref)
          guard page.numberOfCharacters <= 6 * 1024 * 1024 else {
            throw BookDocumentFailure(code: "pdf_text_limit", message: "单页正文过大，请拆分原书后导入")
          }
          let text = page.string ?? ""
          writer.beginPage(index + 1)
          if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Vector-only and scanned pages retain all visible content.
            try writer.image(page: ref, geometry: geometry, region: geometry.bounds)
          } else {
            let selections = page.selection(for: NSRange(location: 0, length: page.numberOfCharacters))?.selectionsByLine() ?? []
            let lines = selections.compactMap { selected -> PdfTextLine? in
              guard let value = selected.string, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
              return PdfTextLine(text: value, bounds: selected.bounds(for: page).applying(geometry.transform))
            }
            let pictures = scan.images.map { $0.applying(geometry.transform).intersection(geometry.bounds) }
              .filter { !$0.isNull && $0.width > 0.1 && $0.height > 0.1 }
            // Use native text order (including columns). Only insert images;
            // sorting all lines by Y would interleave a two-column page.
            if PdfTextLine.normalized(lines.map(\.text).joined()) == PdfTextLine.normalized(text), !lines.isEmpty {
              var insertions = [Int: [CGRect]]()
              for picture in pictures { insertions[PdfTextLine.slot(for: picture, lines: lines), default: []].append(picture) }
              for offset in 0...lines.count {
                for picture in insertions[offset] ?? [] { try writer.image(page: ref, geometry: geometry, region: picture) }
                if offset < lines.count { try writer.text(lines[offset].text) }
              }
            } else {
              // If PDFKit cannot partition every character into selections,
              // preserve its complete page text instead of losing a suffix.
              try writer.text(text)
              for picture in pictures { try writer.image(page: ref, geometry: geometry, region: picture) }
            }
          }
          try writer.endPage()
        } catch {
          let failure = error as? BookDocumentFailure
          throw BookDocumentFailure(code: failure?.code ?? "pdf_io", message: "PDF 第 \(index + 1) 页处理失败：\(error.localizedDescription)")
        }
      }
    }
    try writer.finish()
  }
}

struct PdfPageGeometry {
  let bounds: CGRect
  let transform: CGAffineTransform
  init(page: CGPDFPage) throws {
    let crop = page.getBoxRect(.cropBox).intersection(page.getBoxRect(.mediaBox))
    guard crop.width.isFinite, crop.height.isFinite, crop.width > 0, crop.height > 0,
      crop.width <= 100000, crop.height <= 100000 else {
      throw BookDocumentFailure(code: "pdf_geometry", message: "PDF 页面尺寸无效或过大")
    }
    let sideways = abs(page.rotationAngle) % 180 == 90
    bounds = CGRect(x: 0, y: 0, width: sideways ? crop.height : crop.width, height: sideways ? crop.width : crop.height)
    transform = page.getDrawingTransform(.cropBox, rect: bounds, rotate: 0, preserveAspectRatio: true)
  }
}

struct PdfTextLine {
  let text: String
  let bounds: CGRect
  static func normalized(_ text: String) -> String { String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }) }
  static func slot(for image: CGRect, lines: [PdfTextLine]) -> Int {
    let aligned = lines.enumerated().filter { _, line in
      let overlap = min(image.maxX, line.bounds.maxX) - max(image.minX, line.bounds.minX)
      return overlap > min(image.width, line.bounds.width) * 0.2
    }
    if let before = aligned.filter({ $0.element.bounds.minY >= image.maxY - 2 })
      .min(by: { $0.element.bounds.minY - image.maxY < $1.element.bounds.minY - image.maxY }) { return before.offset + 1 }
    if let after = aligned.filter({ $0.element.bounds.maxY <= image.minY + 2 })
      .min(by: { image.minY - $0.element.bounds.maxY < image.minY - $1.element.bounds.maxY }) { return after.offset }
    return lines.count
  }
}

/// Tracks PDF graphic state and nested Form XObjects, not just dictionary order.
/// Crop rendering is left to Quartz so color spaces, masks and JPEG2000 do not
/// need another decoder and obey the source page's transforms and clipping.
final class PdfImageScanner {
  struct State { var matrix = CGAffineTransform.identity; var clip: CGRect }
  var state: State
  var stack = [State]()
  var images = [CGRect]()
  var inlineImages = false
  var failure: BookDocumentFailure?
  var forms = Set<UInt>()
  var operations = 0
  init(clip: CGRect) { state = State(clip: clip) }

  static func read(_ page: CGPDFPage) throws -> PdfImageScanner {
    let result = PdfImageScanner(clip: page.getBoxRect(.cropBox))
    result.scan(CGPDFContentStreamCreateWithPage(page))
    if let failure = result.failure { throw failure }
    return result
  }

  func fail(_ scanner: CGPDFScannerRef, _ message: String) {
    failure = BookDocumentFailure(code: "pdf_graphics", message: message)
    CGPDFScannerStop(scanner)
  }

  // These scanner objects are not CFTypes and are not released by Swift ARC.
  // Every caller passes a new +1 content stream; this method consumes it.
  private func scan(_ content: CGPDFContentStreamRef) {
    defer { CGPDFContentStreamRelease(content) }
    let table = CGPDFOperatorTableCreate()!
    defer { CGPDFOperatorTableRelease(table) }
    CGPDFOperatorTableSetCallback(table, "q") { scanner, info in
      let owner = Unmanaged<PdfImageScanner>.fromOpaque(info!).takeUnretainedValue()
      if owner.stack.count >= 256 { owner.fail(scanner, "页面图形状态嵌套过深"); return }
      owner.stack.append(owner.state)
    }
    CGPDFOperatorTableSetCallback(table, "Q") { _, info in
      let owner = Unmanaged<PdfImageScanner>.fromOpaque(info!).takeUnretainedValue()
      if let restored = owner.stack.popLast() { owner.state = restored }
    }
    CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
      let owner = Unmanaged<PdfImageScanner>.fromOpaque(info!).takeUnretainedValue()
      var values = [CGPDFReal](repeating: 0, count: 6)
      for index in (0..<6).reversed() {
        if !CGPDFScannerPopNumber(scanner, &values[index]) || !values[index].isFinite { owner.fail(scanner, "页面变换矩阵无效"); return }
      }
      let next = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
      owner.state.matrix = next.concatenating(owner.state.matrix)
    }
    // Quartz reports complete inline images at EI, not at their BI marker.
    CGPDFOperatorTableSetCallback(table, "EI") { scanner, info in
      let owner = Unmanaged<PdfImageScanner>.fromOpaque(info!).takeUnretainedValue()
      owner.inlineImages = true
      var stream: CGPDFStreamRef?
      if CGPDFScannerPopStream(scanner, &stream), let stream, let dictionary = CGPDFStreamGetDictionary(stream) {
        if !owner.validDimensions(scanner, dictionary: dictionary) { return }
      }
      owner.appendImage(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
      Unmanaged<PdfImageScanner>.fromOpaque(info!).takeUnretainedValue().object(scanner)
    }
    let scanner = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(self).toOpaque())
    defer { CGPDFScannerRelease(scanner) }
    if !CGPDFScannerScan(scanner), failure == nil {
      failure = BookDocumentFailure(code: "pdf_graphics", message: "PDF 页面内容流损坏或不完整")
    }
  }

  func object(_ scanner: CGPDFScannerRef) {
    if failure != nil { CGPDFScannerStop(scanner); return }
    operations += 1
    guard operations <= 20000 else { fail(scanner, "单页图像对象过多"); return }
    var name: UnsafePointer<CChar>?
    guard CGPDFScannerPopName(scanner, &name), let name,
      let resource = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "XObject", name) else { fail(scanner, "PDF 引用的图形资源缺失"); return }
    var stream: CGPDFStreamRef?
    guard CGPDFObjectGetValue(resource, .stream, &stream), let stream,
      let dictionary = CGPDFStreamGetDictionary(stream) else { fail(scanner, "PDF 图形资源无效"); return }
    var subtype: UnsafePointer<CChar>?
    guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return }
    switch String(cString: subtype) {
    case "Image":
      if validDimensions(scanner, dictionary: dictionary) { appendImage(scanner) }
    case "Form":
      let id = UInt(bitPattern: stream.rawValue)
      guard forms.count < 32, forms.insert(id).inserted else { fail(scanner, "PDF 图形引用循环或嵌套过深"); return }
      let saved = state, savedStack = stack
      defer { state = saved; stack = savedStack; forms.remove(id) }
      if let matrix = numbers(dictionary, "Matrix", count: 6) {
        state.matrix = CGAffineTransform(a: matrix[0], b: matrix[1], c: matrix[2], d: matrix[3], tx: matrix[4], ty: matrix[5]).concatenating(saved.matrix)
      }
      if let box = numbers(dictionary, "BBox", count: 4) {
        state.clip = saved.clip.intersection(CGRect(x: box[0], y: box[1], width: box[2] - box[0], height: box[3] - box[1]).applying(state.matrix))
      }
      var resources: CGPDFDictionaryRef?
      CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources)
      // An empty lookup in the form dictionary falls through to the parent.
      scan(CGPDFContentStreamCreateWithStream(stream, resources ?? dictionary, CGPDFScannerGetContentStream(scanner)))
      if failure != nil { CGPDFScannerStop(scanner) }
    default: break
    }
  }

  private func validDimensions(_ scanner: CGPDFScannerRef, dictionary: CGPDFDictionaryRef) -> Bool {
    var width = 0, height = 0
    let hasWidth = CGPDFDictionaryGetInteger(dictionary, "Width", &width) || CGPDFDictionaryGetInteger(dictionary, "W", &width)
    let hasHeight = CGPDFDictionaryGetInteger(dictionary, "Height", &height) || CGPDFDictionaryGetInteger(dictionary, "H", &height)
    guard hasWidth, hasHeight, width > 0, height > 0, width <= 24000000 / height else {
      fail(scanner, "PDF 单张图片超过 2400 万像素或尺寸无效"); return false
    }
    return true
  }

  private func appendImage(_ scanner: CGPDFScannerRef) {
    let rect = CGRect(x: 0, y: 0, width: 1, height: 1).applying(state.matrix).intersection(state.clip)
    guard !rect.isInfinite, rect.width.isFinite, rect.height.isFinite else { fail(scanner, "PDF 图片位置无效"); return }
    if !rect.isNull { images.append(rect) }
    if images.count > 2048 { fail(scanner, "单页图片数量过多") }
  }

  private func numbers(_ dictionary: CGPDFDictionaryRef, _ key: String, count: Int) -> [CGFloat]? {
    var array: CGPDFArrayRef?
    guard CGPDFDictionaryGetArray(dictionary, key, &array), let array, CGPDFArrayGetCount(array) == count else { return nil }
    var values = [CGPDFReal](repeating: 0, count: count)
    for index in 0..<count {
      if !CGPDFArrayGetNumber(array, index, &values[index]) || !values[index].isFinite { return nil }
    }
    return values
  }
}

private final class PdfEpubResources {
  let directory: URL, title: String, author: String
  var label = "", body = "", size = 0
  var bodyLength = 0
  var parts = [(String, String)](), images = [String]()
  init(directory: URL, title: String, author: String) {
    self.directory = directory; self.title = String(title.prefix(2048)); self.author = String(author.prefix(2048))
  }
  static func escape(_ text: String) -> String {
    String(text.unicodeScalars.filter { $0.value == 9 || $0.value == 10 || $0.value == 13 || $0.value >= 32 && $0.value != 0xfffe && $0.value != 0xffff })
      .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
  }
  func beginPage(_ page: Int) { label = "第 \(page) 页" }
  func text(_ text: String) throws {
    for line in text.split(whereSeparator: \.isNewline) {
      var remaining = line[...]
      while !remaining.isEmpty {
        let end = remaining.index(remaining.startIndex, offsetBy: 4000, limitedBy: remaining.endIndex) ?? remaining.endIndex
        try append("<p>\(Self.escape(String(remaining[..<end])))</p>")
        remaining = remaining[end...]
      }
    }
  }
  func append(_ text: String) throws {
    let length = text.utf16.count
    if bodyLength + length > 200000 { try endPage() }
    body += text; bodyLength += length
  }
  func write(_ name: String, data: Data) throws {
    guard data.count <= 40 * 1024 * 1024, data.count <= 1024 * 1024 * 1024 - size else {
      throw BookDocumentFailure(code: "pdf_expanded", message: "PDF 展开后超过 1 GiB 或单个资源过大")
    }
    try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    size += data.count
  }
  func endPage() throws {
    guard !body.isEmpty else { return }
    guard parts.count < 10000 else { throw BookDocumentFailure(code: "pdf_parts", message: "PDF 转换章节过多，请拆分后导入") }
    let name = String(format: "part%05d.html", parts.count)
    try write(name, data: Data("<?xml version=\"1.0\" encoding=\"utf-8\"?><html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>\(Self.escape(label))</title></head><body>\(body)</body></html>".utf8))
    parts.append((name, label)); body = ""; bodyLength = 0
  }
  func image(page: CGPDFPage, geometry: PdfPageGeometry, region: CGRect) throws {
    guard region.width > 0, region.height > 0, images.count < 19998 else { throw BookDocumentFailure(code: "pdf_images", message: "PDF 图片范围无效或数量过多") }
    let scale = min(120.0 / 72.0, 1800 / max(region.width, region.height))
    let width = max(1, Int(ceil(region.width * scale))), height = max(1, Int(ceil(region.height * scale)))
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
      throw BookDocumentFailure(code: "pdf_render", message: "无法分配 PDF 页面图片，请释放内存后重试")
    }
    context.setFillColor(gray: 1, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: scale, y: scale); context.translateBy(x: -region.minX, y: -region.minY)
    context.concatenate(geometry.transform); context.drawPDFPage(page)
    guard let image = context.makeImage() else { throw BookDocumentFailure(code: "pdf_render", message: "PDF 页面绘制失败") }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { throw BookDocumentFailure(code: "pdf_image", message: "无法创建 PDF 图片") }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
    guard CGImageDestinationFinalize(destination), data.length <= 8 * 1024 * 1024 else { throw BookDocumentFailure(code: "pdf_image", message: "PDF 图片编码失败或超过 8 MiB") }
    let name = String(format: "resource%05d.jpg", images.count + 1)
    try write(name, data: data as Data); images.append(name)
    try append("<img src=\"\(name)\" style=\"width:\(region.width)px;height:\(region.height)px\"/>")
  }
  func finish() throws {
    try endPage()
    guard !parts.isEmpty else { throw BookDocumentFailure(code: "pdf_empty", message: "PDF 中没有可阅读的页面") }
    let manifest = parts.enumerated().map { "<item id=\"c\($0.offset)\" href=\"\($0.element.0)\" media-type=\"application/xhtml+xml\"/>" }.joined()
      + images.enumerated().map { "<item id=\"i\($0.offset)\" href=\"\($0.element)\" media-type=\"image/jpeg\"/>" }.joined()
    let spine = parts.indices.map { "<itemref idref=\"c\($0)\"/>" }.joined()
    let nav = parts.enumerated().map { "<navPoint id=\"p\($0.offset)\" playOrder=\"\($0.offset + 1)\"><navLabel><text>\(Self.escape($0.element.1))</text></navLabel><content src=\"\($0.element.0)\"/></navPoint>" }.joined()
    try write("resource00000.ncx", data: Data("<?xml version=\"1.0\"?><ncx xmlns=\"http://www.daisy.org/z3986/2005/ncx/\" version=\"2005-1\"><head><meta name=\"dtb:uid\" content=\"urn:local:pdf\"/></head><docTitle><text>\(Self.escape(title))</text></docTitle><navMap>\(nav)</navMap></ncx>".utf8))
    try write("content.opf", data: Data("<?xml version=\"1.0\"?><package xmlns=\"http://www.idpf.org/2007/opf\" version=\"2.0\" unique-identifier=\"uid\"><metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:identifier id=\"uid\">urn:local:pdf</dc:identifier><dc:title>\(Self.escape(title))</dc:title><dc:creator>\(Self.escape(author))</dc:creator><dc:language>und</dc:language></metadata><manifest><item id=\"nav\" href=\"resource00000.ncx\" media-type=\"application/x-dtbncx+xml\"/>\(manifest)</manifest><spine toc=\"nav\">\(spine)</spine></package>".utf8))
  }
}
