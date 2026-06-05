import AppKit

/// Hooks `MenuBarExtra`’s underlying status item so a **right-click** can show Quit (SwiftUI does not expose this for `.window` style).
final class BeatBarAppDelegate: NSObject, NSApplicationDelegate {
    private var rightMouseUpMonitor: Any?
    private var installAttempts = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        scheduleRightClickQuitMenuInstall()
    }

    private func scheduleRightClickQuitMenuInstall() {
        DispatchQueue.main.async { [weak self] in
            self?.tryInstallRightClickQuitMenu()
        }
    }

    private func tryInstallRightClickQuitMenu() {
        installAttempts += 1
        if hasStatusBarButtonInWindowHierarchy() {
            installRightMouseUpMonitorIfNeeded()
            return
        }
        if installAttempts < AppConstants.menuBarExtraQuitMenuInstallMaxAttempts {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + AppConstants.menuBarExtraQuitMenuInstallRetryDelaySeconds
            ) { [weak self] in
                self?.tryInstallRightClickQuitMenu()
            }
        } else {
            installRightMouseUpMonitorIfNeeded()
        }
    }

    /// `NSStatusBar.system.statusItems` is not always exposed to Swift; walk our windows instead.
    private func hasStatusBarButtonInWindowHierarchy() -> Bool {
        NSApp.windows.contains { window in
            guard let root = window.contentView else { return false }
            return viewHierarchyContainsStatusBarButton(root)
        }
    }

    private func viewHierarchyContainsStatusBarButton(_ view: NSView) -> Bool {
        if view is NSStatusBarButton { return true }
        return view.subviews.contains(where: viewHierarchyContainsStatusBarButton)
    }

    private func installRightMouseUpMonitorIfNeeded() {
        guard rightMouseUpMonitor == nil else { return }
        rightMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseUp]) { [weak self] event in
            guard let self else { return event }
            guard let button = self.statusBarButtonContainingScreenPoint(NSEvent.mouseLocation) else {
                return event
            }
            self.presentQuitMenu(for: button, with: event)
            return nil
        }
    }

    private func statusBarButtonContainingScreenPoint(_ screenPoint: NSPoint) -> NSStatusBarButton? {
        for window in NSApp.windows {
            guard window.frame.contains(screenPoint) else { continue }
            let pointInWindow = window.convertPoint(fromScreen: screenPoint)
            guard let contentView = window.contentView else { continue }
            var view: NSView? = contentView.hitTest(pointInWindow)
            while let current = view {
                if let button = current as? NSStatusBarButton {
                    return button
                }
                view = current.superview
            }
        }
        return nil
    }

    private func presentQuitMenu(for button: NSStatusBarButton, with event: NSEvent) {
        let menu = NSMenu()
        let quitTitle = String(format: AppConstants.menuBarExtraQuitMenuItemTitleFormat, appDisplayName)
        let quitItem = NSMenuItem(
            title: quitTitle,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: AppConstants.menuBarExtraQuitMenuKeyEquivalent
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = NSApp
        menu.addItem(quitItem)
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    private var appDisplayName: String {
        if let display = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "BeatBar"
    }
}
