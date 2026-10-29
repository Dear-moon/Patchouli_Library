import Foundation
import Photos

/// Adds a new asset without fetching the library or opening a destination picker.
/// The injected operations let host tests exercise authorization and completion
/// without requesting access to the developer's Photos library.
final class PhotoLibraryImageSaver {
  enum Authorization { case notDetermined, authorized, denied, restricted, automatic }
  typealias Completion = (Result<Void, BookDocumentFailure>) -> Void
  typealias AuthorizationRequest = (@escaping (Authorization) -> Void) -> Void
  typealias ResourceWriter = (Data, String, @escaping (Bool, Error?) -> Void) -> Void

  private let authorization: () -> Authorization
  private let requestAuthorization: AuthorizationRequest
  private let writeResource: ResourceWriter

  init(
    authorization: @escaping () -> Authorization = PhotoLibraryImageSaver.currentAuthorization,
    requestAuthorization: @escaping AuthorizationRequest = PhotoLibraryImageSaver.requestAddOnly,
    writeResource: @escaping ResourceWriter = PhotoLibraryImageSaver.addResource
  ) {
    self.authorization = authorization
    self.requestAuthorization = requestAuthorization
    self.writeResource = writeResource
  }

  func save(_ image: LibraryImageExport, completion: @escaping Completion) {
    let status = authorization()
    if status == .notDetermined {
      requestAuthorization { status in self.save(image, authorization: status, completion: completion) }
    } else {
      save(image, authorization: status, completion: completion)
    }
  }

  private func save(_ image: LibraryImageExport, authorization: Authorization, completion: @escaping Completion) {
    switch authorization {
    case .authorized, .automatic:
      writeResource(image.data, image.name) { success, error in
        if success { completion(.success(())); return }
        completion(.failure(Self.writeFailure(error)))
      }
    case .restricted:
      completion(.failure(Self.permissionFailure(restricted: true)))
    case .denied, .notDetermined:
      completion(.failure(Self.permissionFailure(restricted: false)))
    }
  }

  private static func currentAuthorization() -> Authorization {
    if #available(iOS 14.0, macOS 11.0, *) {
      return mapped(PHPhotoLibrary.authorizationStatus(for: .addOnly))
    }
    // iOS 13 has no public add-only status/request API. Creation itself asks
    // for the add-only permission declared in Info.plist; never request the
    // deprecated read/write authorization just to save a new image.
    return .automatic
  }

  private static func requestAddOnly(_ completion: @escaping (Authorization) -> Void) {
    if #available(iOS 14.0, macOS 11.0, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { completion(mapped($0)) }
    } else {
      completion(.automatic)
    }
  }

  @available(iOS 14.0, macOS 11.0, *)
  private static func mapped(_ status: PHAuthorizationStatus) -> Authorization {
    switch status {
    case .authorized, .limited: return .authorized
    case .notDetermined: return .notDetermined
    case .restricted: return .restricted
    case .denied: return .denied
    @unknown default: return .denied
    }
  }

  private static func addResource(_ data: Data, name: String, completion: @escaping (Bool, Error?) -> Void) {
    PHPhotoLibrary.shared().performChanges({
      let options = PHAssetResourceCreationOptions()
      options.originalFilename = name
      PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: options)
    }, completionHandler: completion)
  }

  private static func permissionFailure(restricted: Bool) -> BookDocumentFailure {
    BookDocumentFailure(code: "gallery_permission", message: restricted
      ? "系统限制了添加照片，无法保存到相册。请检查屏幕使用时间或设备管理限制。"
      : "未获得添加照片权限，请在系统设置中允许轻小说文库添加照片后重试。")
  }

  private static func writeFailure(_ error: Error?) -> BookDocumentFailure {
    let failure = error as NSError?
    if #available(iOS 15.0, macOS 12.0, *), failure?.domain == PHPhotosErrorDomain {
      if failure?.code == PHPhotosError.accessUserDenied.rawValue { return permissionFailure(restricted: false) }
      if failure?.code == PHPhotosError.accessRestricted.rawValue { return permissionFailure(restricted: true) }
      if failure?.code == PHPhotosError.notEnoughSpace.rawValue {
        return BookDocumentFailure(code: "gallery_save", message: "相册可用空间不足，请清理空间后重试。")
      }
    }
    return BookDocumentFailure(code: "gallery_save", message: "未能保存到相册，请检查添加照片权限和可用空间后重试。")
  }
}
