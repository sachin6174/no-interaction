import Cocoa
import Combine

@MainActor
public final class ApproverEngine: ObservableObject {
    public static let shared = ApproverEngine()

    // MARK: - Published State

    @Published public var isEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }
    @Published public var isAccessibilityGranted: Bool = false
    @Published public var totalApprovalsCount: Int = 0 {
        didSet { UserDefaults.standard.set(totalApprovalsCount, forKey: "totalApprovalsCount") }
    }
    @Published public var soundEnabled: Bool = true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published public var logs: [LogEntry] = []

    @Published public var buttonRules: [ApprovalRule] = [] {
        didSet { saveRules() }
    }

    @Published public var checkboxRules: [ApprovalRule] = [] {
        didSet { saveRules() }
    }

    @Published public var promptQueue: [String] = [] {
        didSet { savePromptQueue() }
    }
    @Published public var currentPromptIndex: Int = 0 {
        didSet { UserDefaults.standard.set(currentPromptIndex, forKey: "currentPromptIndex") }
    }
    @Published public var isPromptQueueActive: Bool = false {
        didSet { UserDefaults.standard.set(isPromptQueueActive, forKey: "isPromptQueueActive") }
    }
    @Published public var loopModeEnabled: Bool = false {
        didSet { UserDefaults.standard.set(loopModeEnabled, forKey: "loopModeEnabled") }
    }
    @Published public var loopModeLimit: Int = 10 {
        didSet { UserDefaults.standard.set(loopModeLimit, forKey: "loopModeLimit") }
    }
    @Published public var loopModeCounter: Int = 0 {
        didSet { UserDefaults.standard.set(loopModeCounter, forKey: "loopModeCounter") }
    }

    // MARK: - Private State

    private var timer: Timer?
    private var lastActionTime: Date = .distantPast
    private let cooldown: TimeInterval = 1.2
    private var visionScanInFlight = false

    // Default Fallback Rules
    private static let defaultButtons = [
        "Submit", "Yes, allow this time", "Yes, allow", "Allow running this command",
        "Allow", "Yes, and always", "Approve", "Yes", "Confirm", "Proceed",
        "Accept", "Continue", "OK"
    ]
    private static let defaultCheckboxes = [
        "Remember", "Always", "Trust", "Don't ask", "Don't show"
    ]

    public static let defaultPrompt = """
Perform a complete, exhaustive, and uncompromising security, architecture, performance, and UI/UX audit of this entire codebase. Analyze every single line of code with extreme depth and rigor.

Your objective is to optimize this application to the absolute highest tier of software quality in existence. Follow these strict directives:
1. BUG DETECTION & RESOLUTION: Scan for any logical bugs, concurrency race conditions, memory leaks, performance bottlenecks, edge-case crashes, and API misuses. Resolve them immediately with clean, production-ready, and robust code.
2. CODE OPTIMIZATION & REFACTORING: Optimize compile times, memory footprints, and CPU utilization. Eliminate redundant loops, redundant accessibility calls, and heavy UI renderings. Ensure optimal Swift concurrency paradigms.
3. UI/UX REFINEMENT: Review all layouts, fonts, spacing, color contrasts, transitions, and hover animations. Upgrade the visual design system to feel premium, modern, and state-of-the-art.
4. EDGE CASES & ROBUSTNESS: Ensure perfect error handling, validation, and defensive coding against unexpected window hierarchies, missing permissions, or browser states.
5. DEEP SEARCH: Use the internet, latest documentation, Apple SDK guidelines, and the full extent of your cognitive capacity. Do not stop until this codebase is completely flawless.
"""

    private init() {
        loadSettingsAndRules()
        refreshAccessibilityStatus()
        startTimer()
        setupWorkspaceNotifications()
    }

    // MARK: - Persistence

    private func loadSettingsAndRules() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "isEnabled") != nil {
            self.isEnabled = defaults.bool(forKey: "isEnabled")
        }
        self.totalApprovalsCount = defaults.integer(forKey: "totalApprovalsCount")
        if defaults.object(forKey: "soundEnabled") != nil {
            self.soundEnabled = defaults.bool(forKey: "soundEnabled")
        } else {
            self.soundEnabled = true
        }

        // Load Rules
        if let data = defaults.data(forKey: "buttonRules"),
           let decoded = try? JSONDecoder().decode([ApprovalRule].self, from: data) {
            self.buttonRules = decoded
        } else {
            self.buttonRules = ApproverEngine.defaultButtons.map {
                ApprovalRule(keyword: $0, targetType: .button)
            }
        }
        // Sanitize rules: remove Run and Execute to prevent conflict with IDE "Run Code" buttons
        self.buttonRules.removeAll { $0.keyword.caseInsensitiveCompare("Run") == .orderedSame || $0.keyword.caseInsensitiveCompare("Execute") == .orderedSame }

        if let data = defaults.data(forKey: "checkboxRules"),
           let decoded = try? JSONDecoder().decode([ApprovalRule].self, from: data) {
            self.checkboxRules = decoded
        } else {
            self.checkboxRules = ApproverEngine.defaultCheckboxes.map {
                ApprovalRule(keyword: $0, targetType: .checkbox)
            }
        }

        if let pq = defaults.stringArray(forKey: "promptQueue"), !pq.isEmpty {
            self.promptQueue = pq
        } else {
            self.promptQueue = [ApproverEngine.defaultPrompt]
            self.isPromptQueueActive = true
        }
        self.currentPromptIndex = defaults.integer(forKey: "currentPromptIndex")
        self.isPromptQueueActive = defaults.object(forKey: "isPromptQueueActive") != nil ? defaults.bool(forKey: "isPromptQueueActive") : true
        self.loopModeEnabled = defaults.bool(forKey: "loopModeEnabled")
        self.loopModeLimit = defaults.object(forKey: "loopModeLimit") != nil ? defaults.integer(forKey: "loopModeLimit") : 10
        self.loopModeCounter = defaults.integer(forKey: "loopModeCounter")
    }

    private func saveRules() {
        if let bData = try? JSONEncoder().encode(buttonRules) {
            UserDefaults.standard.set(bData, forKey: "buttonRules")
        }
        if let cData = try? JSONEncoder().encode(checkboxRules) {
            UserDefaults.standard.set(cData, forKey: "checkboxRules")
        }
    }

    private func savePromptQueue() {
        UserDefaults.standard.set(promptQueue, forKey: "promptQueue")
    }

    // MARK: - Accessibility

    public func refreshAccessibilityStatus() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let granted = AXIsProcessTrustedWithOptions(options)
        if granted != self.isAccessibilityGranted {
            self.isAccessibilityGranted = granted
        }
    }

    public func promptAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            Task { @MainActor in
                self?.refreshAccessibilityStatus()
            }
        }
    }

    // MARK: - Scan Loop

    public func startTimer() {
        timer?.invalidate()
        // Run checks every 1.5 seconds for improved responsiveness, scaling up when app is active
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleScan()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func setupWorkspaceNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceNotification),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func handleWorkspaceNotification(_ notification: Notification) {
        // Immediate scan on app switch
        scheduleScan()
    }

    private func scheduleScan() {
        refreshAccessibilityStatus()
        guard isEnabled, isAccessibilityGranted else { return }
        guard Date().timeIntervalSince(lastActionTime) >= cooldown else { return }

        let buttons    = buttonRules.filter(\.isEnabled).map(\.keyword)
        let checkboxes = checkboxRules.filter(\.isEnabled).map(\.keyword)
        guard !buttons.isEmpty else { return }

        let targetApps = AppObserver.shared.findTargetApplications()
        guard !targetApps.isEmpty else { return }

        print("🔄 scheduleScan running. Target apps found: \(targetApps.map { $0.localizedName ?? "" })")

        // Perform scan sequentially for each target application
        for app in targetApps {
            let pid = app.processIdentifier
            let appName = app.localizedName ?? "Anti-Gravity"

            Task {
                // Pass 1: AXPress / AXClick (runs tree traversal in detached background task)
                let result = await Task.detached(priority: .userInitiated) {
                    return AXInspector.shared.inspectAndAutoApprove(
                        pid: pid,
                        buttonKeywords: buttons,
                        checkboxKeywords: checkboxes
                    )
                }.value

                if let result = result {
                    self.lastActionTime = Date()
                    if result.action == "Fallback CGEvent Click Needed", let pt = result.position {
                        ClickAutomation.shared.performClick(at: pt, targetPid: pid) {
                            Task { @MainActor in
                                self.record(appName: appName, text: result.elementText, method: "AX + CGClick")
                            }
                        }
                    } else {
                        self.record(appName: appName, text: result.elementText, method: result.action)
                    }
                    return
                }

                // Pass 2: Vision OCR (Fallback if AX is blocked or missed)
                if !self.visionScanInFlight, let bounds = AppObserver.shared.getWindowBounds(for: app) {
                    self.visionScanInFlight = true
                    let capturedPid = pid

                    let ocrResult = await withCheckedContinuation { (continuation: CheckedContinuation<(CGPoint?, String?), Never>) in
                        VisionOCRScanner.shared.scanRegionForKeywords(
                            windowBounds: bounds,
                            buttonKeywords: buttons
                        ) { point, text in
                            continuation.resume(returning: (point, text))
                        }
                    }
                    
                    self.visionScanInFlight = false
                    if let pt = ocrResult.0, let text = ocrResult.1 {
                        if Date().timeIntervalSince(self.lastActionTime) >= self.cooldown {
                            self.lastActionTime = Date()
                            ClickAutomation.shared.performClick(at: pt, targetPid: capturedPid) {
                                Task { @MainActor in
                                    self.record(appName: appName, text: text, method: "Vision OCR")
                                }
                            }
                        }
                        return
                    }
                }

                // Pass 3: Prompt Queue Check or Loop Mode Check (ONLY if no approval buttons were found)
                let shouldCheckPromptState = (self.isPromptQueueActive && self.currentPromptIndex < self.promptQueue.count) ||
                                             (self.loopModeEnabled && (self.loopModeLimit == 0 || self.loopModeCounter < self.loopModeLimit))

                if shouldCheckPromptState {
                    let chatState = await Task.detached(priority: .userInitiated) { () -> AXInspector.ChatStateResult in
                        let axApp = AXUIElementCreateApplication(pid)
                        var windowsRef: CFTypeRef?
                        var isBusy = false
                        var inputArea: AXUIElement? = nil
                        
                        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                           let windows = windowsRef as? [AXUIElement] {
                            let filteredWindows = AppObserver.shared.isBrowser(app)
                                ? windows.filter { AppObserver.shared.isAntigravityWindow($0) }
                                : windows
                            
                            for win in filteredWindows {
                                let state = AXInspector.shared.findChatInputAndStatus(in: win, depth: 0)
                                if state.isBusy {
                                    isBusy = true
                                }
                                if let input = state.inputArea {
                                    inputArea = input
                                }
                            }
                        }
                        return AXInspector.ChatStateResult(inputArea: inputArea, isBusy: isBusy)
                    }.value

                    if !chatState.isBusy, let input = chatState.inputArea {
                        let prompt = self.loopModeEnabled ? ApproverEngine.defaultPrompt : self.promptQueue[self.currentPromptIndex]
                        await self.pastePrompt(prompt: prompt, toInput: input, forApp: app)
                        return
                    }
                }
            }
        }
    }

    private func pastePrompt(prompt: String, toInput input: AXUIElement, forApp app: NSRunningApplication) async {
        if self.loopModeEnabled {
            self.loopModeCounter += 1
            print("🤖 Loop Mode: Pasting prompt \(self.loopModeCounter)/\(self.loopModeLimit == 0 ? "∞" : String(self.loopModeLimit))")
        } else {
            self.currentPromptIndex += 1
            print("🤖 Prompt Queue: Pasting prompt \(self.currentPromptIndex)/\(self.promptQueue.count)")
        }
        self.lastActionTime = Date()

        app.activate(options: .activateIgnoringOtherApps)
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        if let center = AXInspector.shared.centerOf(input) {
            print("🎯 Clicking center of chat input area at: \(center) for app: \(app.localizedName ?? "")")
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                ClickAutomation.shared.performClick(at: center, targetPid: app.processIdentifier) {
                    continuation.resume()
                }
            }

            try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
            try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s

            print("📋 Pasting prompt...")
            AXInspector.shared.pressPasteKeystroke()
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s

            print("⌨️ Pressing Return key...")
            AXInspector.shared.pressReturnKey()
        }
    }

    // MARK: - Logging & Audio Feedback

    /// Entry point for other engines (e.g. `TerminalApproverEngine`) to share the same
    /// Activity Log and sound feedback instead of keeping a separate log per source.
    public func recordExternal(appName: String, text: String, method: String) {
        record(appName: appName, text: text, method: method)
    }

    private func record(appName: String, text: String, method: String) {
        self.totalApprovalsCount += 1
        let entry = LogEntry(
            appName: appName,
            actionTaken: "Auto-Approved",
            targetText: text,
            detectionMethod: method
        )
        self.logs.insert(entry, at: 0)
        if self.logs.count > 200 { self.logs = Array(self.logs.prefix(200)) }
        MenuBarManager.shared.rebuildMenu()

        if self.soundEnabled {
            NSSound(named: "Tink")?.play()
        }
    }

    // MARK: - Rule Management

    public func addRule(keyword: String, targetType: ApprovalRule.TargetType) {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return }
        let rule = ApprovalRule(keyword: kw, targetType: targetType)
        if targetType == .button {
            guard !buttonRules.contains(where: { $0.keyword.caseInsensitiveCompare(kw) == .orderedSame }) else { return }
            buttonRules.append(rule)
        } else {
            guard !checkboxRules.contains(where: { $0.keyword.caseInsensitiveCompare(kw) == .orderedSame }) else { return }
            checkboxRules.append(rule)
        }
    }

    public func removeRule(id: UUID, targetType: ApprovalRule.TargetType) {
        if targetType == .button {
            buttonRules.removeAll { $0.id == id }
        } else {
            checkboxRules.removeAll { $0.id == id }
        }
    }

    public func toggleRule(id: UUID, targetType: ApprovalRule.TargetType) {
        if targetType == .button {
            if let idx = buttonRules.firstIndex(where: { $0.id == id }) {
                buttonRules[idx].isEnabled.toggle()
            }
        } else {
            if let idx = checkboxRules.firstIndex(where: { $0.id == id }) {
                checkboxRules[idx].isEnabled.toggle()
            }
        }
    }

    public func resetRulesToDefault() {
        buttonRules = ApproverEngine.defaultButtons.map { ApprovalRule(keyword: $0, targetType: .button) }
        checkboxRules = ApproverEngine.defaultCheckboxes.map { ApprovalRule(keyword: $0, targetType: .checkbox) }
    }

    public func resetPromptQueueToDefault() {
        promptQueue = [ApproverEngine.defaultPrompt]
        currentPromptIndex = 0
        isPromptQueueActive = true
    }
}
