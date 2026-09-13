import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let projectMenuController = ProjectMenuController()
  private weak var closeCoordinator: NativeWindowCloseCoordinator?

  /// Called after MainMenu.xib has loaded its menu hierarchy.
  func installProjectMenu() {
    projectMenuController.install(in: NSApp.mainMenu)
  }

  /// Cocoa asks for termination before Flutter has a chance to dispose its
  /// widget tree. Delay the reply until the window bridge has flushed drafts.
  func installTerminationPreparation(_ coordinator: NativeWindowCloseCoordinator) {
    closeCoordinator = coordinator
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let closeCoordinator else { return .terminateNow }
    closeCoordinator.prepare { shouldTerminate in
      DispatchQueue.main.async {
        sender.reply(toApplicationShouldTerminate: shouldTerminate)
      }
    }
    return .terminateLater
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

/// Native File-menu support for project-oriented app windows.
/// Each selection starts another Runner process, which gives macOS a separate
/// window and makes it available through the standard Window menu/Exposé UI.
final class ProjectMenuController: NSObject, NSMenuDelegate {
  private static let recentProjectsKey = "recentProjectRoots"
  private static let maximumRecentProjects = 10

  private var recentMenu: NSMenu?

  /// Test and portable launches may supply an isolated preferences directory.
  /// Keep the native recent-project list in the matching isolated defaults
  /// suite so opening another native window never mutates a user's recents.
  private static var defaults: UserDefaults {
    guard let root = argumentValue("--preferences-root"), !root.isEmpty else {
      return .standard
    }
    return UserDefaults(suiteName: "com.mana.familiar.preferences.\(stableHash(root))") ?? .standard
  }

  private static func argumentValue(_ flag: String) -> String? {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
      return nil
    }
    return arguments[index + 1]
  }

  private static func stableHash(_ value: String) -> String {
    var hash: UInt64 = 1469598103934665603
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1099511628211
    }
    return String(hash, radix: 16)
  }

  func install(in mainMenu: NSMenu?) {
    guard let mainMenu, mainMenu.item(withTitle: "File") == nil else { return }

    let fileMenu = NSMenu(title: "File")
    let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    fileItem.submenu = fileMenu

    let openItem = NSMenuItem(
      title: "Open Project…",
      action: #selector(openProject),
      keyEquivalent: "o"
    )
    openItem.target = self
    fileMenu.addItem(openItem)

    let recents = NSMenu(title: "Open Recent")
    recents.delegate = self
    let recentsItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
    recentsItem.submenu = recents
    fileMenu.addItem(recentsItem)
    recentMenu = recents

    fileMenu.addItem(.separator())
    let closeItem = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    fileMenu.addItem(closeItem)
    mainMenu.insertItem(fileItem, at: 1)
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    guard menu == recentMenu else { return }
    menu.removeAllItems()
    let projects = Self.recentProjects()
    guard !projects.isEmpty else {
      let empty = NSMenuItem(title: "No Recent Projects", action: nil, keyEquivalent: "")
      empty.isEnabled = false
      menu.addItem(empty)
      return
    }

    for path in projects {
      let url = URL(fileURLWithPath: path)
      let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecentProject(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = path
      item.toolTip = path
      menu.addItem(item)
    }
    menu.addItem(.separator())
    let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecentProjects), keyEquivalent: "")
    clear.target = self
    menu.addItem(clear)
  }

  @objc private func openProject() {
    guard let url = Self.chooseProject() else { return }
    open(url)
  }

  static func chooseProject() -> URL? {
    let panel = NSOpenPanel()
    panel.title = "Open Mana project"
    panel.message = "Choose the project folder to open in a new Mana Familiar window."
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Open"
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return url
  }

  @objc private func openRecentProject(_ sender: NSMenuItem) {
    guard let path = sender.representedObject as? String else { return }
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      Self.remove(url)
      return
    }
    open(url)
  }

  @objc private func clearRecentProjects() {
    Self.clearRecentProjectsStorage()
  }

  private func open(_ url: URL) {
    Self.remember(url)
    let executable = ProcessInfo.processInfo.arguments[0]
    var arguments = ["--project-root", url.path]
    for flag in ["--mana-root", "--preferences-root"] {
      if let value = Self.argumentValue(flag), !value.isEmpty {
        arguments.append(contentsOf: [flag, value])
      }
    }
    // A new native Runner process needs independent recoverable drafts even
    // when it observes the same project as the originating window.
    arguments.append(contentsOf: ["--window-session", UUID().uuidString])
    do {
      try Process.run(
        URL(fileURLWithPath: executable),
        arguments: arguments
      )
    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
    }
  }

  static func remember(_ url: URL) {
    let path = url.standardizedFileURL.path
    guard isUsableProjectRoot(path) else { return }
    let entries = [path] + recentProjects().filter { $0 != path }
    defaults.set(Array(entries.prefix(maximumRecentProjects)), forKey: recentProjectsKey)
  }

  static func clearRecentProjectsStorage() {
    defaults.removeObject(forKey: recentProjectsKey)
  }

  private static func remove(_ url: URL) {
    let path = url.standardizedFileURL.path
    defaults.set(recentProjects().filter { $0 != path }, forKey: recentProjectsKey)
  }

  private static func recentProjects() -> [String] {
    ((defaults.array(forKey: recentProjectsKey) as? [String]) ?? [])
      .filter(isUsableProjectRoot)
  }

  private static func isUsableProjectRoot(_ path: String) -> Bool {
    URL(fileURLWithPath: path).standardizedFileURL.pathComponents.count > 1
  }
}
