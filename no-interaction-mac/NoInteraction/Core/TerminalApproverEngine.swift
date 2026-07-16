import Cocoa
import Combine

/// Mirrors `ApproverEngine`'s scan-loop shape but for Terminal.app tabs instead of AX-tree GUI apps.
/// Unlike the GUI approver, sessions are opt-in one at a time via `setAttached` — auto-pressing
/// Return in a shell you're actively typing in, or in every tab indiscriminately, is unsafe.
@MainActor
public final class TerminalApproverEngine: ObservableObject {
    public static let shared = TerminalApproverEngine()

    @Published public var isMonitoringEnabled: Bool = false {
        didSet { UserDefaults.standard.set(isMonitoringEnabled, forKey: "terminalMonitoringEnabled") }
    }
    @Published public var sessions: [TerminalSession] = []

    private var attachedTTYs: Set<String> = []
    /// tty -> candidate prompt line seen on the previous scan; a line must be stable across two
    /// consecutive scans before we act on it, so we don't fire on a transient "?" mid-scroll.
    private var pendingLine: [String: String] = [:]
    /// tty -> prompt line already responded to, so an unchanged prompt isn't re-confirmed every scan.
    private var respondedLine: [String: String] = [:]

    private var timer: Timer?
    private var scanInFlight = false

    private init() {
        isMonitoringEnabled = UserDefaults.standard.bool(forKey: "terminalMonitoringEnabled")
        startTimer()
    }

    public func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    public func setAttached(_ attached: Bool, tty: String) {
        if attached {
            attachedTTYs.insert(tty)
        } else {
            attachedTTYs.remove(tty)
            pendingLine[tty] = nil
            respondedLine[tty] = nil
        }
        if let idx = sessions.firstIndex(where: { $0.tty == tty }) {
            sessions[idx].isAttached = attached
        }
    }

    private func scan() {
        guard isMonitoringEnabled, !scanInFlight else { return }
        scanInFlight = true
        Task {
            let results = await Task.detached(priority: .utility) {
                TerminalObserver.shared.fetchSessions()
            }.value
            self.applyResults(results)
            self.scanInFlight = false
        }
    }

    private func applyResults(_ results: [TerminalScanResult]) {
        let liveTTYs = Set(results.map(\.tty))
        attachedTTYs.formIntersection(liveTTYs)
        pendingLine = pendingLine.filter { liveTTYs.contains($0.key) }
        respondedLine = respondedLine.filter { liveTTYs.contains($0.key) }

        var updated: [TerminalSession] = []
        for result in results {
            let line = lastNonEmptyLine(in: result.contents)
            let isAttached = attachedTTYs.contains(result.tty)
            var isWaiting = false

            if isAttached, TerminalPromptMatcher.isPrompt(line: line) {
                if respondedLine[result.tty] == line {
                    isWaiting = true // already dismissed; program hasn't cleared the prompt text yet
                } else if pendingLine[result.tty] == line {
                    fireReturn(windowId: result.windowId, tabIndex: result.tabIndex, tty: result.tty, line: line)
                    respondedLine[result.tty] = line
                    pendingLine[result.tty] = nil
                } else {
                    pendingLine[result.tty] = line
                    isWaiting = true
                }
            } else {
                pendingLine[result.tty] = nil
                if respondedLine[result.tty] != line {
                    respondedLine[result.tty] = nil
                }
            }

            updated.append(TerminalSession(
                windowId: result.windowId,
                tabIndex: result.tabIndex,
                tty: result.tty,
                isBusy: result.isBusy,
                lastLine: line,
                isAttached: isAttached,
                isWaitingForInput: isWaiting
            ))
        }

        sessions = updated.sorted { lhs, rhs in
            if lhs.windowId != rhs.windowId { return lhs.windowId < rhs.windowId }
            return lhs.tabIndex < rhs.tabIndex
        }
    }

    private func fireReturn(windowId: Int, tabIndex: Int, tty: String, line: String) {
        Task.detached(priority: .userInitiated) {
            TerminalObserver.shared.sendReturn(windowId: windowId, tabIndex: tabIndex)
        }
        let shortTty = tty.replacingOccurrences(of: "/dev/", with: "")
        ApproverEngine.shared.recordExternal(appName: "Terminal (\(shortTty))", text: line, method: "Terminal AppleScript")
    }

    private func lastNonEmptyLine(in contents: String) -> String {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }
}
