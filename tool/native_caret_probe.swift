import Cocoa
import FlutterMacOS

final class CaretMessenger: NSObject, FlutterBinaryMessenger {
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) { callback?(nil) }
  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection { 1 }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

@main
struct NativeCaretProbe {
  static func main() {
    _ = NSApplication.shared
    var passed = true
    for size in [16.0, 20.0, 28.0] {
      for lineHeight in [1.2, 1.8, 2.6] {
        let view = NativeNovelEditor(viewId: 1, messenger: CaretMessenger(), arguments: [
          "text": "舞台之外，是无边无际的黑暗与死寂。", "fontFamily": "Songti SC",
          "fontSize": size, "lineHeight": lineHeight
        ])
        view.frame = NSRect(x: 0, y: 0, width: 760, height: 400)
        view.layout()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 120,
          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        view.editor.drawInsertionPoint(in: NSRect(x: 40, y: 10, width: 1, height: size * lineHeight), color: .red, turnedOn: true)
        NSGraphicsContext.restoreGraphicsState()
        var rows: [Int] = []
        for y in 0..<120 {
          for x in 0..<80 {
            let color = bitmap.colorAt(x: x, y: y)!
            if color.redComponent > 0.8 && color.greenComponent < 0.2 && color.alphaComponent > 0.5 { rows.append(y); break }
          }
        }
        let height = rows.isEmpty ? 0 : rows.max()! - rows.min()! + 1
        let fits = height >= Int(size * 0.85) && height <= Int(size + 3)
        passed = passed && fits
        print("font=\(Int(size)) lineHeight=\(lineHeight) caretPixels=\(height) fits=\(fits)")
      }
    }
    if !passed { exit(1) }
  }
}
