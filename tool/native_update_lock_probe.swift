import Cocoa
import FlutterMacOS

final class UpdateLockMessenger: NSObject, FlutterBinaryMessenger {
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) { callback?(nil) }
  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection { 1 }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

@main struct UpdateLockProbe {
  static func main() {
    _ = NSApplication.shared
    let text = String(repeating: "合成稿件，只用于更新锁测试。\n", count: 100)
    let view = NativeNovelEditor(viewId: 98, messenger: UpdateLockMessenger(), arguments: ["documentId": "synthetic-update", "text": text])
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    window.makeFirstResponder(view.editor)
    view.layoutSubtreeIfNeeded()
    view.editor.setSelectedRange(NSRange(location: 2, length: 0))
    view.editor.setMarkedText("待提交", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    precondition(view.editor.hasMarkedText())
    let expectedText = view.editor.string
    let expectedSelection = view.editor.selectedRange()
    let expectedScroll = view.contentView.bounds.origin
    let locked = view.setUpdateLocked(true)
    precondition(!view.editor.hasMarkedText(), "IME must be committed")
    precondition(!view.editor.isEditable)
    precondition(view.editor.string == expectedText)
    precondition(view.editor.selectedRange() == expectedSelection)
    precondition(view.contentView.bounds.origin == expectedScroll)
    precondition(locked["origin"] as? String == "update")
    precondition(locked["text"] as? String == expectedText)
    precondition(locked["isUpdateLocked"] as? Bool == true)
    let unlocked = view.setUpdateLocked(false)
    precondition(view.editor.isEditable)
    precondition(unlocked["isUpdateLocked"] as? Bool == false)
    precondition(view.editor.selectedRange() == expectedSelection)
    precondition(view.contentView.bounds.origin == expectedScroll)
    print("PASS update lock commits IME, preserves text/selection/scroll, returns state, unlocks")
  }
}
