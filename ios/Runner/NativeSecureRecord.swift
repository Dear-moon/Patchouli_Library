import Foundation
import Security

/// Platform-channel configuration may contain credentials. Keep each record in
/// Keychain, available after first unlock for user-started background playback.
struct NativeSecureRecord {
  let service: String
  let account: String

  static let cloudSources = appRecord("cloud_sources", account: "connections")
  static let customSpeech = appRecord("custom_speech", account: "configuration")
  static let lanReading = appRecord("lan_reading_config", account: "configuration")

  private static func appRecord(_ name: String, account: String) -> NativeSecureRecord {
    NativeSecureRecord(service: "\(Bundle.main.bundleIdentifier ?? "org.mewx.wenku8Flutter").\(name)", account: account)
  }

  private var key: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service, kSecAttrAccount as String: account]
  }

  func read() throws -> String? {
    var query = key
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var found: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &found)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw failure(status) }
    guard let data = found as? Data, let text = String(data: data, encoding: .utf8) else {
      throw BookDocumentFailure(code: "secure_storage", message: "本机安全配置无法读取，请重新保存")
    }
    return text
  }

  func write(_ text: String?) throws {
    guard let text else {
      let status = SecItemDelete(key as CFDictionary)
      if status != errSecSuccess && status != errSecItemNotFound { throw failure(status) }
      return
    }
    let attributes: [String: Any] = [kSecValueData as String: Data(text.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
    var status = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      status = SecItemAdd(key.merging(attributes) { _, value in value } as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw failure(status) }
  }

  private func failure(_ status: OSStatus) -> BookDocumentFailure {
    let reason: String
    switch status {
    case errSecMissingEntitlement: reason = "应用签名缺少安全存储权限，请重新安装正确签名的版本"
    case errSecInteractionNotAllowed, errSecNotAvailable: reason = "系统安全存储暂不可用，请解锁设备后重试"
    default: reason = "系统安全存储操作失败，请重试或联系开发者"
    }
    return BookDocumentFailure(code: "secure_storage", message: "\(reason)（\(status)）")
  }
}
