import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ConfigKit
import ParserKit
import NetworkCore

public struct ConfigWorkbenchView: View {
    @Bindable var state: AppState

    @State private var selectedTab: ConfigWorkbenchTab = .studio
    @State private var sharedConfigText: String = sampleCiscoCoreConfig

    public init(state: AppState) {
        self.state = state
    }

    public enum ConfigWorkbenchTab: String, CaseIterable, Identifiable {
        case studio = "Config Studio"
        case diff = "Structural Diff"
        case acl = "ACL Simulator"
        case parser = "CLI Output Parser"
        case compliance = "Compliance & Hardening"

        public var id: String { rawValue }
        public var iconName: String {
            switch self {
            case .studio: return "doc.text.magnifyingglass"
            case .diff: return "arrow.left.and.right.square"
            case .acl: return "shield.checkered"
            case .parser: return "terminal"
            case .compliance: return "checkmark.shield.fill"
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
                ConfigStudioTab(configText: $sharedConfigText, state: state)
            case .diff:
                StructuralDiffTab(activeConfigText: sharedConfigText)
            case .acl:
                ACLSimulatorTab(currentConfigText: sharedConfigText)
            case .parser:
                CLIParserTab(state: state)
            case .compliance:
                ComplianceAuditorTab(currentConfigText: sharedConfigText)
            }
        }
        .background(Theme.surfaceBackground)
        .onAppear {
            syncStateHandoff()
        }
        .onChange(of: state.configWorkbenchTargetTab) { _, newTab in
            if let newTab = newTab {
                switch newTab {
                case 0: selectedTab = .studio
                case 1: selectedTab = .diff
                case 2: selectedTab = .acl
                case 3: selectedTab = .parser
                case 4: selectedTab = .compliance
                default: break
                }
                state.configWorkbenchTargetTab = nil
            }
        }
        .onChange(of: state.configWorkbenchText) { _, newText in
            if let newText = newText, !newText.isEmpty {
                sharedConfigText = newText
                selectedTab = .studio
                state.configWorkbenchText = nil
            }
        }
    }

    private func syncStateHandoff() {
        if let target = state.configWorkbenchTargetTab {
            switch target {
            case 0: selectedTab = .studio
            case 1: selectedTab = .diff
            case 2: selectedTab = .acl
            case 3: selectedTab = .parser
            case 4: selectedTab = .compliance
            default: break
            }
            state.configWorkbenchTargetTab = nil
        }
        if let incoming = state.configWorkbenchText, !incoming.isEmpty {
            sharedConfigText = incoming
            state.configWorkbenchText = nil
        }
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
                    Text("WORLD-CLASS SUITE")
                        .font(Theme.monoText(10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.neonCyan.opacity(0.18))
                        .foregroundStyle(Theme.neonCyan)
                        .clipShape(Capsule())
                }
                Text("Multi-Vendor Grammar Parser • Semantic Diff & Rollback • Deterministic ACL Engine • CIS/STIG Hardening Auditor")
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
                        .padding(.horizontal, 11)
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
        .padding(.vertical, 12)
    }

    private func shortcutForTab(_ tab: ConfigWorkbenchTab) -> KeyEquivalent {
        switch tab {
        case .studio: return "1"
        case .diff: return "2"
        case .acl: return "3"
        case .parser: return "4"
        case .compliance: return "5"
        }
    }
}

// MARK: - 1. Config Studio & Redactor Tab

struct ConfigStudioTab: View {
    @Binding var configText: String
    var state: AppState

    @State private var selectedFilter: ConfigSectionType? = nil
    @State private var isRedacted = false
    @State private var isAnonymized = false
    @State private var isEditing = false
    @State private var isTargetedForDrop = false
    @State private var toastMessage: String? = nil

    private let parser = ConfigParser()
    private let redactor = ConfigRedactor()

    var activeProcessedText: String {
        var txt = configText
        if isRedacted {
            txt = redactor.sanitize(text: txt).sanitizedText
        }
        if isAnonymized {
            txt = redactor.applyTopologyIPAnonymization(to: txt)
        }
        return txt
    }

