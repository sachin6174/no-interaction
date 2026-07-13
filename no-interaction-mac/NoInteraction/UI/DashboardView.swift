import SwiftUI
import AppKit

enum DashboardTab: Int, Hashable {
    case activityLog = 0
    case rules = 1
    case promptQueue = 2
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var newButtonKeyword: String   = ""
    @Published var newCheckboxKeyword: String = ""
    @Published var newPromptText: String      = ""
    @Published var selectedTab: DashboardTab  = .activityLog
    @Published var logSearchQuery: String     = ""
}

struct DashboardView: View {
    @ObservedObject var engine = ApproverEngine.shared
    @StateObject private var vm = DashboardViewModel()
    @State private var isMonitoringHovered = false
    @State private var isSoundHovered = false

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────────────────
            HStack(spacing: 16) {
                // Status Shield Indicator
                ZStack {
                    Circle()
                        .fill(engine.isEnabled && engine.isAccessibilityGranted
                              ? Color.green.opacity(0.15)
                              : engine.isEnabled ? Color.orange.opacity(0.15) : Color.gray.opacity(0.15))
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: engine.isEnabled && engine.isAccessibilityGranted
                          ? "shield.checkered" : engine.isEnabled
                          ? "exclamationmark.shield.fill" : "shield.slash.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(engine.isEnabled && engine.isAccessibilityGranted ? .green
                                         : engine.isEnabled ? .orange : .secondary)
                }
                .scaleEffect(isMonitoringHovered ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isMonitoringHovered)
                .onHover { hovering in isMonitoringHovered = hovering }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("NoInteraction")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("v1.2")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .foregroundColor(.secondary)
                    }
                    Text(engine.isEnabled && engine.isAccessibilityGranted
                         ? "Active & Monitoring Anti-Gravity Prompts"
                         : engine.isEnabled ? "Accessibility Permission Required" : "Monitoring Paused")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Approval Count Badge
                if engine.totalApprovalsCount > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("\(engine.totalApprovalsCount) Approved")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(LinearGradient(colors: [Color.green.opacity(0.18), Color.emerald.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .foregroundColor(.green)
                    .transition(.scale.combined(with: .opacity))
                }

                // Sound Toggle Button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        engine.soundEnabled.toggle()
                    }
                } label: {
                    Image(systemName: engine.soundEnabled ? "speaker.wave.2.bubble.fill" : "speaker.slash.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(engine.soundEnabled ? .accentColor : .secondary)
                        .padding(8)
                        .background(Circle().fill(Color(NSColor.controlBackgroundColor).opacity(isSoundHovered ? 0.9 : 0.6)))
                        .shadow(color: Color.black.opacity(isSoundHovered ? 0.08 : 0.0), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .help(engine.soundEnabled ? "Sound Feedback Enabled" : "Sound Muted")
                .onHover { hovering in isSoundHovered = hovering }

                Toggle("", isOn: $engine.isEnabled.animation(.spring()))
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))

            // ── Permission Banner ───────────────────────────────────────────
            if !engine.isAccessibilityGranted {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Accessibility Access Needed")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Text("Please grant accessibility permissions so NoInteraction can auto-click approval dialogues.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    Button("Grant Access") {
                        engine.promptAccessibilityPermission()
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.orange)
                    .shadow(color: Color.orange.opacity(0.2), radius: 4, y: 1)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.orange.opacity(0.08))
                .transition(.slide.combined(with: .opacity))

                Divider()
            }

            // ── Tab Navigation ──────────────────────────────────────────────
            HStack(spacing: 8) {
                tabBtn("Activity Log", tab: .activityLog, icon: "text.justify.left")
                tabBtn("Approval Rules", tab: .rules, icon: "slider.horizontal.3")
                tabBtn("Prompt Queue", tab: .promptQueue, icon: "square.stack.3d.down.right.fill")
                
                Spacer()
                
                if vm.selectedTab == .activityLog && !engine.logs.isEmpty {
                    Button(action: {
                        withAnimation {
                            engine.logs.removeAll()
                        }
                    }) {
                        Label("Clear Log", systemImage: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12)

            // ── Body Content ────────────────────────────────────────────────
            Group {
                switch vm.selectedTab {
                case .activityLog:
                    ActivityLogView(engine: engine, searchQuery: $vm.logSearchQuery)
                case .rules:
                    RulesView(engine: engine, newBtn: $vm.newButtonKeyword, newChk: $vm.newCheckboxKeyword)
                case .promptQueue:
                    PromptQueueView(engine: engine, newPromptText: $vm.newPromptText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.15), value: vm.selectedTab)

            Divider()

            // ── Footer ──────────────────────────────────────────────────────
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(engine.isAccessibilityGranted ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                        .shadow(color: (engine.isAccessibilityGranted ? Color.green : Color.red).opacity(0.3), radius: 3)
                    
                    Text(engine.isAccessibilityGranted ? "Engine Online" : "System Access Missing")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Hide to Menu Bar") {
                    NSApp.windows.first?.orderOut(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.08)))
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
        }
        .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
        .frame(minWidth: 580, minHeight: 480)
    }

    @ViewBuilder
    private func tabBtn(_ label: String, tab: DashboardTab, icon: String) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                vm.selectedTab = tab
            }
        }) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: vm.selectedTab == tab ? .bold : .medium, design: .rounded))
                .padding(.vertical, 6).padding(.horizontal, 12)
                .foregroundColor(vm.selectedTab == tab ? .white : .primary.opacity(0.7))
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(vm.selectedTab == tab
                              ? AnyShapeStyle(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.clear))
                )
                .shadow(color: vm.selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear, radius: 4, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Activity Log View

struct ActivityLogView: View {
    @ObservedObject var engine: ApproverEngine
    @Binding var searchQuery: String
    @State private var searchHovered = false

    var filteredLogs: [LogEntry] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return engine.logs }
        return engine.logs.filter {
            $0.targetText.lowercased().contains(query) ||
            $0.appName.lowercased().contains(query) ||
            $0.detectionMethod.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if engine.logs.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.08))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "eyes")
                            .font(.system(size: 32))
                            .foregroundColor(.accentColor.opacity(0.6))
                    }
                    
                    Text("Monitoring Prompts…")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Auto-accept rules will execute silently when prompts appear in code editors or browsers.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                    Spacer()
                }
                .transition(.opacity)
            } else {
                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    TextField("Search activity log...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(searchHovered ? 0.05 : 0.03))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.05), lineWidth: 1))
                )
                .onHover { hovering in searchHovered = hovering }
                .padding(.horizontal, 16).padding(.vertical, 10)

                List(filteredLogs) { log in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.12))
                                .frame(width: 28, height: 28)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(log.targetText)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                Spacer()
                                Text(log.formattedTime)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            HStack(spacing: 8) {
                                Text(log.appName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                Circle().fill(Color.secondary.opacity(0.4)).frame(width: 3, height: 3)
                                
                                Text(log.detectionMethod)
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.purple.opacity(0.1)))
                                    .foregroundColor(.purple)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Rules Config View

