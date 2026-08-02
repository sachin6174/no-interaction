import Cocoa

/// Raw data for one Terminal.app tab as read straight off the AppleScript scripting bridge.
public struct TerminalScanResult {
    public let windowId: Int
    public let tabIndex: Int
    public let tty: String
    public let isBusy: Bool
    public let contents: String
}

/// Talks to Terminal.app via AppleScript (Apple Events) instead of the Accessibility API.
/// Terminal.app only fully populates the Accessibility tree for the frontmost tab, but its
/// scripting dictionary exposes `contents`/`busy`/`tty` for every tab in every window regardless
/// of which one is focused, and `do script "" in tab i of window id w` writes a bare newline to
/// that tab's tty — i.e. presses Return — without needing to bring it to the front.
public final class TerminalObserver {
    public static let shared = TerminalObserver()
    private init() {}

    private static let unitSeparator: Character = Character(UnicodeScalar(31))
    private static let recordSeparator: Character = Character(UnicodeScalar(30))

    // NOTE: Terminal's scripting bridge only resolves `tab i of w` into a real value when the
    // reference is used inline for each property access. Storing it once as `set t to tab i of w`
    // and then reading `contents of t` / `busy of t` leaves those reads as unresolved object
    // specifiers, which throws "Can't make «class ttab» ... into type text" (-1700) the moment
    // you try to concatenate or coerce them. Every property below re-references `tab i of w` directly.
    private static let scanScript = """
    tell application "Terminal"
        set outParts to {}
        set sep to (ASCII character 31)
        set winIDs to id of every window
        repeat with wid in winIDs
            set w to window id wid
            set tabCount to count of tabs of w
            repeat with i from 1 to tabCount
                set tTty to (tty of tab i of w) as text
                set tBusy to (busy of tab i of w) as text
                set tContents to (contents of tab i of w) as text
                set rec to (wid as string) & sep & (i as string) & sep & tTty & sep & tBusy & sep & tContents
                set end of outParts to rec
            end repeat
        end repeat
    end tell
    set {tid, AppleScript's text item delimiters} to {AppleScript's text item delimiters, (ASCII character 30)}
    set outputText to outParts as string
    set AppleScript's text item delimiters to tid
    return outputText
    """

    /// Whether Terminal.app is currently running. `tell application "Terminal"` auto-launches the
    /// app if it isn't, which we never want to trigger just by scanning.
    private func isTerminalRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Terminal" }
    }

    /// Synchronous — run off the main thread. Returns one entry per open tab across all windows.
    public func fetchSessions() -> [TerminalScanResult] {
        guard isTerminalRunning() else { return [] }
        guard let script = NSAppleScript(source: Self.scanScript) else { return [] }

        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        if let errorDict {
            let errNum = errorDict["NSAppleScriptErrorNumber"] as? Int ?? 0
            if errNum == -1743 {
                DispatchQueue.main.async {
                    ApproverEngine.shared.isAutomationGranted = false
                }
            }
            print("⚠️ Terminal scan AppleScript error (\(errNum)): \(errorDict)")
            return []
        } else {
            DispatchQueue.main.async {
                if !ApproverEngine.shared.isAutomationGranted {
                    ApproverEngine.shared.isAutomationGranted = true
                }
            }
        }
        guard let output = result.stringValue, !output.isEmpty else { return [] }

        var results: [TerminalScanResult] = []
        let records = output.split(separator: Self.recordSeparator, omittingEmptySubsequences: true)
        for record in records {
            let fields = record.split(separator: Self.unitSeparator, maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count == 5,
                  let windowId = Int(fields[0]),
                  let tabIndex = Int(fields[1]) else { continue }

            results.append(TerminalScanResult(
                windowId: windowId,
                tabIndex: tabIndex,
                tty: String(fields[2]),
                isBusy: fields[3] == "true",
                contents: String(fields[4])
            ))
        }
        return results
    }

    /// Synchronous — run off the main thread. Writes a bare Return keypress into the given tab.
    public func sendReturn(windowId: Int, tabIndex: Int) {
        let script = """
        tell application "Terminal"
            do script "" in tab \(tabIndex) of window id \(windowId)
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else { return }
        var errorDict: NSDictionary?
        appleScript.executeAndReturnError(&errorDict)
        if let errorDict {
            print("⚠️ Terminal sendReturn AppleScript error: \(errorDict)")
        }
    }
}
