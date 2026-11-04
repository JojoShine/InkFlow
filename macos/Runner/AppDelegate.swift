import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var lifecycle: FlutterMethodChannel?
  private var allowQuit = false
  private var workOpen = false
  private var fileMenu: NSMenu?

  func configureLifecycle(messenger: FlutterBinaryMessenger) {
    lifecycle = FlutterMethodChannel(name: "inkflow/lifecycle", binaryMessenger: messenger)
    lifecycle?.setMethodCallHandler { [weak self] call, result in
      if call.method == "allowQuit" { self?.allowQuit = true; result(nil) }
      else if call.method == "setWorkOpen" {
        self?.workOpen = call.arguments as? Bool ?? false
        self?.updateFileMenu(); result(nil)
      }
      else { result(FlutterMethodNotImplemented) }
    }
    DispatchQueue.main.async { [weak self] in self?.installFileMenu() }
  }

  private func installFileMenu() {
    guard fileMenu == nil, let mainMenu = NSApp.mainMenu else { return }
    let menu = NSMenu(title: "文件")
    menu.autoenablesItems = false
    let items: [(String, String, String, Bool, Bool)] = [
      ("新建作品", "newWork", "n", true, false), ("打开作品", "open", "o", false, false),
      ("新建章节", "newChapter", "n", false, true), ("保存全部", "save", "s", false, true),
      ("导入 TXT 章节", "import", "i", false, true),
      ("导出当前章节", "exportChapter", "e", true, true),
      ("完整作品备份", "backup", "b", true, true),
      ("从备份恢复作品", "restore", "o", true, false)
    ]
    for (title, action, key, shift, requiresWork) in items {
      let item = NSMenuItem(title: title, action: #selector(fileAction(_:)), keyEquivalent: key)
      item.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]
      item.target = self; item.representedObject = action; item.tag = requiresWork ? 1 : 0
      menu.addItem(item)
    }
    let root = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
    root.submenu = menu
    mainMenu.insertItem(root, at: min(1, mainMenu.items.count))
    fileMenu = menu; updateFileMenu()
  }

  private func updateFileMenu() {
    for item in fileMenu?.items ?? [] { item.isEnabled = item.tag == 0 || workOpen }
  }

  @objc private func fileAction(_ sender: NSMenuItem) {
    lifecycle?.invokeMethod("fileAction", arguments: sender.representedObject as? String)
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !allowQuit, let channel = lifecycle else { return .terminateNow }
    channel.invokeMethod("requestQuit", arguments: nil) { [weak self] value in
      let saved = value as? Bool ?? false
      self?.allowQuit = saved
      sender.reply(toApplicationShouldTerminate: saved)
    }
    return .terminateLater
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