    var parsedAST: ConfigAST {
        parser.parse(text: activeProcessedText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Studio Toolbar
            HStack(spacing: 10) {
                // Multi-Vendor Preset Dropdown
                Menu {
                    Section("Cisco") {
                        Button("Cisco IOS-XE Core Switch") { configText = sampleCiscoCoreConfig; resetToggles() }
                        Button("Cisco NX-OS Data Center Spine") { configText = sampleNXOSConfig; resetToggles() }
                    }
                    Section("Juniper Junos") {
                        Button("Juniper Junos (Hierarchical { })") { configText = sampleJunosConfig; resetToggles() }
                        Button("Juniper Junos (Set Notation)") { configText = sampleJunosSetConfig; resetToggles() }
                    }
                    Section("Arista & Linux") {
                        Button("Arista EOS Border Gateway") { configText = sampleAristaConfig; resetToggles() }
                    }
                    Section("Security Appliances") {
                        Button("Fortinet FortiOS Firewall") { configText = sampleFortinetConfig; resetToggles() }
                        Button("Palo Alto PAN-OS Next-Gen FW") { configText = samplePaloAltoConfig; resetToggles() }
                    }
                    Section("Enterprise Edge") {
                        Button("MikroTik RouterOS Gateway") { configText = sampleMikrotikConfig; resetToggles() }
                        Button("Huawei VRP Core Switch") { configText = sampleHuaweiConfig; resetToggles() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.gearshape")
                        Text("Presets")
                        Image(systemName: "chevron.down").font(.system(size: 8))
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)

                // Open File Button
                Button(action: openFileFromDisk) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Open...")
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Open configuration file from Mac storage")

                // Save As Button
                Button(action: saveConfigToDisk) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Save As...")
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Save configuration or sanitized output to disk")

                // Export JSON AST
                Button(action: exportJSONAST) {
                    HStack(spacing: 5) {
                        Image(systemName: "curlybraces")
                        Text("Export AST")
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Export parsed AST hierarchy to JSON")

                Divider().frame(height: 18)

                // Edit Mode Toggle
                Toggle(isOn: $isEditing) {
                    HStack(spacing: 4) {
                        Image(systemName: isEditing ? "pencil.circle.fill" : "pencil.circle")
                        Text("Editable")
                    }
                    .font(.system(size: 11, weight: isEditing ? .bold : .regular))
                    .foregroundStyle(isEditing ? Theme.electricAzure : .secondary)
                }
                .toggleStyle(.button)
                .clipShape(RoundedRectangle(cornerRadius: 6))

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

                // RFC 5737 IP Anonymization Toggle
                Button(action: { isAnonymized.toggle() }) {
                    HStack(spacing: 5) {
                        Image(systemName: isAnonymized ? "eye.slash.fill" : "eye.slash")
                        Text(isAnonymized ? "IPs Anonymized" : "Anonymize IPs")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(isAnonymized ? Theme.neonCyan.opacity(0.2) : Color.primary.opacity(0.05))
                    .foregroundStyle(isAnonymized ? Theme.neonCyan : Color.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Anonymize public IPv4/IPv6 addresses into RFC 5737 documentation ranges")

                // Redact Secrets Button
                Button(action: { isRedacted.toggle() }) {
                    HStack(spacing: 5) {
                        Image(systemName: isRedacted ? "lock.shield.fill" : "lock.shield")
                        Text(isRedacted ? "Secrets Masked" : "Redact Secrets")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
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
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.02))

            if let msg = toastMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.signalEmerald)
                    Text(msg)
                        .font(Theme.monoText(11, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
                .background(Theme.signalEmerald.opacity(0.1))
            }

            Divider()

            // Main Editor & AST Breakdown
            HSplitView {
                // Code Viewer / Editor Area
                ZStack {
                    if isEditing {
                        TextEditor(text: $configText)
                            .font(Theme.monoText(12))
                            .padding(12)
                            .background(Color.black.opacity(0.45))
                    } else {
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

                    if isTargetedForDrop {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.neonCyan, lineWidth: 2)
                            .background(Theme.neonCyan.opacity(0.08))
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "arrow.down.doc.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(Theme.neonCyan)
                                    Text("Drop configuration file here to import")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.primary)
                                }
                            )
                    }
                }
                .frame(minWidth: 500)
                .onDrop(of: [UTType.fileURL, UTType.plainText], isTargeted: $isTargetedForDrop) { providers in
                    handleDrop(providers: providers)
                }

                // Structured Inspector Side Panel
                VStack(alignment: .leading, spacing: 12) {
                    Text("EXTRACTED TOPOLOGY INTELLIGENCE")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
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
                                    Text("Domain")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(parsedAST.domainName ?? "N/A")
                                        .font(Theme.monoText(11))
                                        .foregroundStyle(.primary)
                                }
                                HStack {
                                    Text("Vendor Engine")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(parsedAST.vendor.rawValue)
                                        .font(Theme.monoText(11, weight: .bold))
                                        .foregroundStyle(Theme.electricAzure)
                                }
                            }
                            .modifier(EngineeringCardModifier(padding: 10))

                            // Object Groups Card (NEW)
                            if !parsedAST.objectGroups.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "rectangle.3.group")
                                            .foregroundStyle(Theme.neonCyan)
                                        Text("Object-Groups (\(parsedAST.objectGroups.count))")
                                            .font(.system(size: 12, weight: .bold))
                                        Spacer()
                                    }
                                    ForEach(parsedAST.objectGroups) { og in
                                        HStack {
                                            Text(og.name)
                                                .font(Theme.monoText(11, weight: .bold))
                                            Spacer()
                                            Text("\(og.type.rawValue) (\(og.members.count) items)")
                                                .font(Theme.monoText(10))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                                .modifier(EngineeringCardModifier(padding: 10))
                            }

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
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(intf.name)
                                                .font(Theme.monoText(11, weight: .bold))
                                            Spacer()
                                            if intf.isShutdown {
                                                Text("ADMIN DOWN")
                                                    .font(Theme.monoText(9, weight: .bold))
                                                    .foregroundStyle(Theme.pulseCrimson)
                                            } else {
                                                Text("UP")
                                                    .font(Theme.monoText(9, weight: .bold))
                                                    .foregroundStyle(Theme.signalEmerald)
                                            }
                                        }

                                        if let ip = intf.ipAddress {
                                            HStack(spacing: 4) {
                                                Text(ip)
                                                    .foregroundStyle(Theme.neonCyan)
                                                if let mask = intf.subnetMask {
                                                    Text("/ \(mask)")
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            .font(Theme.monoText(10))
                                        }

                                        if let desc = intf.description {
                                            Text(desc)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    Divider()
                                }
                            }
                            .modifier(EngineeringCardModifier(padding: 10))

                            // Routing Summary Card
                            let routing = parser.extractRouting(from: parsedAST)
                            if !routing.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "point.3.connected.trianglepath.dotted")
                                            .foregroundStyle(Theme.electricAzure)
                                        Text("Routing Protocols (\(routing.count))")
                                            .font(.system(size: 12, weight: .bold))
                                        Spacer()
                                    }

                                    ForEach(routing) { proto in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(proto.routingProtocol.rawValue)
                                                    .font(Theme.monoText(11, weight: .bold))
                                                    .foregroundStyle(Theme.electricAzure)
                                                Spacer()
                                                if let asNum = proto.autonomousSystem {
                                                    Text("AS \(asNum)")
                                                        .font(Theme.monoText(10))
                                                        .foregroundStyle(.secondary)
                                                }
                                            }

                                            if let rId = proto.routerId {
                                                Text("Router-ID: \(rId)")
                                                    .font(Theme.monoText(10))
                                                    .foregroundStyle(.secondary)
                                            }

                                            if !proto.neighbors.isEmpty {
                                                Text("Peers: \(proto.neighbors.joined(separator: ", "))")
                                                    .font(Theme.monoText(10))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                        Divider()
                                    }
                                }
                                .modifier(EngineeringCardModifier(padding: 10))
                            }

                            // ACL Summary Card
                            let acls = parser.extractACLs(from: parsedAST)
                            if !acls.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "shield.checkered")
                                            .foregroundStyle(Theme.solarAmber)
                                        Text("Security ACLs (\(acls.count))")
                                            .font(.system(size: 12, weight: .bold))
                                        Spacer()
                                    }

