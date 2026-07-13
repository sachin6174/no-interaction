import Cocoa
import SwiftUI

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Keep a strong reference — without this ARC would release the delegate
    // before applicationDidFinishLaunching fires on some macOS versions.
    static var shared: AppDelegate!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Show Dock icon as requested by user
        NSApp.setActivationPolicy(.regular)

        if let iconImage = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = iconImage
        }

        MenuBarManager.shared.setupMenuBar()

        // Open dashboard on first launch so user sees the permission guide
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            MenuBarManager.shared.showDashboard()
        }

        print("⚡ NoInteraction started — listening for Anti-Gravity prompts")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Stay alive in the menu bar even when dashboard is closed
        return false
    }
}

// MARK: - Entry Point

@main
struct NoInteractionApp {
    static func main() {
        let app      = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.shared = delegate   // retain strongly
        app.delegate = delegate
        app.run()
    }
}
