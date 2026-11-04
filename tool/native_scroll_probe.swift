import Cocoa
import FlutterMacOS

final class ProbeMessenger: NSObject, FlutterBinaryMessenger {
  var bytes = 0
  var messages: [String: Int] = [:]
  var onCall: ((FlutterMethodCall) -> Void)?
  private var handlers: [String: FlutterBinaryMessageHandler] = [:]
  private let codec = FlutterStandardMethodCodec.sharedInstance()
  func send(onChannel channel: String, message: Data?) {
    guard let message = message else { return }
    bytes += message.count
    let call = codec.decodeMethodCall(message)
    messages[call.method, default: 0] += 1
    onCall?(call)
  }
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    send(onChannel: channel, message: message)
    callback?(codec.encodeSuccessEnvelope(nil))
  }
  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
    handlers[channel] = handler
    return 1
  }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
  func state(viewID: Int) -> [String: Any] {
    var state: [String: Any] = [:]
    handlers["inkflow/editor/\(viewID)"]?(codec.encode(FlutterMethodCall(methodName: "getState", arguments: nil))) { reply in
      if let reply = reply { state = self.codec.decodeEnvelope(reply) as? [String: Any] ?? [:] }
    }
    return state
  }
}

final class ProbeTextContainer: NSTextContainer {
  var sizeWrites = 0
  override var containerSize: NSSize {
    get { super.containerSize }
    set { sizeWrites += 1; super.containerSize = newValue }
  }
}

@main
struct NativeScrollProbe {
  static func main() {
    _ = NSApplication.shared
    let messenger = ProbeMessenger()
    let paragraph = "雨后的街道安静下来，她沿着旧巷慢慢向前走，直到远处的灯再次亮起。\n"
    let text = String(repeating: paragraph, count: 3000)
    let view = NativeNovelEditor(viewId: 1, messenger: messenger, arguments: [
      "text": text, "documentId": "scroll-probe", "fontFamily": "Songti SC",
      "fontSize": 20.0, "lineHeight": 1.8, "paragraphGap": 8.0,
      "selectionBase": 0, "selectionExtent": 0
    ])
    view.frame = NSRect(x: 0, y: 0, width: 760, height: 700)
    let container = ProbeTextContainer(containerSize: NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = false
    view.editor.replaceTextContainer(container)
    view.layout()
    view.editor.layoutManager?.ensureLayout(for: container)
    let height = view.editor.layoutManager?.usedRect(for: container).height ?? 700
    view.editor.setFrameSize(NSSize(width: 760, height: max(700, height + 20)))
    container.sizeWrites = 0
    messenger.bytes = 0
    messenger.messages = [:]
    var samples: [Double] = []
    for step in 0..<300 {
      let start = DispatchTime.now().uptimeNanoseconds
      view.contentView.scroll(to: NSPoint(x: 0, y: min(CGFloat(step * 100), height - 700)))
      view.layout()
      view.editor.layoutManager?.ensureLayout(forBoundingRect: view.documentVisibleRect, in: container)
      samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
    let selectionStart = DispatchTime.now().uptimeNanoseconds
    for step in 0..<100 {
      view.editor.setSelectedRange(NSRange(location: step * 10, length: 0))
      view.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view.editor))
    }
    let selectionMs = Double(DispatchTime.now().uptimeNanoseconds - selectionStart) / 1_000_000
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
    samples.sort()
    var report: [String: Any] = [
      "utf16Length": (text as NSString).length,
      "scrollSteps": samples.count,
      "layoutP95Ms": samples[Int(Double(samples.count - 1) * 0.95)],
      "layoutMaxMs": samples.last!,
      "containerSizeWrites": container.sizeWrites,
      "bridgeBytes": messenger.bytes,
      "selectionDispatchMs": selectionMs,
      "bridgeMessages": messenger.messages,
      "scrollY": view.contentView.bounds.origin.y,
      "textPreserved": view.editor.string == text,
      "scrollbarHidden": !view.hasVerticalScroller
    ]
    let state = messenger.state(viewID: 1)
    let scrollAccurate = (state["scrollOffset"] as? NSNumber)?.doubleValue == Double(view.contentView.bounds.origin.y)
    let stateTextValid = state["text"] as? String == text
    let imeMessenger = ProbeMessenger()
    var latestText: [String: Any] = [:]
    imeMessenger.onCall = { call in
      if call.method == "changed" { latestText = call.arguments as? [String: Any] ?? [:] }
    }
    let ime = NativeNovelEditor(viewId: 2, messenger: imeMessenger, arguments: ["text": "", "documentId": "ime-check"])
    ime.frame = NSRect(x: 0, y: 0, width: 760, height: 400)
    ime.layout()
    ime.editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    ime.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: ime.editor))
    let draftValid = latestText["text"] as? String == "ni" && latestText["composingStart"] as? Int == 0
    report["draftHasMarkedText"] = ime.editor.hasMarkedText()
    report["draftMarkedLocation"] = ime.editor.markedRange().location
    report["draftMarkedLength"] = ime.editor.markedRange().length
    report["nativeIMEDraftState"] = latestText
    ime.editor.insertText("你好", replacementRange: NSRange(location: NSNotFound, length: 0))
    ime.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: ime.editor))
    let commitValid = latestText["text"] as? String == "你好" && latestText["composingStart"] as? Int == -1
    report["commitHasMarkedText"] = ime.editor.hasMarkedText()
    report["nativeIMECommitState"] = latestText
    report["nativeIMEDraftValid"] = draftValid
    report["nativeIMECommitValid"] = commitValid
    let savedSelection = view.editor.selectedRange()
    view.scrollToOffset(CGFloat.greatestFiniteMagnitude)
    let bottomMetrics = view.scrollMetrics()
    let reachedBottom = (bottomMetrics["offset"] as? CGFloat) == (bottomMetrics["maxExtent"] as? CGFloat)
    view.scrollToOffset(0)
    let topMetrics = view.scrollMetrics()
    let returnedTop = (topMetrics["offset"] as? CGFloat) == 0
    let selectionPreserved = view.editor.selectedRange() == savedSelection
    report["dragReachesBottom"] = reachedBottom
    report["returnsTop"] = returnedTop
    report["selectionPreserved"] = selectionPreserved
    if !reachedBottom || !returnedTop || !selectionPreserved { exit(2) }
    report["finalScrollStateAccurate"] = scrollAccurate
    report["stateTextValid"] = stateTextValid
    let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
    if !draftValid || !commitValid || !scrollAccurate || !stateTextValid { exit(1) }
  }
}
