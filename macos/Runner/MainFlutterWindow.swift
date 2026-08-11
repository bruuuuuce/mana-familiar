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

    super.awakeFromNib()
  }

  private func initialBackgroundColor() -> NSColor {
    if let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first {
      for directory in ["Mana Familiar", "Mana Learning Explorer"] {
        let path = applicationSupport
          .appendingPathComponent("\(directory)/preferences.json")
          .path
        if let source = try? String(contentsOfFile: path),
           source.contains("\"themeMode\":\"dark\"") ||
           source.contains("\"themeMode\": \"dark\"") {
          return .black
        }
        if FileManager.default.fileExists(atPath: path) {
          // The first existing file is authoritative. Once migrated, an old
          // dark preference must not override a newer non-dark preference.
          return .windowBackgroundColor
        }
      }
    }
    // Dynamic system color also updates when macOS appearance changes.
    return .windowBackgroundColor
  }
}
