import Cocoa
import FlutterMacOS
import Security

final class AiCredentials {
  private let channel: FlutterMethodChannel
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "inkflow/ai-credentials", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any], let id = args["id"] as? String,
            id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
        result(FlutterError(code: "invalid", message: "凭据标识不合法", details: nil)); return
      }
      let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "InkFlow.AI", kSecAttrAccount as String: id]
      var status: OSStatus
      switch call.method {
      case "read":
        var readQuery = query
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        status = SecItemCopyMatching(readQuery as CFDictionary, &value)
        if status == errSecSuccess, let data = value as? Data { result(String(data: data, encoding: .utf8)); return }
        if status == errSecItemNotFound { result(nil); return }
      case "write":
        guard let key = args["key"] as? String, !key.isEmpty, key.utf8.count <= 2560 else {
          result(FlutterError(code: "invalid", message: "API Key 长度不可用", details: nil)); return
        }
        let data = Data(key.utf8)
        status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
          var item = query; item[kSecValueData as String] = data
          item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
          status = SecItemAdd(item as CFDictionary, nil)
        }
        if status == errSecSuccess { result(nil); return }
      case "delete":
        status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { result(nil); return }
      default: result(FlutterMethodNotImplemented); return
      }
      result(FlutterError(code: "credential_storage", message: "系统凭据访问失败，请重试", details: nil))
    }
  }
}
