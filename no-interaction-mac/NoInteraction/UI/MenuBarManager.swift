import Cocoa
import SwiftUI

@MainActor
public final class MenuBarManager: NSObject {
    public static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?
    private var dashboardWindow: NSWindow?

    private override init() { super.init() }

    // MARK: – Setup

    public func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        rebuildMenu()
    }

    // MARK: – Icon State

    public func updateIcon() {
        guard let button = statusItem?.button else { return }
        let engine = ApproverEngine.shared

        let name = engine.isEnabled && engine.isAccessibilityGranted
            ? "checkmark.shield.fill"
            : (engine.isEnabled ? "exclamationmark.shield" : "pause.circle")
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "NoInteraction")

        if engine.isEnabled && engine.isAccessibilityGranted {
            button.contentTintColor = NSColor.systemGreen
            button.alphaValue = 1.0
        } else if engine.isEnabled {
            button.contentTintColor = NSColor.systemOrange
            button.alphaValue = 0.8
        } else {
            button.contentTintColor = NSColor.secondaryLabelColor
            button.alphaValue = 0.5
        }

        button.action = #selector(handleClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            statusItem?.menu = makeMenu()
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            showDashboard()
        }
    }

    // MARK: – Menu Building

    public func rebuildMenu() {
        updateIcon()
    }

    private func makeMenu() -> NSMenu {
        let engine = ApproverEngine.shared
        let menu = NSMenu()

        // Status header
        let statusTitle = engine.isEnabled && engine.isAccessibilityGranted
            ? "✅  Active — Monitoring Prompts"
            : (engine.isEnabled ? "⚠️  Needs Accessibility Permission" : "⏸  Paused")
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        let countItem = NSMenuItem(title: "Total Auto-Approved: \(engine.totalApprovalsCount)", action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        menu.addItem(countItem)

        menu.addItem(.separator())

        // Toggle Monitoring
        let toggleTitle = engine.isEnabled ? "Pause Monitoring" : "Resume Monitoring"
        menu.addItem(withTitle: toggleTitle, action: #selector(toggleMonitoring), keyEquivalent: "p").target = self

        // Mute / Unmute Sound
        let soundTitle = engine.soundEnabled ? "Mute Sound Feedback" : "Enable Sound Feedback"
        menu.addItem(withTitle: soundTitle, action: #selector(toggleSound), keyEquivalent: "m").target = self

        // Loop Mode Toggle
        let loopTitle = engine.loopModeEnabled ? "Disable Loop Mode" : "Enable Loop Mode"
        menu.addItem(withTitle: loopTitle, action: #selector(toggleLoopMode), keyEquivalent: "l").target = self

        // Dashboard
        menu.addItem(withTitle: "Open Dashboard…", action: #selector(showDashboard), keyEquivalent: "d").target = self

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NoInteraction", action: #selector(quitApp), keyEquivalent: "q").target = self

        return menu
    }

    // MARK: – Actions

    @objc public func toggleMonitoring() {
        ApproverEngine.shared.isEnabled.toggle()
        updateIcon()
    }

    @objc public func toggleSound() {
        ApproverEngine.shared.soundEnabled.toggle()
    }

    @objc public func toggleLoopMode() {
        ApproverEngine.shared.loopModeEnabled.toggle()
    }

    @objc public func showDashboard() {
        if dashboardWindow == nil {
            let view = DashboardView()
            let vc   = NSHostingController(rootView: view)

            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = "NoInteraction"
            win.subtitle = "Anti-Gravity Auto-Approver"
            win.contentViewController = vc
            win.center()
            win.isReleasedWhenClosed = false
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            dashboardWindow = win
        }
        dashboardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc public func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