struct RulesView: View {
    @ObservedObject var engine: ApproverEngine
    @Binding var newBtn: String
    @Binding var newChk: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header Card
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom Verification Bypass").font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("Add label keywords to auto-accept confirmation dialogs and alerts.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    Button("Reset to Defaults") {
                        withAnimation {
                            engine.resetRulesToDefault()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.02)))

                // Rules Sections
                ruleSection(
                    title: "Button Auto-Click Keywords",
                    subtitle: "Auto-clicks button controls with these exact labels (case-insensitive)",
                    keywords: engine.buttonRules,
                    newKeyword: $newBtn,
                    targetType: .button
                )

                ruleSection(
                    title: "Checkbox Auto-Tick Keywords",
                    subtitle: "Auto-selects checkbox labels prior to approving the action",
                    keywords: engine.checkboxRules,
                    newKeyword: $newChk,
                    targetType: .checkbox
                )
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func ruleSection(
        title: String,
        subtitle: String,
        keywords: [ApprovalRule],
        newKeyword: Binding<String>,
        targetType: ApprovalRule.TargetType
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Input Bar
            HStack {
                TextField("Add new keyword...", text: newKeyword)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                
                Button("Add") {
                    withAnimation {
                        engine.addRule(keyword: newKeyword.wrappedValue, targetType: targetType)
                        newKeyword.wrappedValue = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newKeyword.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Keyword Pills Grid
            if keywords.isEmpty {
                Text("No keywords defined.")
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(keywords) { rule in
                        KeywordChip(rule: rule, onToggle: {
                            engine.toggleRule(id: rule.id, targetType: targetType)
                        }, onDelete: {
                            withAnimation {
                                engine.removeRule(id: rule.id, targetType: targetType)
                            }
                        })
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.04), lineWidth: 1))
    }
}

// MARK: - Keyword Pill Component

struct KeywordChip: View {
    let rule: ApprovalRule
    let onToggle: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                Image(systemName: rule.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundColor(rule.isEnabled ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Text(rule.keyword)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .strikethrough(!rule.isEnabled)
                .foregroundColor(rule.isEnabled ? .primary : .secondary)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(3)
                    .background(Circle().fill(Color.primary.opacity(isHovered ? 0.08 : 0.0)))
            }
            .buttonStyle(.plain)
            .onHover { hovering in isHovered = hovering }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(
            Capsule()
                .fill(rule.isEnabled ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.08))
        )
        .overlay(
            Capsule()
                .stroke(rule.isEnabled ? Color.accentColor.opacity(0.1) : Color.clear, lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)
    }
}

// MARK: - Prompt Queue View

struct PromptQueueView: View {
    @ObservedObject var engine: ApproverEngine
    @Binding var newPromptText: String
    @State private var isAddHovered = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                // Active Queue Toggle Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prompt Queue Dispatch").font(.system(size: 13, weight: .bold, design: .rounded))
                            Text("Sequentially paste prompts automatically when the agent window is free.")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $engine.isPromptQueueActive.animation(.spring()))
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                            .labelsHidden()
                            .controlSize(.small)
                    }
                    
                    if engine.isPromptQueueActive {
                        Divider().padding(.vertical, 2)
                        
                        HStack {
                            Text("Status:").font(.system(size: 11, weight: .bold))
                            if engine.currentPromptIndex < engine.promptQueue.count {
                                Text("Active — Sending \(engine.currentPromptIndex + 1) of \(engine.promptQueue.count)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.green)
                            } else {
                                Text("Complete (Queue fully dispatched)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if engine.currentPromptIndex > 0 {
                                Button("Restart Queue") {
                                    withAnimation {
                                        engine.currentPromptIndex = 0
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.04), lineWidth: 1))
                
                // Loop Mode Settings Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Loop Test Mode").font(.system(size: 13, weight: .bold, design: .rounded))
                            Text("Repetitive stress-testing via sequential system auditing.")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $engine.loopModeEnabled.animation(.spring()))
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                            .labelsHidden()
                            .controlSize(.small)
                    }
                    
                    if engine.loopModeEnabled {
                        Divider().padding(.vertical, 2)
                        
                        HStack(spacing: 12) {
                            Picker("Limit:", selection: Binding(
                                get: { engine.loopModeLimit == 0 ? 0 : 10 },
                                set: { engine.loopModeLimit = $0 }
                            ).animation(.spring())) {
                                Text("Infinite").tag(0)
                                Text("10 Iterations").tag(10)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Text("Dispatched:")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                                Text("\(engine.loopModeCounter)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                Text("/ \(engine.loopModeLimit == 0 ? "∞" : String(engine.loopModeLimit))")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                            }
                            
                            Button("Reset") {
                                engine.loopModeCounter = 0
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.04), lineWidth: 1))

                // Default System Audit Banner
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("System Audit Template", systemImage: "text.book.closed.fill")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.accentColor)
                        Spacer()
                        Button("Restore Default") {
                            withAnimation {
                                engine.resetPromptQueueToDefault()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.accentColor)
                    }
                    Text(ApproverEngine.defaultPrompt)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.01)))

                // Add to Queue Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add New Custom Prompt").font(.system(size: 12, weight: .bold, design: .rounded))
                    
                    TextEditor(text: $newPromptText)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 75)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor).opacity(0.6)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation {
                                engine.promptQueue.append(newPromptText.trimmingCharacters(in: .whitespacesAndNewlines))
                                newPromptText = ""
                            }
                        }) {
                            Text("Queue Prompt")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Capsule().fill(Color.accentColor.opacity(newPromptText.isEmpty ? 0.5 : 1.0)))
                        }
                        .buttonStyle(.plain)
                        .disabled(newPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.04), lineWidth: 1))

                // Queue List
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Configured Queue").font(.system(size: 12, weight: .bold, design: .rounded))
                        Spacer()
                        if !engine.promptQueue.isEmpty {
                            Button("Clear All") {
                                withAnimation {
                                    engine.promptQueue.removeAll()
                                    engine.currentPromptIndex = 0
                                    engine.isPromptQueueActive = false
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.red)
                        }
                    }
                    
                    if engine.promptQueue.isEmpty {
                        Text("Queue is empty. Enter a prompt above to schedule.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.01)))
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(engine.promptQueue.enumerated()), id: \.offset) { index, prompt in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(index < engine.currentPromptIndex ? Color.gray : index == engine.currentPromptIndex && engine.isPromptQueueActive ? Color.green : Color.blue)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 5)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Prompt \(index + 1)")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundColor(index < engine.currentPromptIndex ? .secondary : .primary)
                                        Text(prompt)
                                            .font(.system(size: 10, design: .monospaced))
                                            .lineLimit(2)
                                            .foregroundColor(index < engine.currentPromptIndex ? .secondary : .primary.opacity(0.8))
                                    }
                                    
                                    Spacer()
                                    
                                    Button {
                                        withAnimation {
                                            engine.promptQueue.remove(at: index)
                                            if engine.currentPromptIndex > index {
                                                engine.currentPromptIndex = max(0, engine.currentPromptIndex - 1)
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "trash").font(.system(size: 11))
                                            .foregroundColor(.secondary.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.02)))
                            }
                        }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.04), lineWidth: 1))
            }
            .padding(16)
        }
    }
}

// MARK: - Layout Helpers

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal.width ?? 400, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = layout(bounds.width, subviews)
        for (i, pt) in r.points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + pt.x, y: bounds.minY + pt.y), proposal: .unspecified)
        }
    }
    private func layout(_ maxW: CGFloat, _ subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var pts: [CGPoint] = []; var x: CGFloat = 0; var y: CGFloat = 0; var lineH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 { x = 0; y += lineH + spacing; lineH = 0 }
            pts.append(CGPoint(x: x, y: y)); lineH = max(lineH, s.height); x += s.width + spacing
        }
        return (CGSize(width: maxW, height: y + lineH), pts)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(); v.material = material; v.blendingMode = blendingMode; v.state = .active; return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material; v.blendingMode = blendingMode }
}

extension Color {
    static let emerald = Color(red: 16/255, green: 185/255, blue: 129/255)
}
