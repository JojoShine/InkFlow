import Cocoa
import FlutterMacOS

final class DirectoryAccess {
  private let channel: FlutterMethodChannel
  private var activeURLs: [String: URL] = [:]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "inkflow/desktop", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      do {
        switch call.method {
        case "openDownloadPage":
          let url: URL
          if let requested = call.arguments as? String {
            guard let candidate = URL(string: requested),
              candidate.scheme == "https", candidate.host == "tbtparent-me.oss-cn-hangzhou.aliyuncs.com",
              candidate.user == nil, candidate.password == nil, candidate.port == nil,
              candidate.query == nil, candidate.fragment == nil,
              candidate.path.hasPrefix("/Download/inkflow/releases/"),
              !candidate.pathComponents.contains(".."),
              ["zip", "dmg"].contains(candidate.pathExtension.lowercased()) else {
              result(FlutterError(code: "invalid_download", message: "安装包地址不合法", details: nil)); return
            }
            url = candidate
          } else {
            url = URL(string: "https://tbtparent.me/inkflow/#download")!
          }
          if NSWorkspace.shared.open(url) { result(nil) }
          else { result(FlutterError(code: "download_page", message: "无法打开官网下载页", details: nil)) }
        case "updateConfiguration":
          #if arch(arm64)
          let architecture = "arm64"
          #else
          let architecture = "x64"
          #endif
          let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
          let enabled = Bundle.main.bundleIdentifier == "me.tbtparent.inkflow" && Data(base64Encoded: key)?.count == 32
          result(["enabled": enabled, "reason": enabled ? "" : "此安装包尚未配置更新签名，请使用正式发布版本。",
            "architecture": architecture,
            "feedURL": "https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/appcast-macos-\(architecture).xml"])
        case "pickLegacyDataDirectory":
          let home = NSHomeDirectory().components(separatedBy: "/Library/Containers/").first ?? NSHomeDirectory()
          let panel = NSOpenPanel()
          panel.title = "选择旧版 InkFlow 数据文件夹"
          panel.prompt = "导入旧版数据"
          panel.canChooseFiles = false
          panel.canChooseDirectories = true
          panel.allowsMultipleSelection = false
          panel.directoryURL = URL(fileURLWithPath: home).appendingPathComponent("Library/Containers/dev.inkflow.inkflow/Data/Library/Application Support/dev.inkflow.inkflow")
          panel.begin { response in
            result(response == .OK ? panel.url?.path : nil)
          }
        case "legacyAppRunning":
          result(NSRunningApplication.runningApplications(withBundleIdentifier: "dev.inkflow.inkflow")
            .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })
        case "applicationIdentity":
          result(["bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
            "processId": Int(ProcessInfo.processInfo.processIdentifier)])
        case "bookmark":
          guard let path = call.arguments as? String else {
            result(FlutterError(code: "invalid_path", message: "目录路径不合法", details: nil)); return
          }
          let url = URL(fileURLWithPath: path, isDirectory: true)
          let data = try url.bookmarkData(options: .withSecurityScope,
            includingResourceValuesForKeys: nil, relativeTo: nil)
          result(data.base64EncodedString())
        case "resolveBookmark":
          guard let token = call.arguments as? String,
            let data = Data(base64Encoded: token) else {
            result(FlutterError(code: "invalid_bookmark", message: "目录授权记录损坏", details: nil)); return
          }
          var stale = false
          let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope,
            relativeTo: nil, bookmarkDataIsStale: &stale)
          guard url.startAccessingSecurityScopedResource() else {
            result(FlutterError(code: "access_expired", message: "请重新选择作品文件夹", details: nil)); return
          }
          if let previous = self.activeURLs[token] { previous.stopAccessingSecurityScopedResource() }
          self.activeURLs[token] = url
          result(url.path)
        default: result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "directory_access", message: error.localizedDescription, details: nil))
      }
    }
  }

  deinit {
    for url in activeURLs.values { url.stopAccessingSecurityScopedResource() }
    channel.setMethodCallHandler(nil)
  }
}
