import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let projectMenuController = ProjectMenuController()

  /// Called after MainMenu.xib has loaded its menu hierarchy.
  func installProjectMenu() {
    projectMenuController.install(in: NSApp.mainMenu)
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
    do {
      try Process.run(
        URL(fileURLWithPath: executable),
        arguments: ["--project-root", url.path]
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
    UserDefaults.standard.set(Array(entries.prefix(maximumRecentProjects)), forKey: recentProjectsKey)
  }

  static func clearRecentProjectsStorage() {
    UserDefaults.standard.removeObject(forKey: recentProjectsKey)
  }

  private static func remove(_ url: URL) {
    let path = url.standardizedFileURL.path
    UserDefaults.standard.set(recentProjects().filter { $0 != path }, forKey: recentProjectsKey)
  }

  private static func recentProjects() -> [String] {
    ((UserDefaults.standard.array(forKey: recentProjectsKey) as? [String]) ?? [])
      .filter(isUsableProjectRoot)
  }

  private static func isUsableProjectRoot(_ path: String) -> Bool {
    URL(fileURLWithPath: path).standardizedFileURL.pathComponents.count > 1
  }
}