                                    ForEach(acls) { acl in
                                        HStack {
                                            Text(acl.name)
                                                .font(Theme.monoText(11, weight: .bold))
                                            Spacer()
                                            Text("\(acl.rules.count) rules")
                                                .font(Theme.monoText(10))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                                .modifier(EngineeringCardModifier(padding: 10))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 16)
                    }
                }
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
                .background(Color.primary.opacity(0.015))
            }

            // Bottom Status Strip
            HStack(spacing: 16) {
                Text("\(parsedAST.allLines.count) Lines")
                    .font(Theme.monoText(11))
                    .foregroundStyle(.secondary)
                Text("\(parsedAST.blocks.count) Syntactic Blocks")
                    .font(Theme.monoText(11))
                    .foregroundStyle(.secondary)

                if isRedacted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                        Text("Active Redaction: 12 Secret Patterns Masked")
                    }
                    .font(Theme.monoText(11, weight: .bold))
                    .foregroundStyle(Theme.signalEmerald)
                }

                if isAnonymized {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.slash.fill")
                        Text("RFC 5737 Topology Anonymized")
                    }
                    .font(Theme.monoText(11, weight: .bold))
                    .foregroundStyle(Theme.neonCyan)
                }

                Spacer()

                Text("Universal Grammar Parser: Cisco • Junos • Fortinet • PAN-OS • Arista • MikroTik • Huawei")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
        }
    }

    private func resetToggles() {
        isRedacted = false
        isAnonymized = false
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
            Text(String(format: "%3d", line.lineNumber))
                .font(Theme.monoText(11))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .frame(width: 32, alignment: .trailing)

            renderSyntaxText(line.rawText)
                .font(Theme.monoText(12))

            Spacer()
        }
    }

    @ViewBuilder
    private func renderSyntaxText(_ text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("!") || trimmed.hasPrefix("#") || trimmed.hasPrefix("/*") {
            Text(text).foregroundStyle(Color.secondary.opacity(0.7))
        } else if text.contains("[REDACTED_") {
            HStack(spacing: 2) {
                Text(text.components(separatedBy: "[REDACTED_")[0])
                    .foregroundStyle(.primary)
                Text("[REDACTED_SECRET]")
                    .font(Theme.monoText(10, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.solarAmber.opacity(0.25))
                    .foregroundStyle(Theme.solarAmber)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        } else if trimmed.hasPrefix("interface ") || trimmed.hasPrefix("router ") || trimmed.hasPrefix("ip access-list") || trimmed.hasPrefix("vlan ") || trimmed.hasPrefix("config ") {
            Text(text).foregroundStyle(Theme.neonCyan).bold()
        } else if trimmed.hasPrefix("permit ") || trimmed.hasPrefix("set allowaccess") {
            Text(text).foregroundStyle(Theme.signalEmerald)
        } else if trimmed.hasPrefix("deny ") || trimmed.hasPrefix("shutdown") {
            Text(text).foregroundStyle(Theme.pulseCrimson)
        } else {
            Text(text).foregroundStyle(Color(nsColor: .textColor).opacity(0.9))
        }
    }

    private func copyConfig() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(activeProcessedText, forType: .string)
        triggerToast("Configuration copied to clipboard")
    }

    private func openFileFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Select Network Configuration File"
        panel.allowedContentTypes = [.plainText, .text, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                configText = content
                resetToggles()
                triggerToast("Loaded: \(url.lastPathComponent)")
            }
        }
    }

    private func saveConfigToDisk() {
        let panel = NSSavePanel()
        panel.title = "Save Network Configuration"
        panel.nameFieldStringValue = (parsedAST.hostname ?? "device_config") + ".cfg"
        panel.allowedContentTypes = [.plainText]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try activeProcessedText.write(to: url, atomically: true, encoding: .utf8)
                triggerToast("Saved to \(url.lastPathComponent)")
            } catch {
                triggerToast("Save failed: \(error.localizedDescription)")
            }
        }
    }

    private func exportJSONAST() {
        let panel = NSSavePanel()
        panel.title = "Export AST Hierarchy"
        panel.nameFieldStringValue = (parsedAST.hostname ?? "device_ast") + "_ast.json"
        panel.allowedContentTypes = [.json]

        let intfs = parser.extractInterfaces(from: parsedAST)
        let routing = parser.extractRouting(from: parsedAST)
        let acls = parser.extractACLs(from: parsedAST)

        let dict: [String: Any] = [
            "hostname": parsedAST.hostname ?? "",
            "domainName": parsedAST.domainName ?? "",
            "vendor": parsedAST.vendor.rawValue,
            "interfacesCount": intfs.count,
            "routingProtocolsCount": routing.count,
            "aclsCount": acls.count,
            "objectGroups": parsedAST.objectGroups.map { ["name": $0.name, "type": $0.type.rawValue, "members": $0.members] },
            "interfaces": intfs.map { ["name": $0.name, "ip": $0.ipAddress ?? "", "mask": $0.subnetMask ?? "", "shutdown": $0.isShutdown] }
        ]

        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: url)
                triggerToast("Exported AST to \(url.lastPathComponent)")
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url, let content = try? String(contentsOf: url, encoding: .utf8) else { return }
                    DispatchQueue.main.async {
                        self.configText = content
                        self.resetToggles()
                        self.triggerToast("Dropped: \(url.lastPathComponent)")
                    }
                }
                return true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                _ = provider.loadObject(ofClass: String.self) { str, _ in
                    guard let str = str, !str.isEmpty else { return }
                    DispatchQueue.main.async {
                        self.configText = str
                        self.resetToggles()
                        self.triggerToast("Imported text snippet")
                    }
                }
                return true
            }
        }
        return false
    }

    private func triggerToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                if toastMessage == msg { toastMessage = nil }
            }
        }
    }
}

// MARK: - 2. Structural Diff Tab & Semantic Rollback

struct StructuralDiffTab: View {
    var activeConfigText: String?

    @State private var baselineText: String = sampleBaselineConfig
    @State private var targetText: String = sampleTargetConfig
    @State private var isUnified: Bool = false
    @State private var showRollbackDrawer: Bool = false
    @State private var toastMessage: String? = nil

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

                // Preset Scenarios
                Menu {
                    Button("Security Audit Drift Preset") {
                        baselineText = sampleBaselineConfig
                        targetText = sampleTargetConfig
                    }
                    if let act = activeConfigText, !act.isEmpty {
                        Button("Compare Active Config vs Baseline") {
                            targetText = act
                        }
                    }
                    Button("Swap Baseline & Target") {
                        let tmp = baselineText
                        baselineText = targetText
                        targetText = tmp
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Diff Presets")
                        Image(systemName: "chevron.down").font(.system(size: 8))
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)

                // Load from Files
                Button("Load Baseline...") {
                    loadFile(into: $baselineText, label: "Baseline")
                }
                .font(.system(size: 11))

                Button("Load Target...") {
                    loadFile(into: $targetText, label: "Target")
                }
                .font(.system(size: 11))

                // Rollback Script Button
                Button(action: { showRollbackDrawer.toggle() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                        Text("Rollback CLI (\(report.rollbackScript.rollbackCommands.count))")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(showRollbackDrawer ? Theme.neonCyan.opacity(0.25) : Theme.neonCyan.opacity(0.12))
                    .foregroundStyle(Theme.neonCyan)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Picker("View Mode", selection: $isUnified) {
                    Text("Side-by-Side").tag(false)
                    Text("Unified").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.02))

            if let msg = toastMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.signalEmerald)
                    Text(msg).font(Theme.monoText(11, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
                .background(Theme.signalEmerald.opacity(0.1))
            }

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

            // Rollback Script Drawer (if active)
            if showRollbackDrawer {
                rollbackScriptPanel
                Divider()
            }

            // Diff Viewer: Side-by-Side or Unified
            if isUnified {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(report.diffLines) { diff in
                            diffLineRow(diff: diff)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(Color.black.opacity(0.5))
            } else {
                HSplitView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("BASELINE CONFIGURATION")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.03))

                        Divider()

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(report.diffLines.filter { $0.kind != .added }) { diff in
                                    diffLineRow(diff: diff)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .background(Color.black.opacity(0.5))
                    }
                    .frame(minWidth: 350)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("TARGET CONFIGURATION")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.03))

