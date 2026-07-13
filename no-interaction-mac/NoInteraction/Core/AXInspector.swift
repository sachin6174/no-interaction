import Cocoa
import ApplicationServices

public final class AXInspector {
    public static let shared = AXInspector()
    private init() {}

    private static let enabledPidsLock = NSLock()
    private static var enabledPids = Set<pid_t>()

    public struct InspectionResult {
        public let action: String
        public let elementText: String
        public let position: CGPoint?
    }

    // MARK: – Public Entry Point

    public func inspectAndAutoApprove(
        pid: pid_t,
        buttonKeywords: [String],
        checkboxKeywords: [String]
    ) -> InspectionResult? {
        let axApp = AXUIElementCreateApplication(pid)

        let isAlreadyEnabled: Bool = {
            AXInspector.enabledPidsLock.lock()
            defer { AXInspector.enabledPidsLock.unlock() }
            return AXInspector.enabledPids.contains(pid)
        }()

        if !isAlreadyEnabled {
            // Force Electron / Chromium to enable native accessibility trees
            AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            AXInspector.enabledPidsLock.lock()
            AXInspector.enabledPids.insert(pid)
            AXInspector.enabledPidsLock.unlock()
            print("👁️ AXInspector: Enabled AXEnhancedUserInterface and AXManualAccessibility for pid \(pid)")
        }

        var windowsRef: CFTypeRef?
        var windows: [AXUIElement] = []

        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let list = windowsRef as? [AXUIElement], !list.isEmpty {
            windows = list
        } else {
            windows = [axApp]
        }

        // Filter windows if target app is a browser
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }),
           AppObserver.shared.isBrowser(app) {
            windows = windows.filter { AppObserver.shared.isAntigravityWindow($0) }
        }

        // Pass 1: Auto-tick matching checkboxes across windows
        if !checkboxKeywords.isEmpty {
            for win in windows {
                tickCheckboxes(in: win, depth: 0, keywords: checkboxKeywords)
            }
        }

        // Pass 2: Find & click the first matching approval button
        for win in windows {
            let hasSelection = isAnyRadioButtonSelected(in: win, depth: 0, keywords: buttonKeywords + checkboxKeywords)
            if let result = findAndPressButton(in: win, depth: 0, keywords: buttonKeywords, hasSelection: hasSelection) {
                return result
            }
        }
        return nil
    }

    // MARK: – Pass 1: Checkbox Ticking

    private func tickCheckboxes(
        in element: AXUIElement,
        depth: Int,
        keywords: [String],
        isInWebArea: Bool = false,
        isIgnoredContainer: Bool = false
    ) {
        guard depth <= 25 else { return }

        let role = stringAttr(element, kAXRoleAttribute as CFString)
        let inWeb = isInWebArea || role == "AXWebArea" || role == "AXRootWebArea"
        
        let shouldIgnore = isIgnoredContainer || (!inWeb && isIgnoredRoleOrMetadata(role: role, element: element))
        if shouldIgnore { return }

        if role == "AXCheckBox" || role == "AXRadioButton" {
            let label = buttonLabel(element)
            if keywords.contains(where: { KeywordMatcher.matches(label: label, keyword: $0) }) {
                var val: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &val)
                let isChecked = (val as? NSNumber)?.boolValue ?? false
                if !isChecked {
                    AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, kCFBooleanTrue)
                    AXUIElementPerformAction(element, kAXPressAction as CFString)
                    print("✅ AXInspector: Ticked checkbox/radio '\(label)'")
                }
            }
        }

        for child in childElements(element) {
            tickCheckboxes(in: child, depth: depth + 1, keywords: keywords, isInWebArea: inWeb, isIgnoredContainer: shouldIgnore)
        }
    }

    // MARK: – Pass 2: Button Pressing

    private func findAndPressButton(
        in element: AXUIElement,
        depth: Int,
        keywords: [String],
        hasSelection: Bool,
        isInWebArea: Bool = false,
        isIgnoredContainer: Bool = false
    ) -> InspectionResult? {
        guard depth <= 25 else { return nil }

        let role = stringAttr(element, kAXRoleAttribute as CFString)
        let inWeb = isInWebArea || role == "AXWebArea" || role == "AXRootWebArea"
        
        let shouldIgnore = isIgnoredContainer || (!inWeb && isIgnoredRoleOrMetadata(role: role, element: element))
        if shouldIgnore { return nil }

        // Button roles in native macOS and Electron web views
        if role == "AXButton" || role == "AXPopUpButton" || role == "AXRadioButton" {
            // Skip unselected radio buttons if an option is already selected
            if role == "AXRadioButton" && hasSelection {
                return nil
            }
            
            let label = buttonLabel(element)
            let isMatch = !label.isEmpty && keywords.contains { KeywordMatcher.matches(label: label, keyword: $0) }

            if isMatch {
                // Primary action: AXPress (Native accessibility action — 100% silent, 0% cursor movement)
                let pressResult = AXUIElementPerformAction(element, kAXPressAction as CFString)
                let center = centerOf(element)
                let display = label.isEmpty ? "Approval Button" : label

                if pressResult == .success {
                    print("🚀 AXInspector: AXPress succeeded on '\(display)' (role=\(role), depth=\(depth))")
                    return InspectionResult(action: "AXPress", elementText: display, position: center)
                } else if let pt = center {
                    // Secondary action: AXClick fallback
                    let clickResult = AXUIElementPerformAction(element, "AXClick" as CFString)
                    if clickResult == .success {
                        print("🚀 AXInspector: AXClick succeeded on '\(display)'")
                        return InspectionResult(action: "AXClick", elementText: display, position: center)
                    }

                    print("⚠️ AXInspector: AXPress/AXClick failed for '\(display)', requesting CGClick fallback at \(pt)")
                    return InspectionResult(action: "Fallback CGEvent Click Needed", elementText: display, position: pt)
                }
            }
        }

        for child in childElements(element) {
            if let r = findAndPressButton(
                in: child,
                depth: depth + 1,
                keywords: keywords,
                hasSelection: hasSelection,
                isInWebArea: inWeb,
                isIgnoredContainer: shouldIgnore
            ) {
                return r
            }
        }
        return nil
    }

    private func isAnyRadioButtonSelected(
        in element: AXUIElement,
        depth: Int,
        keywords: [String],
        isInWebArea: Bool = false,
        isIgnoredContainer: Bool = false
    ) -> Bool {
        guard depth <= 25 else { return false }
        
        let role = stringAttr(element, kAXRoleAttribute as CFString)
        let inWeb = isInWebArea || role == "AXWebArea" || role == "AXRootWebArea"
        let shouldIgnore = isIgnoredContainer || (!inWeb && isIgnoredRoleOrMetadata(role: role, element: element))
        if shouldIgnore { return false }

        if role == "AXRadioButton" || role == "AXCheckBox" {
            let label = buttonLabel(element)
            let isMatch = !label.isEmpty && keywords.contains { KeywordMatcher.matches(label: label, keyword: $0) }
            if isMatch {
                var val: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &val)
                let isSelected = (val as? NSNumber)?.boolValue ?? ((val as? Bool) ?? false)
                if isSelected {
                    return true
                }
            }
        }
        
        for child in childElements(element) {
            if isAnyRadioButtonSelected(in: child, depth: depth + 1, keywords: keywords, isInWebArea: inWeb, isIgnoredContainer: shouldIgnore) {
                return true
            }
        }
        
        return false
    }

    // MARK: – Helpers

    private func isIgnoredRoleOrMetadata(role: String, element: AXUIElement) -> Bool {
        if role == "AXOutline" || role == "AXTable" || role == "AXTabGroup" {
            return true
        }
        let desc = stringAttr(element, kAXDescriptionAttribute as CFString).lowercased()
        if desc.contains("sidebar") || desc.contains("explorer") || desc.contains("outline") || desc.contains("navigation") || desc.contains("tab bar") {
            return true
        }
        let title = stringAttr(element, kAXTitleAttribute as CFString).lowercased()
        if title.contains("sidebar") || title.contains("explorer") || title.contains("outline") || title.contains("navigation") || title.contains("tab bar") {
            return true
        }
        return false
    }

    private func stringAttr(_ el: AXUIElement, _ attr: CFString) -> String {
        var ref: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr, &ref) == .success ? (ref as? String) ?? "" : ""
    }

    private func directLabel(_ el: AXUIElement) -> String {
        let title = stringAttr(el, kAXTitleAttribute as CFString)
        let desc  = stringAttr(el, kAXDescriptionAttribute as CFString)
        let label = stringAttr(el, kAXLabelValueAttribute as CFString)
        let value = stringAttr(el, kAXValueAttribute as CFString)
        return [title, desc, label, value]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Reads direct label + searches child text nodes (Crucial for Electron webview buttons!)
    private func buttonLabel(_ el: AXUIElement) -> String {
        var text = directLabel(el)
        if text.isEmpty {
            for child in childElements(el) {
                let childRole = stringAttr(child, kAXRoleAttribute as CFString)
                if childRole == "AXStaticText" || childRole == "AXHeading" || childRole == "" {
                    let childText = directLabel(child)
                    if !childText.isEmpty {
                        text += (text.isEmpty ? "" : " ") + childText
                    }
                }
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func childElements(_ el: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref) == .success,
              let list = ref as? [AXUIElement] else { return [] }
        return list
    }

    public func centerOf(_ el: AXUIElement) -> CGPoint? {
        var posRef: CFTypeRef?; var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef)
        guard let pv = posRef, CFGetTypeID(pv) == AXValueGetTypeID(),
              let sv = sizeRef, CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var pt = CGPoint.zero; var sz = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &pt)
        AXValueGetValue(sv as! AXValue, .cgSize,  &sz)
        guard sz.width > 0, sz.height > 0 else { return nil }
        return CGPoint(x: pt.x + sz.width / 2, y: pt.y + sz.height / 2)
    }

    public struct ChatStateResult {
        public let inputArea: AXUIElement?
        public let isBusy: Bool
    }

    public func findChatInputAndStatus(in element: AXUIElement, depth: Int) -> ChatStateResult {
        var inputArea: AXUIElement? = nil
        var isBusy = false
        
        func traverse(_ el: AXUIElement, currentDepth: Int) {
            guard currentDepth <= 30 else { return }
            
            let role = stringAttr(el, kAXRoleAttribute as CFString)
            let title = stringAttr(el, kAXTitleAttribute as CFString).lowercased()
            let desc = stringAttr(el, kAXDescriptionAttribute as CFString).lowercased()
            
            var placeholderValue: CFTypeRef?
            let placeholder: String
            if AXUIElementCopyAttributeValue(el, "AXPlaceholderValue" as CFString, &placeholderValue) == .success,
               let pStr = placeholderValue as? String {
                placeholder = pStr.lowercased()
            } else {
                placeholder = ""
            }
            
            // Check for Stop button
            if role == "AXButton" {
                let label = buttonLabel(el).lowercased()
                let isStopButton = label == "stop" || label == "cancel" || label.contains("stop generating") || label.contains("interrupt") || label.contains("■") || label.contains("⏹") || label.contains("square.fill") || label.contains("stop.fill")
                let isStopDesc = desc.contains("stop") || desc.contains("cancel") || desc.contains("interrupt") || desc.contains("square.fill") || desc.contains("stop.fill")
                let isStopTitle = title.contains("stop") || title.contains("cancel") || title.contains("interrupt") || title.contains("square.fill") || title.contains("stop.fill")
                
                if isStopButton || isStopDesc || isStopTitle {
                    isBusy = true
                }
            }
            
            // Check for Text Area
            if role == "AXTextArea" || role == "AXTextField" {
                let isChatInput = title.contains("message") || title.contains("ask") || title.contains("prompt") ||
                                  desc.contains("message") || desc.contains("ask") || desc.contains("prompt") ||
                                  placeholder.contains("message") || placeholder.contains("ask") || placeholder.contains("prompt") ||
                                  placeholder.contains("type a") || placeholder.contains("ask a") || placeholder.contains("chat")
                
                if isChatInput {
                    inputArea = el
                }
            }
            
            for child in childElements(el) {
                traverse(child, currentDepth: currentDepth + 1)
            }
        }
        
        traverse(element, currentDepth: 0)
        return ChatStateResult(inputArea: inputArea, isBusy: isBusy)
    }

    public func pressReturnKey() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let up   = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        down?.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        up?.post(tap: .cgSessionEventTap)
    }

    public func pressPasteKeystroke() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vCode: CGKeyCode = 0x09 // 'v' key code
        let down = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        up?.post(tap: .cgSessionEventTap)
    }
}
