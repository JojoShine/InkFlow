import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var directoryAccess: DirectoryAccess?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let registrar = flutterViewController.registrar(forPlugin: "InkFlowEditor")
    registrar.register(NovelEditorFactory(messenger: registrar.messenger),
                       withId: "inkflow/novel-editor")
    directoryAccess = DirectoryAccess(messenger: registrar.messenger)
    (NSApplication.shared.delegate as? AppDelegate)?.configureLifecycle(messenger: registrar.messenger)

    super.awakeFromNib()
  }
}