                        Divider()

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(report.diffLines.filter { $0.kind != .removed }) { diff in
                                    diffLineRow(diff: diff)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .background(Color.black.opacity(0.5))
                    }
                    .frame(minWidth: 350)
                }
            }
        }
    }

    private var rollbackScriptPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundStyle(Theme.neonCyan)
                    Text("AUTOMATED ROLLBACK & MIGRATION SCRIPT")
                        .font(Theme.monoText(11, weight: .bold))
                }

                Spacer()

                Button("Copy Rollback Commands") {
                    let cmd = report.rollbackScript.rollbackCommands.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd, forType: .string)
                    triggerToast("Rollback script copied to clipboard")
                }
                .font(.system(size: 11, weight: .semibold))

                Button("Dismiss") {
                    showRollbackDrawer = false
                }
                .font(.system(size: 11))
            }

            if !report.rollbackScript.safetyWarnings.isEmpty {
                ForEach(report.rollbackScript.safetyWarnings, id: \.self) { warn in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.solarAmber)
                        Text(warn)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.solarAmber)
                    }
                    .padding(6)
                    .background(Theme.solarAmber.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(report.rollbackScript.rollbackCommands, id: \.self) { cmd in
                        Text(cmd)
                            .font(Theme.monoText(11))
                            .foregroundStyle(cmd.hasPrefix("no ") ? Theme.pulseCrimson : Theme.neonCyan)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 140)
            .background(Color.black.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(14)
        .background(Color.primary.opacity(0.03))
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
        case .reordered: return Theme.electricAzure
        case .unchanged: return .secondary
        }
    }

    private func diffLineRow(diff: DiffLine) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(diff.oldLineNumber.map { String(format: "%3d", $0) } ?? "   ")
                    .font(Theme.monoText(10))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                Text(diff.newLineNumber.map { String(format: "%3d", $0) } ?? "   ")
                    .font(Theme.monoText(10))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            }
            .frame(width: 60)

            switch diff.kind {
            case .added:
                Text("+").font(Theme.monoText(12, weight: .bold)).foregroundStyle(Theme.signalEmerald)
            case .removed:
                Text("-").font(Theme.monoText(12, weight: .bold)).foregroundStyle(Theme.pulseCrimson)
            case .modified:
                Text("~").font(Theme.monoText(12, weight: .bold)).foregroundStyle(Theme.solarAmber)
            case .reordered:
                Text("^").font(Theme.monoText(12, weight: .bold)).foregroundStyle(Theme.electricAzure)
            case .unchanged:
                Text(" ").font(Theme.monoText(12))
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
        case .reordered: return Theme.electricAzure
        case .unchanged: return Color(nsColor: .textColor).opacity(0.85)
        }
    }

    private func backgroundColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .added: return Theme.signalEmerald.opacity(0.1)
        case .removed: return Theme.pulseCrimson.opacity(0.1)
        case .modified: return Theme.solarAmber.opacity(0.08)
        case .reordered: return Theme.electricAzure.opacity(0.1)
        case .unchanged: return Color.clear
        }
    }

    private func loadFile(into binding: Binding<String>, label: String) {
        let panel = NSOpenPanel()
        panel.title = "Select \(label) File"
        panel.allowedContentTypes = [.plainText, .text]
        if panel.runModal() == .OK, let url = panel.url {
            if let str = try? String(contentsOf: url, encoding: .utf8) {
                binding.wrappedValue = str
                triggerToast("Loaded \(label): \(url.lastPathComponent)")
            }
        }
    }

    private func triggerToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                if toastMessage == msg { toastMessage = nil }
            }
        }
    }
}

// MARK: - 3. ACL Simulator & Linter Tab

struct ACLSimulatorTab: View {
    var currentConfigText: String?

    @State private var srcIP: String = "192.168.1.50"
    @State private var dstIP: String = "10.0.0.2"
    @State private var protocolType: ACLProtocol = .tcp
    @State private var dstPortString: String = "443"
    @State private var isEstablished: Bool = false
    @State private var selectedACLName: String = "INET_INBOUND_FILTER"

    private let analyzer = ACLAnalyzer()
    private let parser = ConfigParser()

    var discoveredACLs: [ACLConfig] {
        if let txt = currentConfigText, !txt.isEmpty {
            let ast = parser.parse(text: txt)
            let acls = parser.extractACLs(from: ast)
            if !acls.isEmpty { return acls }
        }
        return [sampleDefaultACL, samplePCIStrictACL]
    }

    var activeACL: ACLConfig {
        discoveredACLs.first(where: { $0.name == selectedACLName }) ?? discoveredACLs.first ?? sampleDefaultACL
    }

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
        let ast = parser.parse(text: currentConfigText ?? "")
        return analyzer.evaluate(flow: flow, against: activeACL, objectGroups: ast.objectGroups)
    }

    var shadowedFindings: [ShadowedRuleFinding] {
        analyzer.detectShadowedRules(in: activeACL)
    }

    var body: some View {
        HSplitView {
            // Flow Simulator Form Side
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("5-TUPLE FLOW SIMULATOR")
                                .font(Theme.monoText(11, weight: .bold))
                                .foregroundStyle(Theme.neonCyan)
                            Spacer()
                            // ACL Selector Picker
                            Picker("Active ACL", selection: $selectedACLName) {
                                ForEach(discoveredACLs) { acl in
                                    Text(acl.name).tag(acl.name)
                                }
                            }
                            .frame(width: 200)
                        }
                        Text("Simulate deterministic packet traversal against '\(activeACL.name)'")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    // Source IP Field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Source IPv4 / IPv6").font(.system(size: 11, weight: .semibold))
                        TextField("e.g. 192.168.1.50", text: $srcIP)
                            .font(Theme.monoText(12))
                            .textFieldStyle(.roundedBorder)
                    }

                    // Destination IP Field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Destination IPv4 / IPv6").font(.system(size: 11, weight: .semibold))
                        TextField("e.g. 10.0.0.2", text: $dstIP)
                            .font(Theme.monoText(12))
                            .textFieldStyle(.roundedBorder)
                    }

                    // Protocol Selection
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Layer 4 Protocol").font(.system(size: 11, weight: .semibold))
                        Picker("", selection: $protocolType) {
                            Text("TCP").tag(ACLProtocol.tcp)
                            Text("UDP").tag(ACLProtocol.udp)
                            Text("ICMP").tag(ACLProtocol.icmp)
                            Text("IP (Any)").tag(ACLProtocol.ip)
                        }
                        .pickerStyle(.segmented)
                    }

                    // Destination Port
                    if protocolType == .tcp || protocolType == .udp {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Destination Port").font(.system(size: 11, weight: .semibold))
                            TextField("e.g. 443, 80, 22", text: $dstPortString)
                                .font(Theme.monoText(12))
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    // TCP Established Flag
                    if protocolType == .tcp {
                        Toggle(isOn: $isEstablished) {
                            Text("TCP Established (ACK / RST Flags Set)")
                                .font(.system(size: 11))
                        }
                    }

                    Divider()

                    // Evaluation Result Badge
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("SIMULATION VERDICT")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(evaluationResult.action.rawValue)
                                .font(Theme.monoText(14, weight: .heavy))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(evaluationResult.action == .permit ? Theme.signalEmerald.opacity(0.2) : Theme.pulseCrimson.opacity(0.2))
                                .foregroundStyle(evaluationResult.action == .permit ? Theme.signalEmerald : Theme.pulseCrimson)
                                .clipShape(Capsule())
                        }

                        if let matched = evaluationResult.matchedRule {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Matched Rule Seq \(matched.sequence):")
                                    .font(Theme.monoText(11, weight: .bold))
                                Text(matched.rawText)
                                    .font(Theme.monoText(11))
                                    .foregroundStyle(Theme.neonCyan)
                                if let rem = matched.remark {
                                    Text("Remark: \(rem)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            Text("Implicit Deny (End of ACL hit)")
                                .font(Theme.monoText(11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .modifier(EngineeringCardModifier(padding: 12))
                }
                .padding(16)
            }
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 440)

            // Rules & Linter Side Panel
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("ACTIVE ACL RULES (\(activeACL.rules.count))")
                            .font(Theme.monoText(11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(activeACL.isExtended ? "Extended ACL" : "Standard ACL")
                            .font(Theme.monoText(10))
                            .foregroundStyle(.tertiary)
                    }

                    ForEach(activeACL.rules) { rule in
                        let isMatched = evaluationResult.matchedRule?.sequence == rule.sequence
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(rule.action.rawValue)
                                    .font(Theme.monoText(10, weight: .bold))
                                    .foregroundStyle(rule.action == .permit ? Theme.signalEmerald : Theme.pulseCrimson)
                                Text("Seq \(rule.sequence)")
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
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.solarAmber)
                                Text("Linter Findings (\(shadowedFindings.count))")
                                    .font(.system(size: 12, weight: .bold))
                            }

                            ForEach(shadowedFindings) { f in
                                linterRow(finding: f)
                            }
                        }
                        .modifier(EngineeringCardModifier(padding: 10))
                    }
                }
                .padding(16)
            }
            .frame(minWidth: 380)
            .background(Color.primary.opacity(0.015))
        }
    }

    @ViewBuilder
    private func linterRow(finding: ShadowedRuleFinding) -> some View {
        let isRisk = finding.kind == .securityRisk
        let tagColor = isRisk ? Theme.pulseCrimson : Theme.solarAmber
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(finding.kind.rawValue)
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(tagColor)
                Spacer()
                Text("Rule \(finding.flaggedRule.sequence)")
                    .font(Theme.monoText(10))
                    .foregroundStyle(.secondary)
            }
            Text(finding.explanation)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - 4. CLI Output Parser Tab (ParserKit 2.0)

