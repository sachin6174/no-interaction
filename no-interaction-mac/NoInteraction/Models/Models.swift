import Foundation

// MARK: - ApprovalRule

public struct ApprovalRule: Codable, Identifiable, Equatable {
    public var id: UUID
    public var keyword: String
    public var isEnabled: Bool
    public var targetType: TargetType

    public enum TargetType: String, Codable, CaseIterable {
        case button   = "Button"
        case checkbox = "Checkbox"
    }

    public init(id: UUID = UUID(), keyword: String, isEnabled: Bool = true, targetType: TargetType) {
        self.id         = id
        self.keyword    = keyword
        self.isEnabled  = isEnabled
        self.targetType = targetType
    }
}

// MARK: - LogEntry

public struct LogEntry: Identifiable, Codable {
    public var id: UUID
    public var timestamp: Date
    public var appName: String
    public var actionTaken: String
    public var targetText: String
    public var detectionMethod: String  // "AXPress", "AX + CGClick", or "Vision OCR"

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .medium
        return f
    }()

    public var formattedTime: String {
        LogEntry.timeFormatter.string(from: timestamp)
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        appName: String,
        actionTaken: String,
        targetText: String,
        detectionMethod: String
    ) {
        self.id              = id
        self.timestamp       = timestamp
        self.appName         = appName
        self.actionTaken     = actionTaken
        self.targetText      = targetText
        self.detectionMethod = detectionMethod
    }
}

// MARK: - Keyword Matcher

// MARK: - Keyword Matcher

public enum KeywordMatcher {
    private static let cacheLock = NSLock()
    private static var regexCache: [String: NSRegularExpression] = [:]

    public static func matches(label: String, keyword: String) -> Bool {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty, !label.isEmpty else { return false }

        // Fast-path: check if label contains the keyword case-insensitively at all
        guard label.localizedCaseInsensitiveContains(kw) else { return false }

        // Fast-path: exact case-insensitive match
        if label.caseInsensitiveCompare(kw) == .orderedSame { return true }

        // Fetch or create cached word-boundary regex
        let regex: NSRegularExpression? = {
            cacheLock.lock()
            defer { cacheLock.unlock() }
            if let cached = regexCache[kw] {
                return cached
            }
            let escaped = NSRegularExpression.escapedPattern(for: kw)
            let pattern = "\\b\(escaped)\\b"
            if let compiled = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                regexCache[kw] = compiled
                return compiled
            }
            return nil
        }()

        guard let validRegex = regex else { return false }
        let range = NSRange(label.startIndex..., in: label)
        return validRegex.firstMatch(in: label, options: [], range: range) != nil
    }

    /// Clears cached compiled regular expressions if rules change
    public static func clearCache() {
        cacheLock.lock()
        regexCache.removeAll()
        cacheLock.unlock()
    }
}

// MARK: - Terminal Session

/// One Terminal.app tab, identified by its tty (stable for the life of the shell session).
public struct TerminalSession: Identifiable, Equatable {
    public var id: String { tty }
    public var windowId: Int
    public var tabIndex: Int
    public var tty: String
    public var isBusy: Bool
    public var lastLine: String
    public var isAttached: Bool
    public var isWaitingForInput: Bool

    public var displayName: String {
        let short = tty.replacingOccurrences(of: "/dev/", with: "")
        return "Window \(windowId) · Tab \(tabIndex) (\(short))"
    }

    public init(
        windowId: Int,
        tabIndex: Int,
        tty: String,
        isBusy: Bool,
        lastLine: String,
        isAttached: Bool = false,
        isWaitingForInput: Bool = false
    ) {
        self.windowId = windowId
        self.tabIndex = tabIndex
        self.tty = tty
        self.isBusy = isBusy
        self.lastLine = lastLine
        self.isAttached = isAttached
        self.isWaitingForInput = isWaitingForInput
    }
}

// MARK: - Terminal Prompt Matcher

/// Detects whether the last visible line of a terminal tab looks like an interactive
/// yes/no or "press enter to continue" prompt that can be safely dismissed with a bare Return.
public enum TerminalPromptMatcher {
    public static let defaultPatterns: [String] = [
        "(y/n)", "[y/n]", "(yes/no)", "[yes/no]",
        "continue?", "proceed?", "overwrite?", "are you sure",
        "press enter", "press return", "press any key"
    ]

    /// Lines containing these fragments are never auto-confirmed, even if they also match a pattern above —
    /// pressing Return would submit an empty value rather than "allow" anything.
    private static let excludedFragments: [String] = ["password", "passphrase"]

    public static func isPrompt(line: String, patterns: [String] = defaultPatterns) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        guard !excludedFragments.contains(where: { lower.contains($0) }) else { return false }
        if lower.hasSuffix("?") { return true }
        return patterns.contains { lower.contains($0) }
    }
}
