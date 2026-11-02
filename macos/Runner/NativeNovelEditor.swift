import Cocoa
import FlutterMacOS

final class NovelEditorFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    NativeNovelEditor(viewId: viewId, messenger: messenger,
                      arguments: args as? [String: Any] ?? [:])
  }
}

final class NativeNovelEditor: NSScrollView, NSTextViewDelegate {
  let editor = NSTextView()
  private var channel: FlutterMethodChannel?
  private var loading = false
  private var configuration: [String: Any] = [:]
  private var pendingConfiguration: [String: Any]?

  init(viewId: Int64, messenger: FlutterBinaryMessenger, arguments: [String: Any]) {
    super.init(frame: .zero)
    borderType = .noBorder
    hasVerticalScroller = true
    autohidesScrollers = true
    drawsBackground = false
    editor.isRichText = false
    editor.importsGraphics = false
    editor.allowsUndo = true
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.isAutomaticTextReplacementEnabled = false
    editor.isAutomaticSpellingCorrectionEnabled = false
    editor.isContinuousSpellCheckingEnabled = false
    editor.isHorizontallyResizable = false
    editor.isVerticallyResizable = true
    editor.autoresizingMask = [.width]
    editor.textContainerInset = NSSize(width: 0, height: 10)
    editor.textContainer?.lineFragmentPadding = 0
    editor.textContainer?.widthTracksTextView = true
    editor.layoutManager?.allowsNonContiguousLayout = true
    editor.minSize = .zero
    editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
    documentView = editor
    editor.delegate = self
    channel = FlutterMethodChannel(name: "inkflow/editor/\(viewId)",
                                    binaryMessenger: messenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let values = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "configure": self.configure(values); result(nil)
      case "load": self.load(values); result(nil)
      case "getState": result(self.currentState())
      default: result(FlutterMethodNotImplemented)
      }
    }
    configure(arguments)
    load(arguments)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func layout() {
    super.layout()
    guard let container = editor.textContainer else { return }
    container.containerSize = NSSize(width: contentSize.width,
                                     height: CGFloat.greatestFiniteMagnitude)
    var frame = editor.frame
    frame.size.width = contentSize.width
    frame.size.height = max(frame.height, contentSize.height)
    editor.frame = frame
  }

  private func color(_ value: Any?, fallback: NSColor) -> NSColor {
    guard let number = value as? NSNumber else { return fallback }
    let argb = number.uint32Value
    return NSColor(srgbRed: CGFloat((argb >> 16) & 255) / 255,
      green: CGFloat((argb >> 8) & 255) / 255,
      blue: CGFloat(argb & 255) / 255, alpha: CGFloat((argb >> 24) & 255) / 255)
  }

  func configure(_ values: [String: Any]) {
    if editor.hasMarkedText() {
      pendingConfiguration = values
      return
    }
    configuration = values
    let fontSize = CGFloat((values["fontSize"] as? NSNumber)?.doubleValue ?? 20)
    let family = values["fontFamily"] as? String ?? "Songti SC"
    let font = NSFont(name: family, size: fontSize)
      ?? NSFont(name: "Songti SC", size: fontSize)
      ?? NSFont.systemFont(ofSize: fontSize)
    let paragraph = NSMutableParagraphStyle()
    paragraph.firstLineHeadIndent = fontSize * CGFloat(
      (values["firstLineIndentEm"] as? NSNumber)?.doubleValue ?? 2)
    paragraph.headIndent = 0
    paragraph.paragraphSpacing = CGFloat(
      (values["paragraphGap"] as? NSNumber)?.doubleValue ?? 8)
    let height = fontSize * CGFloat((values["lineHeight"] as? NSNumber)?.doubleValue ?? 1.8)
    paragraph.minimumLineHeight = height
    paragraph.maximumLineHeight = height
    let foreground = color(values["textColor"], fallback: .textColor)
    let background = color(values["backgroundColor"], fallback: .textBackgroundColor)
    let selection = editor.selectedRange()
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font, .foregroundColor: foreground, .paragraphStyle: paragraph
    ]
    loading = true
    editor.undoManager?.disableUndoRegistration()
    editor.typingAttributes = attributes
    editor.defaultParagraphStyle = paragraph
    editor.textStorage?.addAttributes(attributes,
      range: NSRange(location: 0, length: (editor.string as NSString).length))
    editor.font = font
    editor.textColor = foreground
    editor.backgroundColor = background
    editor.insertionPointColor = foreground
    editor.setSelectedRange(selection)
    editor.undoManager?.enableUndoRegistration()
    loading = false
  }

  private func load(_ values: [String: Any]) {
    guard let text = values["text"] as? String else { return }
    guard text != editor.string else { return }
    loading = true
    editor.string = text
    editor.undoManager?.removeAllActions()
    let length = (text as NSString).length
    let base = max(0, min(length, values["selectionBase"] as? Int ?? 0))
    let extent = max(0, min(length, values["selectionExtent"] as? Int ?? base))
    editor.setSelectedRange(NSRange(location: min(base, extent), length: abs(base - extent)))
    loading = false
    configure(configuration)
    editor.scrollRangeToVisible(editor.selectedRange())
  }

  private func currentState() -> [String: Any] {
    let range = editor.selectedRange()
    let composing = editor.markedRange()
    return ["text": editor.string,
      "selectionBase": range.location,
      "selectionExtent": range.location + range.length,
      "composingStart": composing.location == NSNotFound ? -1 : composing.location,
      "composingEnd": composing.location == NSNotFound ? -1 : composing.location + composing.length]
  }

  func textDidChange(_ notification: Notification) {
    if !editor.hasMarkedText(), let pending = pendingConfiguration {
      pendingConfiguration = nil
      configure(pending)
    }
    if !loading { channel?.invokeMethod("changed", arguments: currentState()) }
  }

  func textViewDidChangeSelection(_ notification: Notification) {
    if !loading { channel?.invokeMethod("changed", arguments: currentState()) }
  }

  deinit { channel?.setMethodCallHandler(nil) }
}
