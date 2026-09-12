import SwiftUI
import ConfigKit
import ParserKit
import NetworkCore

public struct ConfigWorkbenchView: View {
    @Bindable var state: AppState

    @State private var selectedTab: ConfigWorkbenchTab = .studio

    public init(state: AppState) {
        self.state = state
    }

    public enum ConfigWorkbenchTab: String, CaseIterable, Identifiable {
        case studio = "Config Studio"
        case diff = "Structural Diff"
        case acl = "ACL Simulator"
        case parser = "CLI Output Parser"

        public var id: String { rawValue }
        public var iconName: String {
            switch self {
            case .studio: return "doc.text.magnifyingglass"
            case .diff: return "arrow.left.and.right.square"
            case .acl: return "shield.checkered"
            case .parser: return "terminal"
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Workspace Top Navigation & Header
            headerBar

            Divider()

            // Active Tab Content
            switch selectedTab {
            case .studio:
                ConfigStudioTab()
            case .diff:
                StructuralDiffTab()
            case .acl:
                ACLSimulatorTab()
            case .parser:
                CLIParserTab()
            }
        }
        .background(Theme.surfaceBackground)
    }

    private var headerBar: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.neonCyan.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.neonCyan)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Config Workbench")
                        .font(.system(size: 18, weight: .bold))
                    Text("PHASE 4")
                        .font(Theme.monoText(10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.neonCyan.opacity(0.18))
                        .foregroundStyle(Theme.neonCyan)
                        .clipShape(Capsule())
                }
                Text("Multi-Vendor AST Parser • Structural Semantic Diff • Deterministic ACL Flow Simulator • ParserKit")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Segmented Tab Picker
            HStack(spacing: 4) {
                ForEach(ConfigWorkbenchTab.allCases) { tab in
                    Button(action: { selectedTab = tab }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 12))
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab ? Theme.electricAzure.opacity(0.22) : Color.clear)
                        .foregroundStyle(selectedTab == tab ? Theme.neonCyan : Color.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(shortcutForTab(tab), modifiers: [.control, .option])
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func shortcutForTab(_ tab: ConfigWorkbenchTab) -> KeyEquivalent {
        switch tab {
        case .studio: return "1"
        case .diff: return "2"
        case .acl: return "3"
        case .parser: return "4"
        }
    }
}

// MARK: - 1. Config Studio & Redactor Tab

struct ConfigStudioTab: View {
    @State private var configText: String = sampleCiscoCoreConfig
    @State private var selectedFilter: ConfigSectionType? = nil
    @State private var redactionResult: RedactionResult? = nil
    @State private var isRedacted = false

    private let parser = ConfigParser()
    private let redactor = ConfigRedactor()

