import Cocoa

public final class AppObserver {
    public static let shared = AppObserver()

    /// Process names to monitor — matches by substring (case-insensitive)
    /// "Antigravity" covers "Antigravity IDE", "Antigravity IDE Helper (Plugin)", etc.
    public var targetAppNames: [String] = [
        "Antigravity",
        "Anti-Gravity",
        "AntiGravity",
        "Visual Studio Code",
        "VS Code",
        "VSCode"
    ]

    private init() {}

    /// Checks if a running application is a browser or VS Code
    public func isBrowserOrEditor(_ app: NSRunningApplication) -> Bool {
        return isBrowser(app) || isEditor(app)
    }

    /// Checks if a running application is a code editor (VS Code, Cursor, Windsurf, etc.)
    public func isEditor(_ app: NSRunningApplication) -> Bool {
        guard let name = app.localizedName?.lowercased() else { return false }
        let editors = ["visual studio code", "vs code", "vscode", "cursor", "windsurf", "antigravity"]
        return editors.contains { name.contains($0) }
    }

    /// Checks if a running application is a web browser
    public func isBrowser(_ app: NSRunningApplication) -> Bool {
        guard let bundleId = app.bundleIdentifier?.lowercased() ?? app.localizedName?.lowercased() else { return false }
        let knownBrowsers = [
            "com.google.chrome", "chrome",
            "com.apple.safari", "safari",
            "company.thebrowser.browser", "arc",
            "com.microsoft.edgemac", "edge",
            "com.brave.browser", "brave",
            "org.mozilla.firefox", "firefox",
            "com.kagi.kagimacos", "orion",
            "com.operasoftware.opera", "opera",
            "com.vivaldi.vivaldi", "vivaldi"
        ]
        return knownBrowsers.contains { bundleId.contains($0) }
    }

    /// Checks if a window's title contains any of the Antigravity keywords
    public func isAntigravityWindow(_ element: AXUIElement) -> Bool {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String else {
            return false
        }
        let lower = title.lowercased()
        let keywords = ["antigravity", "anti-gravity", "agy", "gemini", "no-interaction"]
        return keywords.contains { lower.contains($0) }
    }

    /// Returns all running applications whose localizedName contains any target name.
    public func findTargetApplications(customTargets: [String] = []) -> [NSRunningApplication] {
        let allTargets = (targetAppNames + customTargets).filter { !$0.isEmpty }
        return NSWorkspace.shared.runningApplications.filter { app in
            guard let name = app.localizedName else { return false }
            return allTargets.contains { name.localizedCaseInsensitiveContains($0) }
        }
    }

    /// Returns the on-screen bounding rect of the frontmost / largest window for an app.
    public func getWindowBounds(for app: NSRunningApplication) -> CGRect? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        // Prefer full window list so floating dialogs/panels are included
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            
            // If it's a browser, filter windows to only Antigravity windows
            let filteredWindows: [AXUIElement]
            if isBrowser(app) {
                let matched = windows.filter { isAntigravityWindow($0) }
                filteredWindows = matched.isEmpty ? windows : matched
            } else {
                filteredWindows = windows
            }
            
            // Return the largest window (most likely the main UI)
            return filteredWindows.compactMap { rectFor(element: $0) }
                                  .max(by: { $0.width * $0.height < $1.width * $1.height })
        }

        // Fallback: focused window
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let win = focusedRef {
            let winElement = win as! AXUIElement
            if isBrowser(app) && !isAntigravityWindow(winElement) {
                return nil
            }
            return rectFor(element: winElement)
        }
        return nil
    }

    private func rectFor(element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)

        guard let pv = posRef, CFGetTypeID(pv) == AXValueGetTypeID(),
              let sv = sizeRef, CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }

        var point = CGPoint.zero
        var size  = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &point)
        AXValueGetValue(sv as! AXValue, .cgSize,  &size)

        guard size.width > 50 && size.height > 50 else { return nil }
        return CGRect(origin: point, size: size)
    }
}
