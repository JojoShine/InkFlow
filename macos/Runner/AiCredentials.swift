import Foundation
import Security

// Local device storage lives outside works and shared libraries.
final class AiCredentialStore {
  private let root: URL
  private let legacyRead: (String) -> String?

  init(root: URL, legacyRead: @escaping (String) -> String? = AiCredentialStore.readLegacy) {
    self.root = root
    self.legacyRead = legacyRead
  }

  func contains(_ id: String) throws -> Bool {
    let file = root.appendingPathComponent(id + ".key")
    guard FileManager.default.fileExists(atPath: file.path) else { return false }
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    return ((attributes[.size] as? NSNumber)?.uint64Value ?? 0) > 0
  }

  func read(_ id: String) throws -> String? {
    let file = root.appendingPathComponent(id + ".key")
    if FileManager.default.fileExists(atPath: file.path) {
      let key = try String(contentsOf: file, encoding: .utf8)
      return key.isEmpty ? nil : key
    }
    // An empty file also records a failed migration or explicit deletion,
    // so an old Keychain value cannot reappear after deleting a local key.
    let key = legacyRead(id) ?? ""
    try write(id, key: key)
    return key.isEmpty ? nil : key
  }

  func write(_ id: String, key: String) throws {
    let manager = FileManager.default
    try manager.createDirectory(at: root, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
    try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    let file = root.appendingPathComponent(id + ".key")
    try Data(key.utf8).write(to: file, options: .atomic)
    try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
  }

  func delete(_ id: String) throws {
    try write(id, key: "")
  }

  private static func readLegacy(_ id: String) -> String? {
    // Legacy file-based Keychains ignore kSecUseAuthenticationUIFail.
    // Suppress interaction for this one migration and restore it immediately.
    // See Chromium crypto/apple/scoped_keychain_user_interaction_allowed.cc.
    var allowed: DarwinBoolean = false
    guard SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess,
          SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { return nil }
    defer { SecKeychainSetUserInteractionAllowed(allowed.boolValue) }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "InkFlow.AI",
      kSecAttrAccount as String: id,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var value: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
          let data = value as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

#if canImport(FlutterMacOS)
import FlutterMacOS

final class AiCredentials {
  private let channel: FlutterMethodChannel
  init(messenger: FlutterBinaryMessenger) {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let root = support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "InkFlow", isDirectory: true)
      .appendingPathComponent("ai-keys", isDirectory: true)
    let store = AiCredentialStore(root: root)
    let queue = DispatchQueue(label: "InkFlow.AI.credentials")
    channel = FlutterMethodChannel(name: "inkflow/ai-credentials", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any], let id = args["id"] as? String,
            id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
        result(FlutterError(code: "invalid", message: "凭据标识不合法", details: nil)); return
      }
      queue.async {
        let reply: FlutterResult = { value in DispatchQueue.main.async { result(value) } }
        do {
          switch call.method {
          case "contains": reply(try store.contains(id))
          case "read": reply(try store.read(id))
          case "write":
            guard let key = args["key"] as? String, !key.isEmpty, key.utf8.count <= 2560 else {
              reply(FlutterError(code: "invalid", message: "API Key 长度不可用", details: nil)); return
            }
            try store.write(id, key: key)
            reply(nil)
          case "delete":
            try store.delete(id)
            reply(nil)
          default: reply(FlutterMethodNotImplemented)
          }
        } catch {
          reply(FlutterError(code: "credential_storage", message: "读取或保存 API 密钥失败，请重试", details: nil))
        }
      }
    }
  }
}
#endif
