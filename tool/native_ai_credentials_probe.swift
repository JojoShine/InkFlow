// Compile this file together with macos/Runner/AiCredentials.swift and link FlutterMacOS.
// Uses only a unique, disposable InkFlow credential; no existing secrets are read.
import Cocoa
import FlutterMacOS
final class ProbeMessenger: NSObject, FlutterBinaryMessenger {
 var handler: FlutterBinaryMessageHandler?
 func send(onChannel channel: String, message: Data?) {}
 func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {}
 func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection { self.handler=handler;return 1 }
 func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) { handler=nil }
}

enum ProbeFailure: Error { case failed }
@main
struct CredentialProbe {
  static func main() throws {
    let messenger=ProbeMessenger()
    let credentials=AiCredentials(messenger:messenger)
    let codec=FlutterStandardMethodCodec.sharedInstance()
    let id=(UUID().uuidString+UUID().uuidString).replacingOccurrences(of:"-",with:"").lowercased()
    func invoke(_ method:String,_ key:String?=nil)->Any? {
     var args:[String:Any]=["id":id];if let key=key { args["key"]=key }
     let call=FlutterMethodCall(methodName:method,arguments:args)
     var result:Any?
     messenger.handler?(codec.encode(call)){ data in if let data=data {result=codec.decodeEnvelope(data)} }
     return result
    }
    defer { _ = invoke("delete") }
    if let error=invoke("write","inkflow-temporary-probe") as? FlutterError { print("write failed: \(error.code)");throw ProbeFailure.failed }
    guard invoke("read") as? String == "inkflow-temporary-probe" else {print("read failed");throw ProbeFailure.failed}
    if let error=invoke("write","inkflow-temporary-probe-updated") as? FlutterError { print("update failed: \(error.code)");throw ProbeFailure.failed }
    guard invoke("read") as? String == "inkflow-temporary-probe-updated" else {print("updated read failed");throw ProbeFailure.failed}
    if let error=invoke("delete") as? FlutterError {print("delete failed: \(error.code)");throw ProbeFailure.failed}
    guard invoke("read")==nil else {print("deleted credential remains");throw ProbeFailure.failed}
    print("native credential write/read/update/delete passed")
  }
}
