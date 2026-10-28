import Foundation
import ImageIO

struct LibraryImageExport {
  let data: Data
  let name: String
}

/// Match the existing backup/excerpt/original-image limits. Metadata probing
/// does not allocate decoded full-size bitmaps or recompress original images.
enum LibraryExportPolicy {
  static let backupLimit = 4 * 1024 * 1024

  static func backup(_ text: String) throws -> Data {
    let bytes = Data(text.utf8)
    guard bytes.count <= backupLimit else {
      throw BookDocumentFailure(code: "backup_size", message: "备份超过 4 MiB，请减少本地记录后重试")
    }
    return bytes
  }

  static func image(_ data: Data, name: String, original: Bool) throws -> LibraryImageExport {
    let limit = (original ? 8 : 12) * 1024 * 1024
    guard data.count >= 16, data.count <= limit,
          let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          let kind = CGImageSourceGetType(source) as String?,
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0 else {
      throw BookDocumentFailure(code: "image_input", message: "图片格式或大小无效")
    }
    let pixels = Int64(width) * Int64(height)
    let suffix: String
    if original {
      guard pixels <= 80_000_000 else {
        throw BookDocumentFailure(code: "image_dimensions", message: "图片尺寸过大，无法导出")
      }
      switch kind {
      case "public.jpeg": suffix = "jpg"
      case "public.png": suffix = "png"
      case "com.compuserve.gif": suffix = "gif"
      case "org.webmproject.webp", "public.webp": suffix = "webp"
      default: throw BookDocumentFailure(code: "image_format", message: "不支持此图片格式")
      }
    } else {
      guard kind == "public.png", width <= 4096, height <= 8192, pixels <= 12_000_000 else {
        throw BookDocumentFailure(code: "excerpt_image", message: "摘录图片格式或尺寸无效")
      }
      suffix = "png"
    }
    let fallback = original ? "文库插图" : "文库摘录"
    let stem = (name.isEmpty ? fallback : name) as NSString
    return LibraryImageExport(data: data, name: "\(stem.deletingPathExtension).\(suffix)")
  }
}
