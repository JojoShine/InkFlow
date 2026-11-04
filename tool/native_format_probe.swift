import Cocoa
import FlutterMacOS

final class FormatMessenger: NSObject, FlutterBinaryMessenger {
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) { callback?(nil) }
  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection { 1 }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
@main struct FormatProbe {
  static func main() throws {
    _ = NSApplication.shared
    let source = "　第一段  \n\n\n第二段 👩‍💻"
    let view = NativeNovelEditor(viewId: 99, messenger: FormatMessenger(), arguments: ["documentId":"probe", "text": source, "fontFamily":"Songti SC"])
    let window = NSWindow(contentRect: NSRect(x:0,y:0,width:760,height:500), styleMask:[.titled], backing:.buffered, defer:false)
    window.contentView = view
    window.makeFirstResponder(view.editor)
    let replacement = "第一段\n\n第二段 👩‍💻"
    let state = try view.replaceRange(["documentId":"probe", "expectedText": source, "rangeStart":0, "rangeEnd":(source as NSString).length, "replacement":replacement])
    precondition(state["origin"] as? String == "format")
    precondition(view.editor.string == replacement)
    precondition(view.editor.undoManager?.canUndo == true)
    view.editor.undoManager?.undo()
    precondition(view.editor.string == source, "one undo must restore all text")
    view.editor.undoManager?.redo()
    precondition(view.editor.string == replacement)
    do {
      _ = try view.replaceRange(["documentId":"probe", "expectedText":source, "rangeStart":0, "rangeEnd":1,"replacement":"错误"])
      fatalError("stale edit accepted")
    } catch { precondition(view.editor.string == replacement) }
    print("PASS native formatting, one-step undo/redo, stale source rejection")
  }
}
