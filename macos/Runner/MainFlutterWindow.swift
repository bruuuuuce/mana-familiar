import Cocoa
import FlutterMacOS

private func performanceTraceDirectory() -> URL? {
  let arguments = ProcessInfo.processInfo.arguments
  guard let index = arguments.firstIndex(of: "--performance-trace-dir"),
        index + 1 < arguments.count else {
    return nil
  }
  let path = arguments[index + 1]
  guard path.hasPrefix("/") else { return nil }
  return URL(fileURLWithPath: path, isDirectory: true)
}

private func writeNativeWindowPerformance(
  processStartedAt: TimeInterval,
  presentedAt: TimeInterval
) {
  guard let directory = performanceTraceDirectory() else { return }
  let fileManager = FileManager.default
  do {
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let report: [String: Any] = [
      "schema": "mana-familiar.c04.native-window/v1",
      "platform": "macos",
      "process_to_window_presented_us": Int(
        (presentedAt - processStartedAt) * 1_000_000
      ),
      "privacy": [
        "source_content": false,
        "absolute_paths": false,
        "credentials": false,
        "responses": false,
      ],
    ]
    let data = try JSONSerialization.data(
      withJSONObject: report,
      options: [.prettyPrinted, .sortedKeys]
    )
    try data.write(
      to: directory.appendingPathComponent("native-window.json"),
      options: .atomic
    )
  } catch {
    fputs("Mana Familiar performance trace failed: \(error)\n", stderr)
  }
}

class MainFlutterWindow: NSWindow {
  private var closeCoordinator: NativeWindowCloseCoordinator?
  private var performanceVisibilityObserver: NSObjectProtocol?
  private var performancePresentedAt: TimeInterval?

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
    // Interface Builder completes its outlet/delegate wiring in super. Set
    // the lifecycle delegate afterwards so Cmd-W/Cmd-Q reaches the Flutter
    // flush handshake rather than being overwritten by the XIB delegate.
    closeCoordinator = NativeProjectWindowBridge.install(on: flutterViewController, window: self)
    if let appDelegate = NSApp.delegate as? AppDelegate,
       let closeCoordinator {
      appDelegate.installProjectMenu()
      appDelegate.installTerminationPreparation(closeCoordinator)
    }
    // Becoming key is an AppKit-owned upper bound for a presented interactive
    // window and does not require Accessibility permission.
    performanceVisibilityObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification,
      object: self,
      queue: .main
    ) { [weak self] _ in
      self?.recordNativeWindowPresented()
    }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.isVisible else { return }
      self.recordNativeWindowPresented()
    }
  }

  deinit {
    if let performanceVisibilityObserver {
      NotificationCenter.default.removeObserver(performanceVisibilityObserver)
    }
  }

  private func recordNativeWindowPresented() {
    guard performancePresentedAt == nil else { return }
    let presentedAt = ProcessInfo.processInfo.systemUptime
    performancePresentedAt = presentedAt
    let processStartedAt = (NSApp.delegate as? AppDelegate)?
      .performanceProcessStartedAt ?? presentedAt
    writeNativeWindowPerformance(
      processStartedAt: processStartedAt,
      presentedAt: presentedAt
    )
  }

  /// `performClose` is AppKit's common path for the Close Window menu item,
  /// Cmd-W and the title-bar close button. Intercept it on the window itself
  /// because Flutter's embedding may install its own NSWindow delegate after
  /// this XIB has finished loading.
  override func performClose(_ sender: Any?) {
    guard let closeCoordinator else {
      super.performClose(sender)
      return
    }
    closeCoordinator.prepare { [weak self] wasPrepared in
      guard wasPrepared, let self else { return }
      self.performPreparedClose(sender)
    }
  }

  private func performPreparedClose(_ sender: Any?) {
    super.performClose(sender)
    // `applicationShouldTerminateAfterLastWindowClosed` is the usual policy.
    // Retain this explicit fallback for a Flutter embedding that leaves no
    // visible windows but does not initiate termination itself.
    DispatchQueue.main.async {
      if NSApp.windows.allSatisfy({ !$0.isVisible }) {
        NSApp.terminate(nil)
      }
    }
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

  static func install(on controller: FlutterViewController, window: NSWindow) -> NativeWindowCloseCoordinator {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    let coordinator = NativeWindowCloseCoordinator(channel: channel)
    channel.setMethodCallHandler { call, result in
      if call.method == "closePreparationReady" {
        coordinator.markFlutterReady()
        result(nil)
        return
      }
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
    window.delegate = coordinator
    return coordinator
  }
}

/// Cocoa does not wait for Dart `dispose`. Hold the native close request while
/// Flutter flushes its application-owned drafts, then replay the same close
/// action only after the asynchronous acknowledgement arrives.
final class NativeWindowCloseCoordinator: NSObject, NSWindowDelegate {
  private let channel: FlutterMethodChannel
  private var awaitingPreparation = false
  private var mayClose = false
  private var flutterReady = false
  private var preparationAttempts = 0
  private var pendingPreparations: [(Bool) -> Void] = []

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if mayClose { return true }
    prepare { wasPrepared in
      guard wasPrepared else { return }
      sender.performClose(nil)
    }
    return false
  }

  func markFlutterReady() {
    flutterReady = true
  }

  /// Executes all pending completion callbacks after Flutter has durably
  /// flushed the process-local drafts. Multiple close/quit requests collapse
  /// into one channel call, preserving the first request rather than racing
  /// a second `performClose` against it.
  func prepare(_ completion: @escaping (Bool) -> Void) {
    if mayClose {
      completion(true)
      return
    }
    // Flutter has not mounted an input field yet, therefore there is no draft
    // to flush. Do not trap an early native Close behind an absent receiver.
    guard flutterReady else {
      mayClose = true
      completion(true)
      return
    }
    pendingPreparations.append(completion)
    guard !awaitingPreparation else { return }
    preparationAttempts = 0
    invokePreparation()
  }

  private func invokePreparation() {
    awaitingPreparation = true
    preparationAttempts += 1
    channel.invokeMethod("prepareToClose", arguments: nil) { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        self.awaitingPreparation = false
        let wasPrepared = result == nil
        // The engine can briefly report MethodNotImplemented while a desktop
        // refresh swaps a platform handler. Keep the window and its draft in
        // place, then retry the same preparation rather than misclassifying
        // that transient state as a completed close.
        if !wasPrepared && self.preparationAttempts < 3 {
          DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) {
            guard !self.mayClose, !self.awaitingPreparation,
                  !self.pendingPreparations.isEmpty else { return }
            self.invokePreparation()
          }
          return
        }
        if wasPrepared { self.mayClose = true }
        let completions = self.pendingPreparations
        self.pendingPreparations.removeAll()
        completions.forEach { $0(wasPrepared) }
      }
    }
  }
}
