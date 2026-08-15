import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Keep the native surface aligned with macOS appearance while Flutter is
    // constructing its first themed frame.  The Flutter app waits for its
    // persisted preference before runApp, so this avoids a bright system-dark
    // launch flash without hard-coding an appearance for the whole window.
    self.backgroundColor = initialBackgroundColor()
    self.isOpaque = true
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    NativeProjectWindowBridge.install(on: flutterViewController, window: self)

    super.awakeFromNib()
    (NSApp.delegate as? AppDelegate)?.installProjectMenu()
  }

  private func initialBackgroundColor() -> NSColor {
    if let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first {
      let path = applicationSupport
        .appendingPathComponent("Mana Familiar/preferences.json")
        .path
      if let source = try? String(contentsOfFile: path),
         source.contains("\"themeMode\":\"dark\"") ||
         source.contains("\"themeMode\": \"dark\"") {
        return .black
      }
    }
    // Dynamic system color also updates when macOS appearance changes.
    return .windowBackgroundColor
  }
}

private enum NativeProjectWindowBridge {
  static let channelName = "mana_familiar/project_window"

  static func install(on controller: FlutterViewController, window: NSWindow) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      if call.method == "chooseProject" {
        result(ProjectMenuController.chooseProject()?.path)
        return
      }
      if call.method == "clearRecentProjects" {
        ProjectMenuController.clearRecentProjectsStorage()
        result(nil)
        return
      }

      guard call.method == "presentProject",
            let arguments = call.arguments as? [String: Any],
            let projectRoot = arguments["projectRoot"] as? String,
            !projectRoot.isEmpty else {
        result(FlutterMethodNotImplemented)
        return
      }

      let url = URL(fileURLWithPath: projectRoot).standardizedFileURL
      window.title = "\(url.lastPathComponent) — Mana Familiar"
      ProjectMenuController.remember(url)
      result(nil)
    }
  }
}