    var parsedAST: ConfigAST {
        parser.parse(text: isRedacted && redactionResult != nil ? redactionResult!.sanitizedText : configText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Studio Toolbar
            HStack(spacing: 12) {
                Menu {
                    Button("Cisco IOS-XE Core Switch") {
                        configText = sampleCiscoCoreConfig
                        isRedacted = false
                        redactionResult = nil
                    }
                    Button("Cisco NX-OS Data Center Spine") {
                        configText = sampleNXOSConfig
                        isRedacted = false
                        redactionResult = nil
                    }
                    Button("Arista EOS Border Router") {
                        configText = sampleAristaConfig
                        isRedacted = false
                        redactionResult = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text("Load Preset Config")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)

                Divider().frame(height: 18)

                // Section Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button(action: { selectedFilter = nil }) {
                            Text("All Sections")
                                .font(.system(size: 11, weight: selectedFilter == nil ? .bold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(selectedFilter == nil ? Theme.neonCyan.opacity(0.18) : Color.primary.opacity(0.04))
                                .foregroundStyle(selectedFilter == nil ? Theme.neonCyan : Color.secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        ForEach(ConfigSectionType.allCases, id: \.self) { section in
                            Button(action: { selectedFilter = (selectedFilter == section ? nil : section) }) {
                                HStack(spacing: 4) {
                                    Image(systemName: section.iconName)
                                        .font(.system(size: 10))
                                    Text(section.rawValue)
                                }
                                .font(.system(size: 11, weight: selectedFilter == section ? .bold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(selectedFilter == section ? Theme.electricAzure.opacity(0.2) : Color.primary.opacity(0.04))
                                .foregroundStyle(selectedFilter == section ? Theme.neonCyan : Color.secondary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                // Redact Secrets Button
                Button(action: toggleRedact) {
                    HStack(spacing: 6) {
                        Image(systemName: isRedacted ? "lock.slash.fill" : "lock.shield.fill")
                        Text(isRedacted ? "Show Unredacted" : "Sanitize & Redact Secrets")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isRedacted ? Theme.solarAmber.opacity(0.2) : Theme.signalEmerald.opacity(0.15))
                    .foregroundStyle(isRedacted ? Theme.solarAmber : Theme.signalEmerald)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                // Copy Button
                Button(action: copyConfig) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .padding(6)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Copy to Clipboard")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.02))

            Divider()

            // Main Editor & AST Breakdown
            HSplitView {
                // Code Viewer
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            let lines = filteredLines(from: parsedAST)
                            ForEach(lines) { line in
                                codeLineRow(line: line)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }
                    .background(Color.black.opacity(0.45))
                }
                .frame(minWidth: 500)

                // Structured Inspector Side Panel
                VStack(alignment: .leading, spacing: 14) {
                    Text("EXTRACTED TOPOLOGY INTELLIGENCE")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 14)
                        .padding(.horizontal, 14)

                    ScrollView {
                        VStack(spacing: 12) {
                            // Hostname & Vendor Card
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Hostname")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(parsedAST.hostname ?? "Unconfigured")
                                        .font(Theme.monoText(12, weight: .bold))
                                        .foregroundStyle(Theme.neonCyan)
                                }
                                HStack {
                                    Text("Vendor Engine")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(parsedAST.vendor.rawValue)
                                        .font(Theme.monoText(11))
                                        .foregroundStyle(.primary)
                                }
                            }
                            .modifier(EngineeringCardModifier(padding: 10))

                            // Interfaces Summary Card
                            let intfs = parser.extractInterfaces(from: parsedAST)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "cable.connector")
                                        .foregroundStyle(Theme.signalEmerald)
                                    Text("Interfaces (\(intfs.count))")
                                        .font(.system(size: 12, weight: .bold))
                                    Spacer()
                                }

                                ForEach(intfs) { intf in
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(intf.isShutdown ? Theme.pulseCrimson : Theme.signalEmerald)
                                            .frame(width: 6, height: 6)
                                        Text(intf.name)
                                            .font(Theme.monoText(11, weight: .semibold))
                                        Spacer()
                                        if let ip = intf.ipAddress {
                                            Text(ip)
                                                .font(Theme.monoText(10))
                                                .foregroundStyle(.secondary)
                                        } else if let vlan = intf.accessVlan {
                                            Text("VLAN \(vlan)")
                                                .font(Theme.monoText(10))
                                                .foregroundStyle(Theme.electricAzure)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .modifier(EngineeringCardModifier(padding: 10))

                            // Routing Summary Card
                            let routes = parser.extractRouting(from: parsedAST)
                            if !routes.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "point.3.connected.trianglepath.dotted")
                                            .foregroundStyle(Theme.solarAmber)
                                        Text("Routing Protocols (\(routes.count))")
                                            .font(.system(size: 12, weight: .bold))
                                    }

                                    ForEach(routes) { r in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(r.routingProtocol.rawValue) \(r.autonomousSystem.map { "AS \($0)" } ?? "")")
                                                .font(Theme.monoText(11, weight: .bold))
                                                .foregroundStyle(Theme.solarAmber)
                                            if let rId = r.routerId {
                                                Text("Router ID: \(rId)")
                                                    .font(Theme.monoText(10))
                                                    .foregroundStyle(.secondary)
                                            }
                                            Text("\(r.neighbors.count) Neighbors • \(r.networks.count) Networks")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                                .modifier(EngineeringCardModifier(padding: 10))
                            }

                            // ACLs Card
                            let acls = parser.extractACLs(from: parsedAST)
                            if !acls.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "shield.lefthalf.filled")
                                            .foregroundStyle(Theme.quantumViolet)
                                        Text("Access Control Lists (\(acls.count))")
                                            .font(.system(size: 12, weight: .bold))
                                    }

                                    ForEach(acls) { acl in
                                        HStack {
                                            Text(acl.name)
                                                .font(Theme.monoText(11, weight: .semibold))
                                            Spacer()
                                            Text("\(acl.rules.count) rules")
                                                .font(Theme.monoText(10))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .modifier(EngineeringCardModifier(padding: 10))
                            }
                        }
                        .padding(14)
                    }
                }
                .frame(minWidth: 260, maxWidth: 340)
                .background(Color.primary.opacity(0.02))
            }

            // Footer Status Bar
            HStack(spacing: 16) {
                Text("Total Lines: \(parsedAST.allLines.count)")
                    .font(Theme.monoText(11))
                    .foregroundStyle(.secondary)
                Text("Blocks: \(parsedAST.blocks.count)")
                    .font(Theme.monoText(11))
                    .foregroundStyle(.secondary)
                if isRedacted, let count = redactionResult?.redactedCount {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield.fill")
                        Text("\(count) Secrets Sanitized")
                    }
                    .font(Theme.monoText(11, weight: .bold))
                    .foregroundStyle(Theme.signalEmerald)
                }
                Spacer()
                Text("Swift 6 Native AST Lexer")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
        }
    }

    private func filteredLines(from ast: ConfigAST) -> [ConfigLine] {
        guard let filter = selectedFilter else { return ast.allLines }
        var result: [ConfigLine] = []
        for block in ast.blocks where block.sectionType == filter {
            result.append(contentsOf: block.lines)
        }
        return result.isEmpty ? ast.allLines : result
    }

    private func codeLineRow(line: ConfigLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // Line Number
            Text(String(format: "%3d", line.lineNumber))
                .font(Theme.monoText(11))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .frame(width: 32, alignment: .trailing)

            // Syntax Line
            renderSyntaxText(line.rawText)
                .font(Theme.monoText(12))

            Spacer()
        }
    }

    @ViewBuilder
    private func renderSyntaxText(_ text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("!") || trimmed.hasPrefix("#") {
            Text(text)
                .foregroundStyle(Color.secondary.opacity(0.7))
        } else if text.contains("[REDACTED_SECRET_") {
            HStack(spacing: 2) {
                Text(text.components(separatedBy: "[REDACTED_SECRET_")[0])
                    .foregroundStyle(.primary)
                Text("[REDACTED_SECRET]")
                    .font(Theme.monoText(10, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.solarAmber.opacity(0.25))
                    .foregroundStyle(Theme.solarAmber)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        } else if trimmed.hasPrefix("interface ") || trimmed.hasPrefix("router ") || trimmed.hasPrefix("ip access-list") || trimmed.hasPrefix("vlan ") {
            Text(text)
                .foregroundStyle(Theme.neonCyan)
                .bold()
        } else if trimmed.hasPrefix("permit ") {
            Text(text)
                .foregroundStyle(Theme.signalEmerald)
        } else if trimmed.hasPrefix("deny ") {
            Text(text)
                .foregroundStyle(Theme.pulseCrimson)
        } else {
            Text(text)
                .foregroundStyle(Color(nsColor: .textColor).opacity(0.9))
        }
    }

    private func toggleRedact() {
        if isRedacted {
            isRedacted = false
        } else {
            let res = redactor.sanitize(text: configText)
            redactionResult = res
            isRedacted = true
        }
    }

    private func copyConfig() {
        let textToCopy = isRedacted && redactionResult != nil ? redactionResult!.sanitizedText : configText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
    }
}

// MARK: - 2. Structural Diff Tab

struct StructuralDiffTab: View {
    @State private var baselineText: String = sampleBaselineConfig
    @State private var targetText: String = sampleTargetConfig
    @State private var isUnified: Bool = false

    private let engine = StructuralDiffEngine()

    var report: StructuralDiffReport {
        engine.compare(baseline: baselineText, target: targetText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Diff Header Bar
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    diffBadge(count: report.addedCount, prefix: "+", color: Theme.signalEmerald)
                    diffBadge(count: report.removedCount, prefix: "-", color: Theme.pulseCrimson)
                    diffBadge(count: report.modifiedCount, prefix: "~", color: Theme.solarAmber)
                }

                Spacer()

                // Load Test Scenarios
                Button("Security Audit Drift Preset") {
                    baselineText = sampleBaselineConfig
                    targetText = sampleTargetConfig
                }
                .font(.system(size: 11))

                Picker("View Mode", selection: $isUnified) {
                    Text("Side-by-Side").tag(false)
                    Text("Unified Diff").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.02))

            Divider()

            // Semantic Changes Summary Ribbon
            if !report.semanticChanges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(report.semanticChanges) { change in
                            HStack(spacing: 6) {
                                Image(systemName: change.category == .interface ? "cable.connector" : (change.category == .routing ? "point.3.connected.trianglepath.dotted" : "shield.lefthalf.filled"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(changeColor(for: change.changeType))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(change.title)
                                        .font(.system(size: 11, weight: .bold))
                                    Text(change.detail)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(changeColor(for: change.changeType).opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(changeColor(for: change.changeType).opacity(0.25), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .background(Color.primary.opacity(0.015))

                Divider()
            }

            // Diff Lines Display
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(report.diffLines) { diff in
                        diffLineRow(diff: diff)
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color.black.opacity(0.5))
        }
    }

    private func diffBadge(count: Int, prefix: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(prefix)\(count)")
                .font(Theme.monoText(11, weight: .bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.18))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private func changeColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .added: return Theme.signalEmerald
        case .removed: return Theme.pulseCrimson
        case .modified: return Theme.solarAmber
        case .unchanged: return .secondary
        }
    }

    private func diffLineRow(diff: DiffLine) -> some View {
        HStack(spacing: 12) {
            // Line numbers
            HStack(spacing: 4) {
                Text(diff.oldLineNumber.map { String(format: "%3d", $0) } ?? "   ")
                    .font(Theme.monoText(10))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                Text(diff.newLineNumber.map { String(format: "%3d", $0) } ?? "   ")
                    .font(Theme.monoText(10))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            }
            .frame(width: 60)

            // Status Indicator Icon
            switch diff.kind {
            case .added:
                Text("+")
                    .font(Theme.monoText(12, weight: .bold))
                    .foregroundStyle(Theme.signalEmerald)
            case .removed:
                Text("-")
                    .font(Theme.monoText(12, weight: .bold))
                    .foregroundStyle(Theme.pulseCrimson)
            case .modified:
                Text("~")
                    .font(Theme.monoText(12, weight: .bold))
                    .foregroundStyle(Theme.solarAmber)
            case .unchanged:
                Text(" ")
                    .font(Theme.monoText(12))
            }

            Text(diff.text)
                .font(Theme.monoText(12))
                .foregroundStyle(textColor(for: diff.kind))

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .background(backgroundColor(for: diff.kind))
    }

    private func textColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .added: return Theme.signalEmerald
        case .removed: return Theme.pulseCrimson
        case .modified: return Theme.solarAmber
        case .unchanged: return Color(nsColor: .textColor).opacity(0.85)
        }
    }

    private func backgroundColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .added: return Theme.signalEmerald.opacity(0.1)
        case .removed: return Theme.pulseCrimson.opacity(0.1)
        case .modified: return Theme.solarAmber.opacity(0.08)
        case .unchanged: return Color.clear
        }
    }
}

// MARK: - 3. ACL Simulator & Linter Tab

struct ACLSimulatorTab: View {
    @State private var srcIP: String = "192.168.1.50"
    @State private var dstIP: String = "10.0.0.2"
    @State private var protocolType: ACLProtocol = .tcp
    @State private var dstPortString: String = "443"
    @State private var isEstablished: Bool = false

    private let analyzer = ACLAnalyzer()
    private let sampleACL = ACLConfig(
        name: "INET_INBOUND_FILTER",
        isExtended: true,
        rules: [
            ACLRule(id: 10, sequence: 10, action: .permit, protocolType: .tcp, source: .any, destination: .any, portOperator: nil, isEstablished: true, remark: "Allow return established traffic", rawText: "10 permit tcp any any established"),
            ACLRule(id: 20, sequence: 20, action: .permit, protocolType: .tcp, source: .any, destination: .host("10.0.0.2"), portOperator: .eq(443), remark: "Allow HTTPS to App Server", rawText: "20 permit tcp any host 10.0.0.2 eq 443"),
            ACLRule(id: 30, sequence: 30, action: .permit, protocolType: .tcp, source: .any, destination: .host("10.0.0.2"), portOperator: .eq(80), remark: "Allow HTTP to App Server", rawText: "30 permit tcp any host 10.0.0.2 eq 80"),
            ACLRule(id: 40, sequence: 40, action: .deny, protocolType: .tcp, source: .any, destination: .host("10.0.0.2"), portOperator: .eq(22), remark: "Explicit block SSH", rawText: "40 deny tcp any host 10.0.0.2 eq 22"),
            ACLRule(id: 50, sequence: 50, action: .deny, protocolType: .any, source: .any, destination: .any, rawText: "50 deny ip any any")
        ]
    )

    var evaluationResult: FlowEvaluationResult {
        let port = UInt16(dstPortString)
        let flow = PacketFlow(
            srcIP: srcIP,
            dstIP: dstIP,
            protocolType: protocolType,
            srcPort: 54321,
            dstPort: port,
            isEstablished: isEstablished
        )
        return analyzer.evaluate(flow: flow, against: sampleACL)
    }

    var shadowedFindings: [ShadowedRuleFinding] {
        analyzer.detectShadowedRules(in: sampleACL)
    }

    var body: some View {
        HSplitView {
            // Flow Simulator Form
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("5-TUPLE FLOW SIMULATOR")
                            .font(Theme.monoText(11, weight: .bold))
                            .foregroundStyle(Theme.neonCyan)
                        Text("Simulate live packet traversal against '\(sampleACL.name)'")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    // Verdict Banner
                    HStack(spacing: 16) {
                        Image(systemName: evaluationResult.action == .permit ? "checkmark.shield.fill" : "xmark.shield.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(evaluationResult.action == .permit ? Theme.signalEmerald : Theme.pulseCrimson)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(evaluationResult.action.rawValue)
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundStyle(evaluationResult.action == .permit ? Theme.signalEmerald : Theme.pulseCrimson)
                            Text(evaluationResult.reason)
                                .font(Theme.monoText(11))
                                .foregroundStyle(.primary)
                            Text("Evaluated \(evaluationResult.evaluatedRuleCount) rules before resolution")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(
                        (evaluationResult.action == .permit ? Theme.signalEmerald : Theme.pulseCrimson).opacity(0.12)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke((evaluationResult.action == .permit ? Theme.signalEmerald : Theme.pulseCrimson).opacity(0.3), lineWidth: 1.5)
                    )

                    // Input Fields
                    VStack(spacing: 12) {
                        HStack {
                            Text("Source IP")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 100, alignment: .leading)
                            TextField("Source IP", text: $srcIP)
                                .textFieldStyle(.roundedBorder)
                                .font(Theme.monoText(12))
                        }

                        HStack {
                            Text("Destination IP")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 100, alignment: .leading)
                            TextField("Destination IP", text: $dstIP)
                                .textFieldStyle(.roundedBorder)
                                .font(Theme.monoText(12))
                        }

                        HStack {
                            Text("Protocol")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 100, alignment: .leading)
                            Picker("", selection: $protocolType) {
                                Text("TCP").tag(ACLProtocol.tcp)
                                Text("UDP").tag(ACLProtocol.udp)
                                Text("ICMP").tag(ACLProtocol.icmp)
                                Text("IP").tag(ACLProtocol.ip)
                            }
                            .pickerStyle(.segmented)
                        }

                        HStack {
                            Text("Dest Port")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 100, alignment: .leading)
                            TextField("Port (e.g. 443)", text: $dstPortString)
                                .textFieldStyle(.roundedBorder)
                                .font(Theme.monoText(12))
                        }

                        HStack {
                            Text("Quick Ports:")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 100, alignment: .leading)
                            HStack(spacing: 6) {
                                ForEach(["443", "80", "22", "53", "3389"], id: \.self) { p in
                                    Button(p) { dstPortString = p }
                                        .font(Theme.monoText(10))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }

                        Toggle("TCP Established Connection (ACK/RST)", isOn: $isEstablished)
                            .font(.system(size: 12))
                            .padding(.top, 4)
                    }
                    .modifier(EngineeringCardModifier())
                }
                .padding(20)
            }
            .frame(minWidth: 420)

            // ACL Rule Sequence & Linter Card
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("ACTIVE ACL RULES & LINTER AUDIT")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(sampleACL.rules.count) Entries")
                        .font(Theme.monoText(10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                ScrollView {
                    VStack(spacing: 12) {
                        // Rules Sequence
                        ForEach(sampleACL.rules) { rule in
                            let isMatched = evaluationResult.matchedRule?.id == rule.id
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(rule.sequence)")
                                    .font(Theme.monoText(11, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(rule.action.rawValue)
                                            .font(Theme.monoText(11, weight: .bold))
                                            .foregroundStyle(rule.action == .permit ? Theme.signalEmerald : Theme.pulseCrimson)
                                        Text(rule.protocolType.rawValue.uppercased())
                                            .font(Theme.monoText(10, weight: .semibold))
                                            .foregroundStyle(Theme.electricAzure)
                                        Spacer()
                                        if isMatched {
                                            Text("MATCHED")
                                                .font(Theme.monoText(9, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(Theme.neonCyan.opacity(0.2))
                                                .foregroundStyle(Theme.neonCyan)
                                                .clipShape(Capsule())
                                        }
                                    }

                                    Text(rule.rawText)
                                        .font(Theme.monoText(11))
                                        .foregroundStyle(isMatched ? .primary : .secondary)

                                    if let rem = rule.remark {
                                        Text("! \(rem)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .padding(10)
                            .background(isMatched ? Theme.neonCyan.opacity(0.1) : Color.primary.opacity(0.02))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isMatched ? Theme.neonCyan.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                        }

                        // Shadowed / Redundant Linter Findings
                        if !shadowedFindings.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Theme.solarAmber)
                                    Text("Linter Findings (\(shadowedFindings.count))")
                                        .font(.system(size: 12, weight: .bold))
                                }

                                ForEach(shadowedFindings) { f in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.kind.rawValue)
                                            .font(Theme.monoText(10, weight: .bold))
                                            .foregroundStyle(f.kind == .shadowed ? Theme.pulseCrimson : Theme.solarAmber)
                                        Text(f.explanation)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(8)
                                    .background(Color.primary.opacity(0.03))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            .modifier(EngineeringCardModifier(padding: 10))
                        }
                    }
                    .padding(16)
                }
            }
            .frame(minWidth: 360)
            .background(Color.primary.opacity(0.015))
        }
    }
}

// MARK: - 4. CLI Output Parser Tab

struct CLIParserTab: View {
    @State private var inputText: String = sampleIPIntBriefCLI
    @State private var selectedCommand: CommandFamily? = nil
    @State private var filterQuery: String = ""

    private let registry = ParserRegistry.shared

    var parsedResult: (parser: any VendorOutputParser, result: StructuredResult)? {
        try? registry.parse(text: inputText, forcedFamily: selectedCommand)
    }

    var body: some View {
        HSplitView {
            // Terminal Input Side
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("RAW TERMINAL OUTPUT")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Preset Buttons
                    Menu {
                        Button("show ip interface brief") { inputText = sampleIPIntBriefCLI; selectedCommand = nil }
                        Button("show interfaces") { inputText = sampleShowInterfacesCLI; selectedCommand = nil }
                        Button("show ip route") { inputText = sampleShowIPRouteCLI; selectedCommand = nil }
                        Button("show mac address-table") { inputText = sampleShowMacCLI; selectedCommand = nil }
                        Button("show arp") { inputText = sampleShowARPCLI; selectedCommand = nil }
                        Button("show cdp neighbors") { inputText = sampleShowCDPCLI; selectedCommand = nil }
                        Button("show ip bgp summary") { inputText = sampleShowBGPCLI; selectedCommand = nil }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "terminal")
                            Text("Sample Commands")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .menuStyle(.borderlessButton)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.02))

                Divider()

                TextEditor(text: $inputText)
                    .font(Theme.monoText(11))
                    .padding(8)
                    .background(Color.black.opacity(0.45))
            }
            .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)

            // Parsed Table Presentation Side
            VStack(spacing: 0) {
                // Detected Command Bar
                HStack(spacing: 10) {
                    if let (p, res) = parsedResult {
                        HStack(spacing: 6) {
                            Image(systemName: p.commandFamily.iconName)
                                .foregroundStyle(Theme.neonCyan)
                            Text(p.commandFamily.rawValue)
                                .font(Theme.monoText(12, weight: .bold))
                        }

                        Text("\(res.recordCount) Records")
                            .font(Theme.monoText(10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.signalEmerald.opacity(0.2))
                            .foregroundStyle(Theme.signalEmerald)
                            .clipShape(Capsule())
                    } else {
                        Text("Awaiting Output...")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Filter Search
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        TextField("Filter rows...", text: $filterQuery)
                            .font(Theme.monoText(11))
                            .textFieldStyle(.plain)
                            .frame(width: 130)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.03))

                Divider()

                // Render Table
                if let (_, result) = parsedResult {
                    ScrollView([.horizontal, .vertical]) {
                        renderStructuredResultTable(result)
                            .padding(14)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "questionmark.folder")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Paste command output on the left or select a sample preset.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 500)
            .background(Color.primary.opacity(0.01))
        }
    }

    @ViewBuilder
    private func renderStructuredResultTable(_ result: StructuredResult) -> some View {
        switch result {
        case .ipInterfaceBrief(let entries):
            VStack(spacing: 6) {
                HStack {
                    Text("INTERFACE").frame(width: 140, alignment: .leading)
                    Text("IP ADDRESS").frame(width: 120, alignment: .leading)
                    Text("OK?").frame(width: 50, alignment: .center)
                    Text("METHOD").frame(width: 70, alignment: .leading)
                    Text("STATUS").frame(width: 120, alignment: .leading)
                    Text("PROTOCOL").frame(width: 80, alignment: .leading)
                    Spacer()
                }
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(.secondary)

                Divider()

                ForEach(entries.filter { filterQuery.isEmpty || $0.interface.localizedCaseInsensitiveContains(filterQuery) || $0.ipAddress.contains(filterQuery) }) { entry in
                    HStack {
                        Text(entry.interface)
                            .font(Theme.monoText(11, weight: .bold))
                            .frame(width: 140, alignment: .leading)
                        Text(entry.ipAddress)
                            .font(Theme.monoText(11))
                            .frame(width: 120, alignment: .leading)
                        Text(entry.isOK ? "YES" : "NO")
                            .font(Theme.monoText(10))
                            .frame(width: 50, alignment: .center)
                        Text(entry.method)
                            .font(.system(size: 11))
                            .frame(width: 70, alignment: .leading)
                        statusPill(text: entry.status, isUp: entry.isUp)
                            .frame(width: 120, alignment: .leading)
                        Text(entry.lineProtocol)
                            .font(Theme.monoText(11))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }

        case .interfaceDetails(let entries):
            VStack(spacing: 8) {
                ForEach(entries) { intf in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(intf.name)
                                .font(Theme.monoText(12, weight: .bold))
                                .foregroundStyle(Theme.neonCyan)
                            Spacer()
                            Text("\(intf.adminState), \(intf.lineState)")
                                .font(Theme.monoText(10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(intf.adminState.lowercased().contains("up") ? Theme.signalEmerald.opacity(0.2) : Theme.pulseCrimson.opacity(0.2))
                                .foregroundStyle(intf.adminState.lowercased().contains("up") ? Theme.signalEmerald : Theme.pulseCrimson)
                                .clipShape(Capsule())
                        }

                        HStack(spacing: 16) {
                            if let ip = intf.ipAddress { Text("IP: \(ip)") }
                            if let mtu = intf.mtu { Text("MTU: \(mtu)") }
                            if let bw = intf.bandwidth { Text("BW: \(bw)") }
                            if let speed = intf.speed { Text("Speed: \(speed)") }
                            if let dup = intf.duplex { Text("Duplex: \(dup)") }
                        }
                        .font(Theme.monoText(10))
                        .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            Text("In: \(intf.inputPackets) pkts")
                            Text("Out: \(intf.outputPackets) pkts")
                            Text("CRC Errors: \(intf.crcErrors)")
                                .foregroundStyle(intf.crcErrors > 0 ? Theme.pulseCrimson : .secondary)
                                .bold(intf.crcErrors > 0)
                        }
                        .font(Theme.monoText(10))

                        if !intf.anomalies.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(intf.anomalies, id: \.self) { anom in
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                        Text(anom)
                                    }
                                    .font(Theme.monoText(9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.solarAmber.opacity(0.2))
                                    .foregroundStyle(Theme.solarAmber)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                    }
                    .modifier(EngineeringCardModifier(padding: 10))
                }
            }

        case .routes(let entries):
            VStack(spacing: 6) {
                HStack {
                    Text("PROTO").frame(width: 60, alignment: .leading)
                    Text("PREFIX").frame(width: 140, alignment: .leading)
                    Text("METRIC").frame(width: 80, alignment: .leading)
                    Text("NEXT HOP").frame(width: 120, alignment: .leading)
                    Text("INTERFACE").frame(width: 120, alignment: .leading)
                    Spacer()
                }
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(.secondary)

                Divider()

                ForEach(entries) { r in
                    HStack {
                        Text(r.protocolCode)
                            .font(Theme.monoText(11, weight: .bold))
                            .foregroundStyle(routeColor(for: r.protocolCode))
                            .frame(width: 60, alignment: .leading)
                        Text(r.prefix)
                            .font(Theme.monoText(11, weight: .bold))
                            .frame(width: 140, alignment: .leading)
                        Text(r.adminDistance.map { "[\($0)/\(r.metric ?? 0)]" } ?? "-")
                            .font(Theme.monoText(10))
                            .frame(width: 80, alignment: .leading)
                        Text(r.nextHop ?? "-")
                            .font(Theme.monoText(11))
                            .frame(width: 120, alignment: .leading)
                        Text(r.outgoingInterface ?? "-")
                            .font(Theme.monoText(11))
                            .frame(width: 120, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }

        case .macTable(let entries):
            VStack(spacing: 6) {
                HStack {
                    Text("VLAN").frame(width: 60, alignment: .leading)
                    Text("MAC ADDRESS").frame(width: 150, alignment: .leading)
                    Text("TYPE").frame(width: 90, alignment: .leading)
                    Text("PORT").frame(width: 100, alignment: .leading)
                    Spacer()
                }
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(.secondary)

                Divider()

                ForEach(entries) { m in
                    HStack {
                        Text("\(m.vlan)").font(Theme.monoText(11)).frame(width: 60, alignment: .leading)
                        Text(m.macAddress).font(Theme.monoText(11, weight: .bold)).frame(width: 150, alignment: .leading)
                        Text(m.type).font(.system(size: 11)).frame(width: 90, alignment: .leading)
                        Text(m.port).font(Theme.monoText(11)).frame(width: 100, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }

        case .arp(let entries):
            VStack(spacing: 6) {
                HStack {
                    Text("IP ADDRESS").frame(width: 120, alignment: .leading)
                    Text("MAC ADDRESS").frame(width: 140, alignment: .leading)
                    Text("VENDOR (OUI)").frame(width: 130, alignment: .leading)
                    Text("AGE (MIN)").frame(width: 70, alignment: .leading)
                    Text("INTERFACE").frame(width: 120, alignment: .leading)
                    Spacer()
                }
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(.secondary)

                Divider()

                ForEach(entries) { a in
                    HStack {
                        Text(a.ipAddress).font(Theme.monoText(11, weight: .bold)).frame(width: 120, alignment: .leading)
                        Text(a.macAddress).font(Theme.monoText(11)).frame(width: 140, alignment: .leading)
                        Text(a.vendor ?? "Generic").font(.system(size: 10)).foregroundStyle(Theme.electricAzure).frame(width: 130, alignment: .leading)
                        Text(a.ageMinutes).font(Theme.monoText(10)).frame(width: 70, alignment: .leading)
                        Text(a.interface).font(Theme.monoText(11)).frame(width: 120, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }

        case .neighbors(let entries):
            VStack(spacing: 6) {
                HStack {
                    Text("DEVICE ID").frame(width: 140, alignment: .leading)
                    Text("LOCAL INTF").frame(width: 90, alignment: .leading)
                    Text("PLATFORM").frame(width: 100, alignment: .leading)
                    Text("REMOTE PORT").frame(width: 110, alignment: .leading)
                    Text("CAPABILITY").frame(width: 80, alignment: .leading)
                    Spacer()
                }
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(.secondary)

                Divider()

                ForEach(entries) { n in
                    HStack {
                        Text(n.deviceId).font(Theme.monoText(11, weight: .bold)).foregroundStyle(Theme.neonCyan).frame(width: 140, alignment: .leading)
                        Text(n.localInterface).font(Theme.monoText(11)).frame(width: 90, alignment: .leading)
                        Text(n.platform).font(.system(size: 11)).frame(width: 100, alignment: .leading)
                        Text(n.portId).font(Theme.monoText(11)).frame(width: 110, alignment: .leading)
                        Text(n.capability).font(Theme.monoText(10)).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }

        case .bgpSummary(let entries):
            VStack(spacing: 6) {
                HStack {
                    Text("NEIGHBOR").frame(width: 120, alignment: .leading)
                    Text("REMOTE AS").frame(width: 80, alignment: .leading)
                    Text("MSG R/S").frame(width: 90, alignment: .leading)
                    Text("UP/DOWN").frame(width: 80, alignment: .leading)
                    Text("STATE / PFX").frame(width: 90, alignment: .leading)
                    Spacer()
                }
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(.secondary)

                Divider()

                ForEach(entries) { b in
                    HStack {
                        Text(b.neighborIP).font(Theme.monoText(11, weight: .bold)).frame(width: 120, alignment: .leading)
                        Text("\(b.remoteAS)").font(Theme.monoText(11)).frame(width: 80, alignment: .leading)
                        Text("\(b.msgRcvd)/\(b.msgSent)").font(Theme.monoText(10)).frame(width: 90, alignment: .leading)
                        Text(b.upDown).font(Theme.monoText(10)).frame(width: 80, alignment: .leading)
                        Text(b.stateOrPfxRcd)
                            .font(Theme.monoText(10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(b.isEstablished ? Theme.signalEmerald.opacity(0.2) : Theme.pulseCrimson.opacity(0.2))
                            .foregroundStyle(b.isEstablished ? Theme.signalEmerald : Theme.pulseCrimson)
                            .clipShape(Capsule())
                            .frame(width: 90, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    private func statusPill(text: String, isUp: Bool) -> some View {
        Text(text)
            .font(Theme.monoText(10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isUp ? Theme.signalEmerald.opacity(0.18) : (text.contains("admin") ? Theme.solarAmber.opacity(0.18) : Theme.pulseCrimson.opacity(0.18)))
            .foregroundStyle(isUp ? Theme.signalEmerald : (text.contains("admin") ? Theme.solarAmber : Theme.pulseCrimson))
            .clipShape(Capsule())
    }

    private func routeColor(for code: String) -> Color {
        switch code.prefix(1) {
        case "C", "L": return Theme.signalEmerald
        case "S": return Theme.neonCyan
        case "O": return Theme.solarAmber
        case "B": return Theme.quantumViolet
        default: return .secondary
        }
    }
}

// MARK: - Sample Data Presets

let sampleCiscoCoreConfig = """
! Current configuration: 4120 bytes
!
version 17.3
service timestamps debug datetime msec
service timestamps log datetime msec
service password-encryption
!
hostname core-switch-01
!
enable secret 9 $9$W2.y5G0.11$fP2o3/ZlS6
username admin privilege 15 secret 9 $9$m0129Fz81$abcdef123456
!
vlan 10
 name MANAGEMENT
!
vlan 20
 name CORP_USERS
!
interface GigabitEthernet0/0/0
 description UPLINK TO WAN ROUTER
 ip address 10.0.0.2 255.255.255.252
 no shutdown
 mtu 1500
!
interface GigabitEthernet0/0/1
 description ACCESS USERS
 switchport access vlan 20
 shutdown
!
interface GigabitEthernet0/0/2
 description TRUNK TO DISTRIBUTION
 switchport trunk allowed vlan 10,20,30-40
!
router bgp 65001
 bgp router-id 10.255.255.1
 neighbor 10.0.0.1 remote-as 65000
 neighbor 10.0.0.1 password 7 071B244F4D091A
!
ip access-list extended INET_INBOUND
 remark Allow return established traffic
 10 permit tcp any any established
 20 permit tcp any host 10.0.0.2 eq 443
 30 permit tcp any host 10.0.0.2 eq 80
 40 deny ip any any
!
snmp-server community MySecretStr RO
!
line con 0
 stopbits 1
!
end
"""

let sampleNXOSConfig = """
! Cisco NX-OS Configuration
version 9.3(5)
hostname spine-dc-01
feature bgp
feature vpc
feature lacp

vlan 100
  name DC_SERVERS

interface Ethernet1/1
  description LEAF-01 UPLINK
  no switchport
  ip address 10.100.1.1/31
  no shutdown

router bgp 65100
  router-id 10.255.0.1
  neighbor 10.100.1.0 remote-as 65101
    address-family ipv4 unicast
"""

let sampleAristaConfig = """
! Arista EOS Configuration
hostname arista-border-01
!
vlan 50
   name DMZ
!
interface Ethernet1
   description WAN-PEER
   no switchport
   ip address 172.16.0.2/30
!
router bgp 65200
   router-id 10.255.255.2
   neighbor 172.16.0.1 remote-as 65000
"""

let sampleBaselineConfig = """
hostname core-switch-01
!
interface GigabitEthernet0/0/1
 description ACCESS USERS
 switchport access vlan 20
 shutdown
!
router bgp 65001
 neighbor 10.0.0.1 remote-as 65000
!
ip access-list extended INET_INBOUND
 10 permit tcp any host 10.0.0.2 eq 443
 20 deny ip any any
"""

let sampleTargetConfig = """
hostname core-switch-01
!
interface GigabitEthernet0/0/1
 description ACCESS USERS
 switchport access vlan 30
 no shutdown
!
interface GigabitEthernet0/0/2
 description NEW BRANCH UPLINK
 ip address 10.50.1.1 255.255.255.0
 no shutdown
!
router bgp 65001
 neighbor 10.0.0.1 remote-as 65000
 neighbor 10.0.0.5 remote-as 65002
!
ip access-list extended INET_INBOUND
 10 permit tcp any host 10.0.0.2 eq 443
 15 permit tcp any host 10.0.0.2 eq 80
 20 deny ip any any
"""

let sampleIPIntBriefCLI = """
Interface              IP-Address      OK? Method Status                Protocol
FastEthernet0/0        192.168.1.1     YES NVRAM  up                    up      
FastEthernet0/1        unassigned      YES unset  administratively down down    
GigabitEthernet0/0/0   10.0.0.1        YES manual up                    up      
Loopback0              127.0.0.1       YES unset  up                    up      
"""

let sampleShowInterfacesCLI = """
GigabitEthernet0/1 is up, line protocol is up
  Hardware is Gigabit Ethernet, address is 0050.56b2.1a2b (bia 0050.56b2.1a2b)
  Internet address is 10.0.0.1/24
  MTU 1500 bytes, BW 1000000 Kbit/sec, DLY 10 usec,
     Full-duplex, 1000Mb/s, media type is RJ45
     1234567 packets input, 891234567 bytes, 0 no buffer
     Received 123 broadcasts (0 IP multicasts)
     0 runts, 0 giants, 0 throttles
     14 input errors, 14 CRC, 0 frame, 0 overrun, 0 ignored
     987654 packets output, 654321987 bytes, 0 underruns
"""

let sampleShowIPRouteCLI = """
Codes: L - local, C - connected, S - static, R - RIP, M - mobile, B - BGP
       D - EIGRP, EX - EIGRP external, O - OSPF, IA - OSPF inter area 

Gateway of last resort is 10.0.0.1 to network 0.0.0.0

C        10.0.0.0/24 is directly connected, GigabitEthernet0/1
S*       0.0.0.0/0 [1/0] via 10.0.0.1
O        172.16.1.0/24 [110/20] via 10.0.0.2, GigabitEthernet0/1
B        192.168.100.0/24 [20/0] via 10.255.255.1
"""

let sampleShowMacCLI = """
          Mac Address Table
-------------------------------------------
Vlan    Mac Address       Type        Ports
----    -----------       --------    -----
  10    0014.2201.2345    DYNAMIC     Gi0/1
  20    0050.56a1.b2c3    DYNAMIC     Gi0/2
 100    0000.0c07.ac01    STATIC      Router
"""

let sampleShowARPCLI = """
Protocol  Address          Age (min)  Hardware Addr   Type   Interface
Internet  192.168.1.1             -   0050.56b2.1a2b  ARPA   GigabitEthernet0/0
Internet  192.168.1.50           12   3c22.fb12.3456  ARPA   GigabitEthernet0/0
"""

let sampleShowCDPCLI = """
Capability Codes: R - Router, T - Trans Bridge, B - Source Route Bridge
                  S - Switch, H - Host, I - IGMP, r - Repeater, P - Phone

Device ID        Local Intrfce     Hldtme    Capability  Platform  Port ID
sw-core-01       Gig 0/1           154              R S  WS-C3850  Gig 1/0/24
router-edge      Gig 0/0           120              R    ISR4451   Gig 0/0/0
"""

let sampleShowBGPCLI = """
BGP router identifier 10.255.255.1, local AS number 65001
BGP table version is 42, main routing table version 42

Neighbor        V           AS MsgRcvd MsgSent   TblVer  InQ OutQ Up/Down  State/PfxRcd
10.0.0.2        4        65002    1204    1205       42    0    0 02:14:22        5
10.0.0.6        4        65003     500     502       42    0    0 00:10:05    Active
"""
