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

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────────────────
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(engine.isEnabled && engine.isAccessibilityGranted
                              ? Color.green.opacity(0.18)
                              : engine.isEnabled ? Color.orange.opacity(0.18) : Color.gray.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: engine.isEnabled && engine.isAccessibilityGranted
                          ? "bolt.shield.fill" : engine.isEnabled
                          ? "exclamationmark.shield.fill" : "pause.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(engine.isEnabled && engine.isAccessibilityGranted ? .green
                                         : engine.isEnabled ? .orange : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("NoInteraction").font(.title3).fontWeight(.bold)
                        Text("v1.2")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .foregroundColor(.secondary)
                    }
                    Text(engine.isEnabled && engine.isAccessibilityGranted
                         ? "Active & Monitoring Anti-Gravity Prompts"
                         : engine.isEnabled ? "Needs Accessibility Permission" : "Paused")
                        .font(.caption).foregroundColor(.secondary)
                }

                Spacer()

                // Approval Count Badge
                if engine.totalApprovalsCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill").font(.caption)
                        Text("\(engine.totalApprovalsCount) Approved")
                            .font(.caption2).fontWeight(.semibold)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
                    .foregroundColor(.green)
                }

                // Sound Toggle Button
                Button {
                    engine.soundEnabled.toggle()
                } label: {
                    Image(systemName: engine.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(engine.soundEnabled ? .accentColor : .secondary)
                        .padding(6)
                        .background(Circle().fill(Color(NSColor.controlBackgroundColor)))
                }
                .buttonStyle(.plain)
                .help(engine.soundEnabled ? "Sound Feedback Enabled" : "Sound Muted")

                Toggle("", isOn: $engine.isEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                    .labelsHidden()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))

            Divider()

            // ── Permission Banner ───────────────────────────────────────────
            if !engine.isAccessibilityGranted {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility Permission Required")
                            .font(.system(size: 13, weight: .bold))
                        Text("NoInteraction needs permission to observe & auto-approve Anti-Gravity prompts.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        )
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small).tint(.orange)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.orange.opacity(0.09))

                Divider()
            }

            // ── Tab Navigation ──────────────────────────────────────────────
            HStack(spacing: 6) {
                tabBtn("Activity Log", tab: .activityLog, icon: "clock.fill")
                tabBtn("Approval Rules", tab: .rules, icon: "slider.horizontal.3")
                tabBtn("Prompt Queue", tab: .promptQueue, icon: "play.rectangle.fill")
                Spacer()
                if vm.selectedTab == .activityLog && !engine.logs.isEmpty {
                    Button("Clear Log") {
                        engine.logs.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.top, 8)
 
            Divider().padding(.top, 6)
 
            // ── Body Content ────────────────────────────────────────────────
            Group {
                if vm.selectedTab == .activityLog {
                    ActivityLogView(engine: engine, searchQuery: $vm.logSearchQuery)
                } else if vm.selectedTab == .rules {
                    RulesView(engine: engine,
                              newBtn: $vm.newButtonKeyword,
                              newChk: $vm.newCheckboxKeyword)
                } else {
                    PromptQueueView(engine: engine, newPromptText: $vm.newPromptText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // ── Footer ──────────────────────────────────────────────────────
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(engine.isAccessibilityGranted ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(engine.isAccessibilityGranted ? "Accessibility Ready" : "Accessibility Restricted")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Button("Hide to Menu Bar") {
                    NSApp.windows.first?.orderOut(nil)
                }
                .buttonStyle(.plain).font(.caption).foregroundColor(.accentColor)
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .frame(minWidth: 540, minHeight: 440)
    }

    @ViewBuilder
    private func tabBtn(_ label: String, tab: DashboardTab, icon: String) -> some View {
        Button(action: { vm.selectedTab = tab }) {
            Label(label, systemImage: icon)
                .font(.system(size: 12, weight: vm.selectedTab == tab ? .semibold : .regular))
                .padding(.vertical, 5).padding(.horizontal, 12)
                .foregroundColor(vm.selectedTab == tab ? .primary : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(vm.selectedTab == tab ? Color(NSColor.controlBackgroundColor) : .clear)
                )
        }.buttonStyle(.plain)
    }
}

// MARK: - Activity Log View

struct ActivityLogView: View {
    @ObservedObject var engine: ApproverEngine
    @Binding var searchQuery: String

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
        if engine.logs.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "bolt.shield")
                    .font(.system(size: 42))
                    .foregroundColor(.secondary.opacity(0.35))
                Text("Listening for Anti-Gravity Prompts…")
                    .font(.headline).foregroundColor(.secondary)
                Text("When Anti-Gravity asks for permission (Allow/Submit/Run), NoInteraction will auto-accept and log it here.")
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Spacer()
            }
        } else {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").font(.caption).foregroundColor(.secondary)
                    TextField("Filter activity log...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))
                .padding(.horizontal, 12).padding(.vertical, 6)

                List(filteredLogs) { log in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green).font(.system(size: 15))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(log.targetText)
                                    .font(.system(size: 13, weight: .bold))
                                    .lineLimit(1)
                                Spacer()
                                Text(log.formattedTime)
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            HStack(spacing: 6) {
                                Text(log.appName).font(.caption).foregroundColor(.secondary)
                                Text("·").font(.caption).foregroundColor(.secondary)
                                Text(log.detectionMethod)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.purple.opacity(0.12)))
                                    .foregroundColor(.purple)
                            }
                        }
                    }
                    .padding(.vertical, 3)
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
            VStack(alignment: .leading, spacing: 18) {

                // Section Header with Reset Defaults
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom Approval Rules").font(.headline)
                        Text("Configure keywords for auto-clicking buttons and auto-ticking checkboxes.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Reset Defaults") {
                        engine.resetRulesToDefault()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }

                Divider()

                // Section 1: Buttons
                ruleSection(
                    title: "Auto-Click Buttons",
                    subtitle: "Buttons with these titles will be auto-clicked when prompted",
                    keywords: engine.buttonRules,
                    newKeyword: $newBtn,
                    targetType: .button
                )

                // Section 2: Checkboxes
                ruleSection(
                    title: "Auto-Tick Checkboxes",
                    subtitle: "Checkboxes with these labels will be auto-ticked before approving",
                    keywords: engine.checkboxRules,
                    newKeyword: $newChk,
                    targetType: .checkbox
                )
            }
            .padding(14)
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline).fontWeight(.bold)
            Text(subtitle).font(.caption).foregroundColor(.secondary)

            HStack {
                TextField("Add new keyword (e.g. 'Trust')", text: newKeyword)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    engine.addRule(keyword: newKeyword.wrappedValue, targetType: targetType)
                    newKeyword.wrappedValue = ""
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(newKeyword.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            FlowLayout(spacing: 6) {
                ForEach(keywords) { rule in
                    HStack(spacing: 5) {
                        Button {
                            engine.toggleRule(id: rule.id, targetType: targetType)
                        } label: {
                            Image(systemName: rule.isEnabled ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11))
                                .foregroundColor(rule.isEnabled ? .green : .secondary)
                        }
                        .buttonStyle(.plain)

                        Text(rule.keyword)
                            .font(.system(size: 12, weight: .medium))
                            .strikethrough(!rule.isEnabled)
                            .foregroundColor(rule.isEnabled ? .primary : .secondary)

                        Button {
                            engine.removeRule(id: rule.id, targetType: targetType)
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(
                        Capsule().fill(rule.isEnabled ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.12))
                    )
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
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

struct PromptQueueView: View {
    @ObservedObject var engine: ApproverEngine
    @Binding var newPromptText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                // ── Section 1: Prompt Queue Automation ─────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prompt Queue Automation").font(.subheadline).fontWeight(.bold)
                            Text("Automatically paste sequential prompts when the agent becomes free.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $engine.isPromptQueueActive)
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                            .labelsHidden()
                    }
                    
                    if engine.isPromptQueueActive {
                        Divider().padding(.vertical, 2)
                        
                        // Status details
                        HStack {
                            Text("Status:").font(.caption).fontWeight(.semibold)
                            if engine.currentPromptIndex < engine.promptQueue.count {
                                Text("Active (Pasting \(engine.currentPromptIndex + 1)/\(engine.promptQueue.count))")
                                    .font(.caption).foregroundColor(.green).fontWeight(.medium)
                            } else {
                                Text("Completed (All prompts sent)")
                                    .font(.caption).foregroundColor(.gray)
                            }
                            Spacer()
                            if engine.currentPromptIndex > 0 {
                                Button("Reset Index") {
                                    engine.currentPromptIndex = 0
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
                
                // ── Section 2: Loop Mode (Auto-Paste) ──────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Loop Mode (Infinite/Repeat)").font(.subheadline).fontWeight(.bold)
                            Text("Repeatedly paste the default system audit prompt when the agent is free.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $engine.loopModeEnabled)
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                            .labelsHidden()
                    }
                    
                    if engine.loopModeEnabled {
                        Divider().padding(.vertical, 2)
                        
                        HStack(spacing: 12) {
                            Picker("Limit:", selection: Binding(
                                get: { engine.loopModeLimit == 0 ? 0 : 10 },
                                set: { engine.loopModeLimit = $0 }
                            )) {
                                Text("Infinite Loop").tag(0)
                                Text("10 Iterations").tag(10)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Text("Sent:")
                                    .font(.caption).foregroundColor(.secondary)
                                Text("\(engine.loopModeCounter)")
                                    .font(.system(size: 11, weight: .bold))
                                if engine.loopModeLimit > 0 {
                                    Text("/ \(engine.loopModeLimit)")
                                        .font(.caption).foregroundColor(.secondary)
                                } else {
                                    Text("/ ∞")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                            
                            Button("Reset Count") {
                                engine.loopModeCounter = 0
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))

                // ── Section 3: Default Prompt Reference ───────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("💡 Default System-Audit Prompt").font(.caption).fontWeight(.bold).foregroundColor(.accentColor)
                        Spacer()
                        Button("Load Default & Run Queue") {
                            engine.resetPromptQueueToDefault()
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    Text(ApproverEngine.defaultPrompt)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.05)))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))

                // ── Section 4: Add New Prompt ─────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add New Prompt to Queue").font(.caption).fontWeight(.bold)
                    TextEditor(text: $newPromptText)
                        .frame(height: 70)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                    
                    HStack {
                        Spacer()
                        Button("Add to Queue") {
                            engine.promptQueue.append(newPromptText.trimmingCharacters(in: .whitespacesAndNewlines))
                            newPromptText = ""
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .disabled(newPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))

                // ── Section 5: Queue List ─────────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Queue List").font(.caption).fontWeight(.bold)
                        Spacer()
                        if !engine.promptQueue.isEmpty {
                            Button("Clear Queue") {
                                engine.promptQueue.removeAll()
                                engine.currentPromptIndex = 0
                                engine.isPromptQueueActive = false
                            }
                            .buttonStyle(.plain).font(.caption).foregroundColor(.red)
                        }
                    }
                    
                    if engine.promptQueue.isEmpty {
                        VStack {
                            Spacer()
                            Text("Queue is empty. Add a prompt above to get started!")
                                .font(.caption).foregroundColor(.secondary)
                                .padding(.vertical, 20)
                                .frame(maxWidth: .infinity, alignment: .center)
                            Spacer()
                        }
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                    } else {
                        List {
                            ForEach(Array(engine.promptQueue.enumerated()), id: \.offset) { index, prompt in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(index < engine.currentPromptIndex ? Color.gray : index == engine.currentPromptIndex && engine.isPromptQueueActive ? Color.green : Color.blue)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 5)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Prompt \(index + 1)")
                                            .font(.caption).fontWeight(.bold)
                                            .foregroundColor(index < engine.currentPromptIndex ? .secondary : .primary)
                                        Text(prompt)
                                            .font(.system(size: 11))
                                            .lineLimit(3)
                                            .foregroundColor(index < engine.currentPromptIndex ? .secondary : .primary)
                                    }
                                    Spacer()
                                    
                                    Button {
                                        engine.promptQueue.remove(at: index)
                                        if engine.currentPromptIndex > index {
                                            engine.currentPromptIndex = max(0, engine.currentPromptIndex - 1)
                                        }
                                    } label: {
                                        Image(systemName: "trash").font(.caption2)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .listStyle(.plain)
                        .frame(height: 120)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
            }
            .padding(14)
        }
    }
}