struct CLIParserTab: View {
    var state: AppState

    @State private var inputText: String = sampleIPIntBriefCLI
    @State private var selectedCommand: CommandFamily? = nil
    @State private var filterQuery: String = ""
    @State private var toastMessage: String? = nil

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

                    // Preset Menu with all 10 commands
                    Menu {
                        Section("Interface & Layer 2") {
                            Button("show ip interface brief") { inputText = sampleIPIntBriefCLI; selectedCommand = nil }
                            Button("show interfaces (detail)") { inputText = sampleShowInterfacesCLI; selectedCommand = nil }
                            Button("show mac address-table") { inputText = sampleShowMacCLI; selectedCommand = nil }
                            Button("show vlan brief") { inputText = sampleShowVLANCLI; selectedCommand = nil }
                        }
                        Section("Routing & Neighbors") {
                            Button("show ip route") { inputText = sampleShowIPRouteCLI; selectedCommand = nil }
                            Button("show ip bgp summary") { inputText = sampleShowBGPCLI; selectedCommand = nil }
                            Button("show ip ospf neighbor") { inputText = sampleShowOSPFCLI; selectedCommand = nil }
                            Button("show cdp / lldp neighbors") { inputText = sampleShowCDPCLI; selectedCommand = nil }
                            Button("show arp") { inputText = sampleShowARPCLI; selectedCommand = nil }
                        }
                        Section("System & Hardware") {
                            Button("show version") { inputText = sampleShowVersionCLI; selectedCommand = nil }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "terminal")
                            Text("Sample Commands")
                            Image(systemName: "chevron.down").font(.system(size: 8))
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .menuStyle(.borderlessButton)

                    Button("Clear") { inputText = "" }
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.02))

                Divider()

                TextEditor(text: $inputText)
                    .font(Theme.monoText(11))
                    .padding(8)
                    .background(Color.black.opacity(0.45))
            }
            .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)
            .onAppear {
                if let inc = state.cliParserInputText, !inc.isEmpty {
                    inputText = inc
                    state.cliParserInputText = nil
                }
            }

            // Parsed Table Presentation Side
            VStack(spacing: 0) {
                // Detected Command & Export Bar
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

                        Spacer()

                        // Export to CSV
                        Button(action: { exportCSV(result: res) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "tablecells")
                                Text("CSV")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("Export structured results as CSV")

                        // Export to JSON
                        Button(action: { exportJSON(result: res) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "curlybraces")
                                Text("JSON")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("Export structured results as JSON")
                    } else {
                        Text("Awaiting Output...")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

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
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.03))

                if let msg = toastMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.signalEmerald)
                        Text(msg).font(Theme.monoText(11, weight: .bold))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 3)
                    .background(Theme.signalEmerald.opacity(0.1))
                }

                Divider()

                // Render Table
                if let (_, result) = parsedResult {
                    ScrollView([.horizontal, .vertical]) {
                        renderStructuredResultTable(result)
                            .padding(14)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "tablecells.badge.ellipsis")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("Paste raw terminal output or select a sample command from the toolbar.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 520)
            .background(Color.primary.opacity(0.01))
        }
    }

    @ViewBuilder
    private func renderStructuredResultTable(_ result: StructuredResult) -> some View {
        switch result {
        case .ipInterfaceBrief(let entries):
            VStack(spacing: 6) {
                HStack {
                    Text("INTERFACE").frame(width: 150, alignment: .leading)
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
                            .frame(width: 150, alignment: .leading)
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

        case .version(let v):
            VStack(alignment: .leading, spacing: 10) {
                Text("HARDWARE & OS DETAILS")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Hardware Platform:").foregroundStyle(.secondary)
                        Text(v.hardware).bold()
                    }
                    GridRow {
                        Text("OS Version:").foregroundStyle(.secondary)
                        Text(v.osVersion).font(Theme.monoText(11, weight: .bold)).foregroundStyle(Theme.neonCyan)
                    }
                    GridRow {
                        Text("System Uptime:").foregroundStyle(.secondary)
                        Text(v.uptime)
                    }
                    if let ser = v.serialNumber {
                        GridRow {
                            Text("Serial Number:").foregroundStyle(.secondary)
                            Text(ser).font(Theme.monoText(11))
                        }
                    }
                    if let img = v.systemImage {
                        GridRow {
                            Text("Boot Image:").foregroundStyle(.secondary)
                            Text(img).font(Theme.monoText(10))
                        }
                    }
                }
                .modifier(EngineeringCardModifier(padding: 14))
            }

        case .vlans(let entries):
            VStack(spacing: 6) {
                HStack {
                    Text("VLAN ID").frame(width: 70, alignment: .leading)
                    Text("NAME").frame(width: 160, alignment: .leading)
                    Text("STATUS").frame(width: 90, alignment: .leading)
                    Text("PORTS").frame(width: 250, alignment: .leading)
                    Spacer()
                }
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(.secondary)

                Divider()

                ForEach(entries.filter { filterQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(filterQuery) || String($0.vlanId).contains(filterQuery) }) { entry in
                    HStack {
                        Text("\(entry.vlanId)")
                            .font(Theme.monoText(11, weight: .bold))
                            .frame(width: 70, alignment: .leading)
                        Text(entry.name)
                            .font(Theme.monoText(11))
                            .frame(width: 160, alignment: .leading)
                        Text(entry.status)
                            .font(Theme.monoText(10))
                            .foregroundStyle(entry.status.lowercased() == "active" ? Theme.signalEmerald : .secondary)
                            .frame(width: 90, alignment: .leading)
                        Text(entry.ports.joined(separator: ", "))
                            .font(Theme.monoText(10))
                            .frame(width: 250, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }

        case .ospfNeighbors(let entries):
            VStack(spacing: 6) {
                HStack {
                    Text("NEIGHBOR ID").frame(width: 120, alignment: .leading)
                    Text("PRI").frame(width: 40, alignment: .center)
                    Text("STATE").frame(width: 130, alignment: .leading)
                    Text("DEAD TIME").frame(width: 90, alignment: .leading)
                    Text("ADDRESS").frame(width: 120, alignment: .leading)
                    Text("INTERFACE").frame(width: 140, alignment: .leading)
                    Spacer()
                }
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(.secondary)

                Divider()

                ForEach(entries.filter { filterQuery.isEmpty || $0.neighborId.contains(filterQuery) || $0.address.contains(filterQuery) }) { entry in
                    HStack {
                        Text(entry.neighborId)
                            .font(Theme.monoText(11, weight: .bold))
                            .foregroundStyle(Theme.neonCyan)
                            .frame(width: 120, alignment: .leading)
                        Text("\(entry.priority)")
                            .font(Theme.monoText(10))
                            .frame(width: 40, alignment: .center)
                        Text(entry.state)
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(entry.state.contains("FULL") ? Theme.signalEmerald : Theme.solarAmber)
                            .frame(width: 130, alignment: .leading)
                        Text(entry.deadTime)
                            .font(Theme.monoText(10))
                            .frame(width: 90, alignment: .leading)
                        Text(entry.address)
                            .font(Theme.monoText(11))
                            .frame(width: 120, alignment: .leading)
                        Text(entry.interface)
                            .font(Theme.monoText(11))
                            .frame(width: 140, alignment: .leading)
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
                            Text(intf.name).font(Theme.monoText(12, weight: .bold))
                            Spacer()
                            Text(intf.adminState).font(Theme.monoText(10))
                        }
                        if let mac = intf.macAddress {
                            Text("MAC: \(mac)").font(Theme.monoText(10)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.02))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

        case .routes(let entries):
            VStack(spacing: 6) {
                HStack {
                    Text("PROTO").frame(width: 60, alignment: .leading)
                    Text("PREFIX").frame(width: 150, alignment: .leading)
                    Text("NEXT HOP").frame(width: 140, alignment: .leading)
                    Text("INTERFACE").frame(width: 140, alignment: .leading)
                    Spacer()
                }
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(.secondary)

                Divider()

                ForEach(entries) { r in
                    HStack {
                        Text(r.protocolCode).font(Theme.monoText(10, weight: .bold)).frame(width: 60, alignment: .leading)
                        Text(r.prefix).font(Theme.monoText(11)).frame(width: 150, alignment: .leading)
                        Text(r.nextHop ?? "Direct").font(Theme.monoText(11)).frame(width: 140, alignment: .leading)
                        Text(r.outgoingInterface ?? "").font(Theme.monoText(11)).frame(width: 140, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 3)
                    Divider()
                }
            }

        case .macTable(let entries):
            VStack(spacing: 6) {
                HStack {
                    Text("VLAN").frame(width: 60, alignment: .leading)
                    Text("MAC ADDRESS").frame(width: 160, alignment: .leading)
                    Text("TYPE").frame(width: 100, alignment: .leading)
                    Text("PORT").frame(width: 120, alignment: .leading)
                    Spacer()
                }
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(.secondary)

                Divider()

                ForEach(entries) { m in
                    HStack {
                        Text("\(m.vlan)").font(Theme.monoText(11)).frame(width: 60, alignment: .leading)
                        Text(m.macAddress).font(Theme.monoText(11, weight: .bold)).frame(width: 160, alignment: .leading)
                        Text(m.type).font(Theme.monoText(10)).frame(width: 100, alignment: .leading)
                        Text(m.port).font(Theme.monoText(11)).frame(width: 120, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 3)
                    Divider()
                }
            }

        case .arp(let entries):
            VStack(spacing: 6) {
                ForEach(entries) { a in
                    HStack {
                        Text(a.ipAddress).font(Theme.monoText(11, weight: .bold)).frame(width: 140, alignment: .leading)
                        Text(a.macAddress).font(Theme.monoText(11)).frame(width: 160, alignment: .leading)
                        Text(a.interface).font(Theme.monoText(11)).frame(width: 140, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 3)
                    Divider()
                }
            }

        case .neighbors(let entries):
            VStack(spacing: 6) {
                ForEach(entries) { n in
                    HStack {
                        Text(n.deviceId).font(Theme.monoText(11, weight: .bold)).frame(width: 160, alignment: .leading)
                        Text(n.localInterface).font(Theme.monoText(11)).frame(width: 120, alignment: .leading)
                        Text(n.platform).font(Theme.monoText(10)).frame(width: 120, alignment: .leading)
                        Text(n.portId).font(Theme.monoText(11)).frame(width: 120, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 3)
                    Divider()
                }
            }

        case .bgpSummary(let entries):
            VStack(spacing: 6) {
                ForEach(entries) { b in
                    HStack {
                        Text(b.neighborIP).font(Theme.monoText(11, weight: .bold)).frame(width: 140, alignment: .leading)
                        Text("AS \(b.remoteAS)").font(Theme.monoText(11)).frame(width: 90, alignment: .leading)
                        Text(b.upDown).font(Theme.monoText(10)).frame(width: 90, alignment: .leading)
                        Text(b.stateOrPfxRcd).font(Theme.monoText(11, weight: .bold)).foregroundStyle(b.isEstablished ? Theme.signalEmerald : Theme.pulseCrimson).frame(width: 100, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 3)
                    Divider()
                }
            }
        }
    }

    private func statusPill(text: String, isUp: Bool) -> some View {
        Text(text)
            .font(Theme.monoText(9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isUp ? Theme.signalEmerald.opacity(0.18) : Theme.pulseCrimson.opacity(0.18))
            .foregroundStyle(isUp ? Theme.signalEmerald : Theme.pulseCrimson)
            .clipShape(Capsule())
    }

    private func exportCSV(result: StructuredResult) {
        let csv = result.toCSV()
        let panel = NSSavePanel()
        panel.title = "Export Parsed CLI Output to CSV"
        panel.nameFieldStringValue = "parsed_output.csv"
        panel.allowedContentTypes = [.commaSeparatedText]

        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
            triggerToast("Exported CSV to \(url.lastPathComponent)")
        }
    }

    private func exportJSON(result: StructuredResult) {
        let json = result.toJSON()
        let panel = NSSavePanel()
        panel.title = "Export Parsed CLI Output to JSON"
        panel.nameFieldStringValue = "parsed_output.json"
        panel.allowedContentTypes = [.json]

        if panel.runModal() == .OK, let url = panel.url {
            try? json.write(to: url, atomically: true, encoding: .utf8)
            triggerToast("Exported JSON to \(url.lastPathComponent)")
        }
    }

    private func triggerToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                if toastMessage == msg { toastMessage = nil }
            }
        }
    }
}

// MARK: - 5. CIS & STIG Compliance & Hardening Tab

struct ComplianceAuditorTab: View {
    var currentConfigText: String?

    @State private var filterSeverity: ComplianceSeverity? = nil
    @State private var onlyShowFailures: Bool = false
    @State private var toastMessage: String? = nil

    private let auditor = ComplianceAuditor()
    private let parser = ConfigParser()

    var auditReport: ComplianceAuditReport {
        let text = (currentConfigText?.isEmpty == false ? currentConfigText : nil) ?? sampleCiscoCoreConfig
        let ast = parser.parse(text: text)
        return auditor.audit(ast: ast, rawConfig: text)
    }

    var filteredFindings: [ComplianceFinding] {
        var res = auditReport.findings
        if onlyShowFailures {
            res = res.filter { !$0.isCompliant }
        }
        if let sev = filterSeverity {
            res = res.filter { $0.severity == sev }
        }
        return res
    }

    var scoreColor: Color {
        let s = auditReport.totalScore
        if s >= 85.0 { return Theme.signalEmerald }
        if s >= 65.0 { return Theme.solarAmber }
        return Theme.pulseCrimson
    }

    var gradeText: String {
        let s = auditReport.totalScore
        if s >= 95.0 { return "A+" }
        if s >= 85.0 { return "A" }
        if s >= 75.0 { return "B" }
        if s >= 60.0 { return "C" }
        return "F"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Hardening Action Bar
            HStack(spacing: 12) {
                // Score Mini Widget
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 4)
                            .frame(width: 38, height: 38)
                        Circle()
                            .trim(from: 0, to: CGFloat(auditReport.totalScore / 100.0))
                            .stroke(scoreColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 38, height: 38)
                        Text(gradeText)
                            .font(Theme.monoText(11, weight: .black))
                            .foregroundStyle(scoreColor)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(String(format: "%.1f%%", auditReport.totalScore))
                                .font(Theme.monoText(14, weight: .bold))
                                .foregroundStyle(scoreColor)
                            Text("CIS HARDENING SCORE")
                                .font(Theme.monoText(9, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        Text("\(auditReport.passedRulesCount) Passed • \(auditReport.failedRulesCount) Non-Compliant")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Filter toggles
                Toggle("Failures Only", isOn: $onlyShowFailures)
                    .font(.system(size: 11))
                    .toggleStyle(.checkbox)

                // Severity Filter Pills
                HStack(spacing: 4) {
                    Button(action: { filterSeverity = nil }) {
                        Text("All (\(auditReport.findings.count))")
                            .font(.system(size: 10, weight: filterSeverity == nil ? .bold : .regular))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(filterSeverity == nil ? Theme.neonCyan.opacity(0.2) : Color.primary.opacity(0.04))
                            .foregroundStyle(filterSeverity == nil ? Theme.neonCyan : Color.secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    ForEach([ComplianceSeverity.critical, .high, .medium, .low], id: \.self) { sev in
                        let count = auditReport.findings.filter { $0.severity == sev }.count
                        Button(action: { filterSeverity = (filterSeverity == sev ? nil : sev) }) {
                            Text("\(sev.rawValue) (\(count))")
                                .font(.system(size: 10, weight: filterSeverity == sev ? .bold : .regular))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(filterSeverity == sev ? severityColor(sev).opacity(0.2) : Color.primary.opacity(0.04))
                                .foregroundStyle(filterSeverity == sev ? severityColor(sev) : Color.secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().frame(height: 18)

                // Copy Full Remediation Playbook Button
                Button(action: copyFullPlaybook) {
                    HStack(spacing: 5) {
                        Image(systemName: "terminal.fill")
                        Text("Copy Remediation Playbook")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.signalEmerald.opacity(0.18))
                    .foregroundStyle(Theme.signalEmerald)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                // Export Markdown Audit Report
                Button(action: exportMarkdownAudit) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                        Text("Export Audit (.md)")
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.02))

            if let msg = toastMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.signalEmerald)
                    Text(msg).font(Theme.monoText(11, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
                .background(Theme.signalEmerald.opacity(0.1))
            }

            Divider()

            // Findings ScrollView
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredFindings) { finding in
                        complianceFindingCard(finding)
                    }
                }
                .padding(20)
            }
            .background(Color.black.opacity(0.4))
        }
    }

    private func complianceFindingCard(_ finding: ComplianceFinding) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                // Pass/Fail icon
                Image(systemName: finding.isCompliant ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(finding.isCompliant ? Theme.signalEmerald : Theme.pulseCrimson)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(finding.ruleId)
                            .font(Theme.monoText(11, weight: .bold))
                            .foregroundStyle(Theme.electricAzure)
                        Text(finding.title)
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(finding.category)
                        .font(Theme.monoText(10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Severity Badge
                Text(finding.severity.rawValue)
                    .font(Theme.monoText(9, weight: .black))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(severityColor(finding.severity).opacity(0.2))
                    .foregroundStyle(severityColor(finding.severity))
                    .clipShape(Capsule())

                // Status Badge
                Text(finding.isCompliant ? "COMPLIANT" : "NON-COMPLIANT")
                    .font(Theme.monoText(9, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(finding.isCompliant ? Theme.signalEmerald.opacity(0.18) : Theme.pulseCrimson.opacity(0.18))
                    .foregroundStyle(finding.isCompliant ? Theme.signalEmerald : Theme.pulseCrimson)
                    .clipShape(Capsule())
            }

            Text(finding.rationale)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // Affected lines if any
            if !finding.affectedLines.isEmpty {
                HStack(spacing: 4) {
                    Text("Violating Lines:")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(finding.affectedLines.map { String($0) }.joined(separator: ", "))
                        .font(Theme.monoText(10))
                        .foregroundStyle(Theme.pulseCrimson)
                }
            }

            // Copyable Remediation Block
            if !finding.isCompliant && !finding.remediationCLI.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("REMEDIATION COMMANDS")
                            .font(Theme.monoText(9, weight: .bold))
                            .foregroundStyle(Theme.signalEmerald)
                        Spacer()
                        Button("Copy Remediation") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(finding.remediationCLI, forType: .string)
                            triggerToast("Remediation copied to clipboard")
                        }
                        .font(.system(size: 10))
                    }

                    Text(finding.remediationCLI)
                        .font(Theme.monoText(11))
                        .foregroundStyle(Color(nsColor: .textColor).opacity(0.9))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(finding.isCompliant ? Color.primary.opacity(0.02) : Theme.pulseCrimson.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(finding.isCompliant ? Color.primary.opacity(0.06) : Theme.pulseCrimson.opacity(0.25), lineWidth: 1)
        )
    }

    private func severityColor(_ sev: ComplianceSeverity) -> Color {
        switch sev {
        case .critical: return Theme.pulseCrimson
        case .high:     return Theme.solarAmber
        case .medium:   return Theme.electricAzure
        case .low:      return Theme.signalEmerald
        case .info:     return .secondary
        }
    }

    private func copyFullPlaybook() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(auditReport.fullRemediationScript, forType: .string)
        triggerToast("Full Remediation Playbook copied to clipboard")
    }

    private func exportMarkdownAudit() {
        let panel = NSSavePanel()
        panel.title = "Export Compliance Audit Report"
        panel.nameFieldStringValue = (auditReport.deviceHostname ?? "device") + "_compliance_audit.md"
        panel.allowedContentTypes = [.plainText]

        var md = [
            "# CIS & STIG Security Hardening Audit Report",
            "- **Target Device**: `\(auditReport.deviceHostname ?? "Device")`",
            "- **Vendor Engine**: `\(auditReport.vendor.rawValue)`",
            "- **Audit Score**: `\(String(format: "%.1f", auditReport.totalScore))% (\(gradeText))`",
            "- **Passed Checks**: \(auditReport.passedRulesCount)",
            "- **Failed Checks**: \(auditReport.failedRulesCount)",
            "",
            "## Findings Breakdown",
            ""
        ]

        for f in auditReport.findings {
            let status = f.isCompliant ? "PASS" : "FAIL"
            md.append("### [\(status)] \(f.ruleId): \(f.title) (\(f.severity.rawValue))")
            md.append("- **Category**: \(f.category)")
            md.append("- **Rationale**: \(f.rationale)")
            if !f.isCompliant && !f.remediationCLI.isEmpty {
                md.append("```bash")
                md.append(f.remediationCLI)
                md.append("```")
            }
            md.append("")
        }

        md.append("## Complete Remediation Playbook")
        md.append("```bash")
        md.append(auditReport.fullRemediationScript)
        md.append("```")

        let reportStr = md.joined(separator: "\n")

        if panel.runModal() == .OK, let url = panel.url {
            try? reportStr.write(to: url, atomically: true, encoding: .utf8)
            triggerToast("Audit report exported: \(url.lastPathComponent)")
        }
    }

    private func triggerToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                if toastMessage == msg { toastMessage = nil }
            }
        }
    }
}

// MARK: - Multi-Vendor Preset Samples & Default Configurations

let sampleCiscoCoreConfig = """
! Cisco IOS-XE Core Switch Running Configuration
hostname core-switch-01
ip domain name nexwave.corp
!
service password-encryption
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
 exec-timeout 10 0
 stopbits 1
line vty 0 15
 transport input ssh
 exec-timeout 10 0
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

let sampleJunosConfig = """
system {
    host-name junos-core-01;
    domain-name nexwave.internal;
    services {
        ssh {
            protocol-version v2;
        }
    }
}
interfaces {
    ge-0/0/0 {
        unit 0 {
            family inet {
                address 10.10.1.1/30;
            }
        }
    }
    ge-0/0/1 {
        unit 0 {
            family inet {
                address 192.168.10.1/24;
            }
        }
    }
}
protocols {
    bgp {
        group EXTERNAL-PEERS {
            type external;
            peer-as 65000;
            neighbor 10.10.1.2;
        }
    }
}
"""

let sampleJunosSetConfig = """
set system host-name junos-edge-02
set system domain-name nexwave.internal
set system services ssh protocol-version v2
set interfaces ge-0/0/0 unit 0 family inet address 172.16.1.1/24
set protocols ospf area 0.0.0.0 interface ge-0/0/0.0
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

let sampleFortinetConfig = """
config system global
    set hostname FGT-EDGE-01
    set timezone 04
end
config system interface
    edit "port1"
        set vdom "root"
        set ip 198.51.100.1 255.255.255.0
        set allowaccess ping https ssh
        set type physical
    next
    edit "port2"
        set vdom "root"
        set ip 10.0.1.1 255.255.255.0
        set allowaccess ping
        set type physical
    next
end
config router bgp
    set as 65111
    set router-id 10.0.1.1
    config neighbor
        edit "198.51.100.254"
            set remote-as 65000
        next
    end
end
"""

let samplePaloAltoConfig = """
set deviceconfig system hostname PA-5220-BORDER
set deviceconfig system domain nexwave.corp
set network interface ethernet ethernet1/1 layer3 ip 203.0.113.2/29
set network interface ethernet ethernet1/2 layer3 ip 10.200.1.1/24
set network routing-options bgp router-id 10.200.1.1
set network routing-options bgp local-as 65300
"""

let sampleMikrotikConfig = """
/system identity
set name=MikroTik-CCR2004
/interface ethernet
set [ find default-name=ether1 ] name=ether1-WAN
set [ find default-name=ether2 ] name=ether2-LAN
/ip address
add address=192.168.88.1/24 interface=ether2-LAN network=192.168.88.0
add address=203.0.113.10/30 interface=ether1-WAN network=203.0.113.8
/routing bgp connection
add name=bgp-upstream local.role=ebgp remote.as=65000 remote.address=203.0.113.9 as=65400
"""

let sampleHuaweiConfig = """
#
sysname Huawei-CE6800
#
vlan batch 10 20 100
#
interface 10GE1/0/1
 description UPLINK-SPINE
 undo portswitch
 ip address 10.10.10.1 255.255.255.252
#
interface 10GE1/0/2
 description LEAF-ACCESS
 port link-type trunk
 port trunk allow-pass vlan 10 20
#
bgp 65500
 router-id 10.255.255.5
 peer 10.10.10.2 as-number 65501
#
return
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

let sampleDefaultACL = ACLConfig(
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

let samplePCIStrictACL = ACLConfig(
    name: "PCI_CDE_ISOLATION",
    isExtended: true,
    rules: [
        ACLRule(id: 10, sequence: 10, action: .permit, protocolType: .tcp, source: .subnet(network: "10.100.0.0", wildcard: "0.0.255.255"), destination: .host("10.200.1.10"), portOperator: .eq(443), remark: "PCI CDE Payment Gateway API", rawText: "10 permit tcp 10.100.0.0 0.0.255.255 host 10.200.1.10 eq 443"),
        ACLRule(id: 20, sequence: 20, action: .deny, protocolType: .any, source: .any, destination: .subnet(network: "10.200.0.0", wildcard: "0.0.255.255"), remark: "Strict Block to PCI Zone", rawText: "20 deny ip any 10.200.0.0 0.0.255.255"),
        ACLRule(id: 30, sequence: 30, action: .deny, protocolType: .any, source: .any, destination: .any, rawText: "30 deny ip any any")
    ]
)

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

let sampleShowVersionCLI = """
Cisco IOS XE Software, Version 17.06.03
Cisco IOS Software [Cupertino], Catalyst L3 Switch Software (CAT9K_IOSXE), Version 17.6.3, RELEASE SOFTWARE (fc4)
Technical Support: http://www.cisco.com/techsupport
Copyright (c) 1986-2022 by Cisco Systems, Inc.

core-switch-01 uptime is 42 weeks, 3 days, 14 hours, 22 minutes
Uptime for this control processor is 42 weeks, 3 days, 14 hours, 24 minutes
System returned to ROM by reload
System image file is "bootflash:cat9k_iosxe.17.06.03.SPA.bin"
Last reload reason: Reload Command

cisco C9300-48UXM (X86) processor with 16777216K/2097152K bytes of memory.
Processor board ID FOC2418ABCD
"""

let sampleShowVLANCLI = """
VLAN Name                             Status    Ports
---- -------------------------------- --------- -------------------------------
1    default                          active    Gi0/3, Gi0/4
10   MANAGEMENT                       active    Gi0/1, Gi0/2
20   CORP_USERS                       active    Gi0/5, Gi0/6, Gi0/7
100  SERVER_FARM                      active    Te1/1, Te1/2
"""

let sampleShowOSPFCLI = """
Neighbor ID     Pri   State           Dead Time   Address         Interface
10.255.255.1      1   FULL/BDR        00:00:34    10.0.0.2        GigabitEthernet0/0/0
10.255.255.2      1   FULL/DR         00:00:38    10.0.0.6        GigabitEthernet0/0/1
"""
