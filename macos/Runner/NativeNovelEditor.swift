import Cocoa
import CoreText
import FlutterMacOS

final class NovelPlainTextView: NSTextView {
  var onAction: ((String) -> Void)?
  var onKeystroke: (() -> Void)?
  var onInputCompleted: (() -> Void)?
  private(set) var inputDepth = 0
  var changeOrigin = "input"
  override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
    guard let font = typingAttributes[.font] as? NSFont ?? self.font,
          let layout = layoutManager else {
      super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
      return
    }
    // Use the typeface's CJK body and baseline, not the paragraph's line spacing.
    var character: UniChar = 0x56FD
    var glyph: CGGlyph = 0
    let hasBody = CTFontGetGlyphsForCharacters(font as CTFont, &character, &glyph, 1)
    let body = hasBody ? font.boundingRect(forGlyph: NSGlyph(glyph)) :
      NSRect(x: 0, y: font.descender, width: 0, height: font.capHeight - font.descender)
    var caret = rect
    caret.size.height = min(rect.height, max(font.pointSize, body.height))
    let baseline = rect.maxY - (layout.defaultLineHeight(for: font) - layout.defaultBaselineOffset(for: font))
    caret.origin.y = max(rect.minY, min(rect.maxY - caret.height, baseline - body.midY - caret.height / 2))
    super.drawInsertionPoint(in: caret, color: color, turnedOn: flag)
  }
  override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    inputDepth += 1
    super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    inputDepth -= 1
    if inputDepth == 0 { onInputCompleted?() }
  }
  override func insertText(_ string: Any, replacementRange: NSRange) {
    inputDepth += 1
    super.insertText(string, replacementRange: replacementRange)
    inputDepth -= 1
    if inputDepth == 0 { onInputCompleted?() }
  }
  override func unmarkText() {
    inputDepth += 1
    super.unmarkText()
    inputDepth -= 1
    if inputDepth == 0 { onInputCompleted?() }
  }
  override func paste(_ sender: Any?) {
    changeOrigin = "paste"
    defer { changeOrigin = "input" }
    super.paste(sender)
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 && !hasMarkedText() {
      onAction?("exitFocus"); return
    }
    if event.modifierFlags.intersection([.command, .control]).isEmpty {
      let printable = (event.characters ?? "").unicodeScalars.contains {
        $0.value >= 0x20 && !($0.value >= 0xF700 && $0.value <= 0xF8FF)
      }
      if printable || [36, 48, 51, 76, 117].contains(event.keyCode) { onKeystroke?() }
    }
    super.keyDown(with: event)
  }
}

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
  let editor = NovelPlainTextView()
  private var channel: FlutterMethodChannel?
  private var loading = false
  private var configuration: [String: Any] = [:]
  private var pendingConfiguration: [String: Any]?
  private var documentID: String?
  private var scrollObserver: NSObjectProtocol?
  private var pendingScrollUpdate: DispatchWorkItem?
  private var lastReportedScroll: [CGFloat]?
  private var lastReportedDocument: String?
  private var documentGeneration = 0
  private var wasComposing = false
  private var acceptsPointerEvents = true
  private var typingSounds: [NSSound] = []
  private var soundIndex = 0

  init(viewId: Int64, messenger: FlutterBinaryMessenger, arguments: [String: Any]) {
    super.init(frame: .zero)
    borderType = .noBorder
    hasVerticalScroller = false
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
    editor.textContainer?.widthTracksTextView = false
    editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    editor.layoutManager?.allowsNonContiguousLayout = true
    editor.minSize = .zero
    editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
    documentView = editor
    editor.delegate = self
    channel = FlutterMethodChannel(name: "inkflow/editor/\(viewId)",
                                    binaryMessenger: messenger)
    editor.onAction = { [weak self] action in self?.channel?.invokeMethod(action, arguments: nil) }
    editor.onKeystroke = { [weak self] in self?.playTypingSound() }
    editor.onInputCompleted = { [weak self] in
      guard let self = self else { return }
      self.textDidChange(Notification(name: NSText.didChangeNotification, object: self.editor))
    }
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let values = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "configure": self.configure(values); result(nil)
      case "load": self.load(values); result(nil)
      case "focus": _ = self.window?.makeFirstResponder(self.editor); result(nil)
      case "interactive": self.acceptsPointerEvents = call.arguments as? Bool ?? true; result(nil)
      case "sound":
        self.typingSounds.forEach { $0.stop() }
        self.typingSounds = []
        if let bytes = values["bytes"] as? FlutterStandardTypedData {
          self.typingSounds = (0..<4).compactMap { _ in NSSound(data: bytes.data) }
        }
        if values["preview"] as? Bool == true { self.playTypingSound() }
        result(nil)
      case "getState": result(self.currentState())
      case "lockForUpdate":
        guard let locked = call.arguments as? Bool else {
          result(FlutterError(code: "invalid_lock", message: "更新锁参数不合法", details: nil)); return
        }
        result(self.setUpdateLocked(locked))
      case "scrollTo":
        if values["documentId"] as? String == self.documentID && values["documentGeneration"] as? Int == self.documentGeneration {
          self.scrollToOffset(CGFloat((values["offset"] as? NSNumber)?.doubleValue ?? 0))
        }
        result(nil)
      case "replaceRange":
        do { result(try self.replaceRange(values)) }
        catch { result(FlutterError(code: "stale_edit", message: error.localizedDescription, details: nil)) }
      case "commitComposition":
        if self.editor.hasMarkedText() { self.editor.unmarkText() }
        result(self.currentState())
      default: result(FlutterMethodNotImplemented)
      }
    }
    configure(arguments)
    load(arguments)
    contentView.postsBoundsChangedNotifications = true
    scrollObserver = NotificationCenter.default.addObserver(
      forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main
    ) { [weak self] _ in
      guard let self = self, !self.loading else { return }
      self.scheduleScrollUpdate()
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  // Let Flutter's menu barriers receive outside clicks without hiding the text.
  override func hitTest(_ point: NSPoint) -> NSView? {
    acceptsPointerEvents ? super.hitTest(point) : nil
  }

  private func playTypingSound() {
    guard !typingSounds.isEmpty else { return }
    let sound = typingSounds[soundIndex % typingSounds.count]
    soundIndex += 1
    if sound.isPlaying { sound.stop() }
    sound.currentTime = 0
    sound.play()
  }

  override func layout() {
    super.layout()
    guard let container = editor.textContainer else { return }
    var frame = editor.frame
    let nextSize = NSSize(width: contentSize.width, height: max(frame.height, contentSize.height))
    if frame.size != nextSize {
      frame.size = nextSize
      editor.frame = frame
    }
    let gutter = CGFloat((configuration["scrollbarGutter"] as? NSNumber)?.doubleValue ?? 0)
    let fullWidth = contentSize.width + gutter
    let maximum = CGFloat((configuration["maxWidth"] as? NSNumber)?.doubleValue ?? 760)
    let bodyWidth = max(1, min(maximum, fullWidth - 96))
    let inset = max(0, (fullWidth - bodyWidth) / 2)
    if editor.textContainerInset.width != inset { editor.textContainerInset = NSSize(width: inset, height: 10) }
    if container.containerSize.width != bodyWidth {
      container.containerSize = NSSize(width: bodyWidth, height: CGFloat.greatestFiniteMagnitude)
    }
    scheduleScrollUpdate()
  }

  func scrollToOffset(_ offset: CGFloat) {
    let maximum = max(0, editor.frame.height - contentView.bounds.height)
    contentView.scroll(to: NSPoint(x: 0, y: max(0, min(offset, maximum))))
    reflectScrolledClipView(contentView)
    scheduleScrollUpdate()
  }

  func scrollMetrics() -> [String: Any] {
    let maximum = max(0, editor.frame.height - contentView.bounds.height)
    return ["documentId": documentID ?? "probe", "documentGeneration": documentGeneration,
      "offset": max(0, min(contentView.bounds.origin.y, maximum)),
      "maxExtent": maximum, "viewport": contentView.bounds.height]
  }

  private func scheduleScrollUpdate() {
    guard pendingScrollUpdate == nil else { return }
    let update = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      self.pendingScrollUpdate = nil
      guard !self.loading else { return }
      let values = self.scrollMetrics()
      let next = [values["offset"] as! CGFloat, values["maxExtent"] as! CGFloat, values["viewport"] as! CGFloat]
      let identity = "\(self.documentID ?? "probe")/\(self.documentGeneration)"
      guard self.lastReportedScroll != next || self.lastReportedDocument != identity else { return }
      self.lastReportedScroll = next
      self.lastReportedDocument = identity
      self.channel?.invokeMethod("scrolled", arguments: values)
    }
    pendingScrollUpdate = update
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: update)
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
    needsLayout = true
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
    editor.drawsBackground = background.alphaComponent > 0
    editor.insertionPointColor = foreground
    editor.setSelectedRange(selection)
    editor.undoManager?.enableUndoRegistration()
    loading = false
  }

  private func load(_ values: [String: Any]) {
    guard let text = values["text"] as? String else { return }
    documentGeneration = values["documentGeneration"] as? Int ?? 0
    let nextID = values["documentId"] as? String
    let changed = text != editor.string || nextID != documentID
    pendingScrollUpdate?.cancel()
    pendingScrollUpdate = nil
    lastReportedScroll = nil
    loading = true
    if changed {
      editor.string = text
      editor.undoManager?.removeAllActions()
      documentID = nextID
    }
    let length = (text as NSString).length
    let base = max(0, min(length, values["selectionBase"] as? Int ?? 0))
    let extent = max(0, min(length, values["selectionExtent"] as? Int ?? base))
    editor.setSelectedRange(NSRange(location: min(base, extent), length: abs(base - extent)))
    loading = false
    if changed { configure(configuration) }
    editor.scrollRangeToVisible(editor.selectedRange())
    if let offset = values["scrollOffset"] as? NSNumber {
      let y = max(0, min(CGFloat(offset.doubleValue), editor.frame.height - contentSize.height))
      contentView.scroll(to: NSPoint(x: 0, y: y))
      reflectScrolledClipView(contentView)
    }
    wasComposing = editor.hasMarkedText()
    needsLayout = true
    scheduleScrollUpdate()
  }

  func replaceRange(_ values: [String: Any]) throws -> [String: Any] {
    let start = values["rangeStart"] as? Int ?? -1
    let end = values["rangeEnd"] as? Int ?? -1
    let length = (editor.string as NSString).length
    guard values["documentId"] as? String == documentID,
          values["expectedText"] as? String == editor.string,
          !editor.hasMarkedText(), start >= 0, end >= start, end <= length,
          let replacement = values["replacement"] as? String else {
      throw NSError(domain: "InkFlow", code: 1, userInfo: [NSLocalizedDescriptionKey: "正文已变化，请重新打开排版预览"])
    }
    let range = NSRange(location: start, length: end - start)
    editor.breakUndoCoalescing()
    editor.undoManager?.beginUndoGrouping()
    loading = true
    defer { loading = false; editor.undoManager?.endUndoGrouping(); editor.breakUndoCoalescing() }
    guard editor.shouldChangeText(in: range, replacementString: replacement) else {
      throw NSError(domain: "InkFlow", code: 2, userInfo: [NSLocalizedDescriptionKey: "编辑器暂不可编辑"])
    }
    editor.textStorage?.replaceCharacters(in: range, with: replacement)
    editor.didChangeText()
    editor.setSelectedRange(NSRange(location: start + (replacement as NSString).length, length: 0))
    editor.undoManager?.setActionName("排版整理")
    var state = currentState()
    state["origin"] = "format"
    return state
  }

  private func selectionState() -> [String: Any] {
    let range = editor.selectedRange()
    let composing = editor.hasMarkedText() ? editor.markedRange() : NSRange(location: NSNotFound, length: 0)
    return ["selectionBase": range.location,
      "selectionExtent": range.location + range.length,
      "composingStart": composing.location == NSNotFound ? -1 : composing.location,
      "composingEnd": composing.location == NSNotFound ? -1 : composing.location + composing.length]
  }

  func setUpdateLocked(_ locked: Bool) -> [String: Any] {
    let selection = editor.selectedRange()
    let scroll = contentView.bounds.origin
    let previousLoading = loading
    let previousOrigin = editor.changeOrigin
    loading = true
    editor.changeOrigin = "update"
    defer { loading = previousLoading; editor.changeOrigin = previousOrigin }
    if locked && editor.hasMarkedText() { editor.unmarkText() }
    editor.isEditable = !locked
    editor.setSelectedRange(selection)
    contentView.scroll(to: scroll)
    reflectScrolledClipView(contentView)
    wasComposing = editor.hasMarkedText()
    return currentState()
  }

  private func currentState() -> [String: Any] {
    var state = selectionState()
    state["text"] = editor.string
    state["isComposing"] = editor.hasMarkedText()
    state["isUpdateLocked"] = !editor.isEditable
    state["origin"] = editor.undoManager?.isUndoing == true ? "undo" :
      (editor.undoManager?.isRedoing == true ? "redo" : editor.changeOrigin)
    state["scrollOffset"] = contentView.bounds.origin.y
    return state
  }

  func textDidChange(_ notification: Notification) {
    guard editor.inputDepth == 0 else { return }
    if !editor.hasMarkedText(), let pending = pendingConfiguration {
      pendingConfiguration = nil
      configure(pending)
    }
    if !loading { emitTextState() }
  }

  func textViewDidChangeSelection(_ notification: Notification) {
    guard !loading, editor.inputDepth == 0 else { return }
    if wasComposing != editor.hasMarkedText() {
      emitTextState()
    } else {
      channel?.invokeMethod("selection", arguments: selectionState())
    }
  }

  private func emitTextState() {
    wasComposing = editor.hasMarkedText()
    channel?.invokeMethod("changed", arguments: currentState())
  }

  deinit {
    pendingScrollUpdate?.cancel()
    typingSounds.forEach { $0.stop() }
    if let observer = scrollObserver { NotificationCenter.default.removeObserver(observer) }
    channel?.setMethodCallHandler(nil)
  }
}
