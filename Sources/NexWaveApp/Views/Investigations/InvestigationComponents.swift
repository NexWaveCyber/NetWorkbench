import SwiftUI
import UniformTypeIdentifiers
import InvestigationKit
import PersistenceKit

// MARK: - Incident KPI Metric Card

public struct IncidentMetricCard: View {
    public let title: String
    public let value: String
    public let subtitle: String
    public let tint: Color
    public let isAlert: Bool

    public init(
        title: String,
        value: String,
        subtitle: String = "",
        tint: Color = Theme.cyanPulse,
        isAlert: Bool = false
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.tint = tint
        self.isAlert = isAlert
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(value)
                .font(Theme.monoText(20, weight: .heavy))
                .foregroundStyle(isAlert ? Theme.crimsonCritical : tint)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(isAlert ? Theme.crimsonCritical.opacity(0.85) : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isAlert ? Theme.crimsonCritical.opacity(0.4) : tint.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Evidence Item Row

public struct EvidenceItemRow: View {
    public let item: EvidenceItem
    public let onInspect: () -> Void
    public let onDelete: () -> Void

    public init(
        item: EvidenceItem,
        onInspect: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.onInspect = onInspect
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(typeColor(item.evidenceType).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: item.evidenceType.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(typeColor(item.evidenceType))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.filename)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Text(item.evidenceType.displayName)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(typeColor(item.evidenceType).opacity(0.12))
                        .foregroundStyle(typeColor(item.evidenceType))
                        .clipShape(Capsule())

                    Spacer()

                    Text(ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file))
                        .font(Theme.monoText(11))
                        .foregroundStyle(.secondary)
                }

                if !item.title.isEmpty && item.title != item.filename {
                    Text(item.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text("SHA-256: \(item.sha256.prefix(16))...")
                        .font(Theme.monoText(10))
                        .foregroundStyle(.secondary.opacity(0.7))

                    Text("•")
                        .foregroundStyle(.secondary.opacity(0.5))

                    Text(item.sourceWorkbench)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Button(action: onInspect) {
                    Label("Inspect", systemImage: "eye.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 5))

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.crimsonCritical)
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func typeColor(_ t: EvidenceType) -> Color {
        switch t {
        case .pcap: return Theme.cyanPulse
        case .cliOutput: return Theme.electricAzure
        case .configDiff: return Theme.quantumViolet
        case .diagnosticProbe: return Theme.signalEmerald
        case .syslog: return Theme.solarAmber
        case .screenshot: return Color.pink
        case .genericFile: return Color.gray
        }
    }
}

// MARK: - Evidence Inspector Sheet

public struct EvidenceInspectorSheet: View {
    public let item: EvidenceItem
    public let onDismiss: () -> Void
    @State private var copiedToast = false

    public init(item: EvidenceItem, onDismiss: @escaping () -> Void) {
        self.item = item
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: item.evidenceType.iconName)
                            .foregroundStyle(Theme.cyanPulse)
                        Text(item.filename)
                            .font(.system(size: 15, weight: .bold))
                        Text(item.evidenceType.displayName)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.cyanPulse.opacity(0.12))
                            .foregroundStyle(Theme.cyanPulse)
                            .clipShape(Capsule())
                    }
                    Text(item.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Close") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Metadata Ledger
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SHA-256 CHECKSUM")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(item.sha256)
                            .font(Theme.monoText(10))
                            .lineLimit(1)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.sha256, forType: .string)
                            copiedToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedToast = false
                            }
                        } label: {
                            Image(systemName: copiedToast ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundStyle(copiedToast ? Theme.signalEmerald : Theme.cyanPulse)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 2) {
                    Text("FILE SIZE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file))
                        .font(Theme.monoText(11, weight: .semibold))
                }

                Divider()

                VStack(alignment: .leading, spacing: 2) {
                    Text("SOURCE WORKBENCH")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(item.sourceWorkbench)
                        .font(.system(size: 11))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content Canvas
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if item.evidenceType == .screenshot,
                       let data = Data(base64Encoded: item.content),
                       let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Text(item.content.isEmpty ? "[No Content Recorded]" : item.content)
                            .font(Theme.monoText(11))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    if !item.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("INVESTIGATOR NOTES")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(item.notes)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 10)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 720, height: 540)
    }
}

// MARK: - Hypothesis Card

public struct HypothesisCard: View {
    public let hypothesis: InvestigationHypothesis
    public let onStatusChange: (HypothesisStatus, String) -> Void
    public let onDelete: () -> Void

    @State private var showingEditSheet = false
    @State private var findingsText: String
    @State private var selectedStatus: HypothesisStatus

    public init(
        hypothesis: InvestigationHypothesis,
        onStatusChange: @escaping (HypothesisStatus, String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.hypothesis = hypothesis
        self.onStatusChange = onStatusChange
        self.onDelete = onDelete
        _findingsText = State(initialValue: hypothesis.findings)
        _selectedStatus = State(initialValue: hypothesis.status)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: hypothesis.status.iconName)
                        .foregroundStyle(statusColor(hypothesis.status))
                    Text(hypothesis.statement)
                        .font(.system(size: 13, weight: .semibold))
                }

                Spacer()

                Picker("", selection: $selectedStatus) {
                    ForEach(HypothesisStatus.allCases) { st in
                        Text(st.rawValue).tag(st)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .onChange(of: selectedStatus) { _, newStatus in
                    onStatusChange(newStatus, findingsText)
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.crimsonCritical)
                }
                .buttonStyle(.plain)
            }

            if !hypothesis.proposedTest.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text("Verification Test:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(hypothesis.proposedTest)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if !hypothesis.findings.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text("Findings:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor(hypothesis.status))
                    Text(hypothesis.findings)
                        .font(.system(size: 11))
                }
                .padding(8)
                .background(statusColor(hypothesis.status).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(statusColor(hypothesis.status).opacity(0.2), lineWidth: 1)
        )
    }

    private func statusColor(_ s: HypothesisStatus) -> Color {
        switch s {
        case .untested: return .secondary
        case .testing: return Theme.solarAmber
        case .confirmed: return Theme.signalEmerald
        case .refuted: return Theme.crimsonCritical
        }
    }
}

// MARK: - 5-Whys Tree Card

public struct FiveWhysTreeCard: View {
    public let rca: InvestigationRCA?
    public let onSave: (InvestigationRCA) -> Void

    @State private var problemStatement: String = ""
    @State private var why1: String = ""
    @State private var why2: String = ""
    @State private var why3: String = ""
    @State private var why4: String = ""
    @State private var why5: String = ""
    @State private var rootCause: String = ""
    @State private var preventativeStrategy: String = ""

    public init(rca: InvestigationRCA?, onSave: @escaping (InvestigationRCA) -> Void) {
        self.rca = rca
        self.onSave = onSave
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("THE 5-WHYS ROOT CAUSE ANALYSIS", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.cyanPulse)
                Spacer()
                Button("Save RCA") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("PROBLEM STATEMENT / OUTAGE SYMPTOM")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextField("E.g., Core BGP transit flapped, causing 14,000 clients to lose external access.", text: $problemStatement)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(spacing: 8) {
                whyRow(step: 1, text: $why1, prompt: "Why did client traffic drop? (e.g., BGP session went down)")
                whyRow(step: 2, text: $why2, prompt: "Why did BGP drop? (e.g., Hold timer expired due to dropped keepalives)")
                whyRow(step: 3, text: $why3, prompt: "Why were keepalives dropped? (e.g., Ingress port accumulated CRC errors)")
                whyRow(step: 4, text: $why4, prompt: "Why were there CRC errors? (e.g., Optical power dropped to -21.4 dBm)")
                whyRow(step: 5, text: $why5, prompt: "Root Cause Why? (e.g., Dirty and damaged LC patch cord connector)")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("IDENTIFIED ROOT CAUSE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.crimsonCritical)
                TextField("Definitive physical, software, or configuration root cause...", text: $rootCause)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("PREVENTATIVE HARDENING STRATEGY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.signalEmerald)
                TextField("Policy, monitoring, or architecture changes to prevent recurrence...", text: $preventativeStrategy)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.cyanPulse.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            if let rca = rca {
                problemStatement = rca.problemStatement
                why1 = rca.why1
                why2 = rca.why2
                why3 = rca.why3
                why4 = rca.why4
                why5 = rca.why5
                rootCause = rca.rootCause
                preventativeStrategy = rca.preventativeStrategy
            }
        }
    }

    private func whyRow(step: Int, text: Binding<String>, prompt: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.cyanPulse.opacity(0.18))
                    .frame(width: 24, height: 24)
                Text("\(step)")
                    .font(Theme.monoText(11, weight: .bold))
                    .foregroundStyle(Theme.cyanPulse)
            }

            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func saveChanges() {
        let updated = InvestigationRCA(
            id: rca?.id ?? UUID().uuidString,
            investigationId: rca?.investigationId ?? "",
            problemStatement: problemStatement,
            why1: why1,
            why2: why2,
            why3: why3,
            why4: why4,
            why5: why5,
            rootCause: rootCause,
            preventativeStrategy: preventativeStrategy
        )
        onSave(updated)
    }
}

// MARK: - Action Item Row

public struct ActionItemRow: View {
    public let item: InvestigationActionItem
    public let onToggle: (Bool) -> Void
    public let onDelete: () -> Void

    public init(
        item: InvestigationActionItem,
        onToggle: @escaping (Bool) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.onToggle = onToggle
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: 10) {
            Button {
                onToggle(!item.isCompleted)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(item.isCompleted ? Theme.signalEmerald : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: item.isCompleted ? .regular : .medium))
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                HStack(spacing: 8) {
                    Text(item.phase.displayName)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(phaseColor(item.phase).opacity(0.12))
                        .foregroundStyle(phaseColor(item.phase))
                        .clipShape(Capsule())

                    if let ass = item.assignee, !ass.isEmpty {
                        Text("Assignee: \(ass)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    if let comp = item.completedAt {
                        Text("•")
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text(comp.formatted(date: .abbreviated, time: .shortened))
                            .font(Theme.monoText(10))
                            .foregroundStyle(Theme.signalEmerald)
                    }
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.crimsonCritical)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func phaseColor(_ p: ActionPhase) -> Color {
        switch p {
        case .mitigation: return Theme.crimsonCritical
        case .verification: return Theme.cyanPulse
        case .postMortem: return Theme.quantumViolet
        }
    }
}

// MARK: - Add Evidence Sheet

public struct AddEvidenceSheet: View {
    public let investigationId: String
    public let onAdd: (String, String, EvidenceType, String, String) -> Void
    public let onDismiss: () -> Void

    @State private var title: String = ""
    @State private var filename: String = ""
    @State private var selectedType: EvidenceType = .cliOutput
    @State private var content: String = ""
    @State private var notes: String = ""

    public init(
        investigationId: String,
        onAdd: @escaping (String, String, EvidenceType, String, String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.investigationId = investigationId
        self.onAdd = onAdd
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Attach Forensic Evidence")
                .font(.system(size: 16, weight: .bold))

            HStack(spacing: 12) {
                TextField("Artifact Filename (e.g. show_ip_bgp.txt)", text: $filename)
                    .textFieldStyle(.roundedBorder)

                Button("Browse File...") {
                    browseFile()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            TextField("Descriptive Title (e.g. Core BGP Summary Before Flap)", text: $title)
                .textFieldStyle(.roundedBorder)

            Picker("Evidence Type", selection: $selectedType) {
                ForEach(EvidenceType.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("CONTENT / LOG PAYLOAD")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextEditor(text: $content)
                    .font(Theme.monoText(11))
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
            }

            TextField("Investigator Notes / Observations (Optional)", text: $notes)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.plain)

                Button("Attach Evidence") {
                    let fn = filename.isEmpty ? "evidence_\(Date().timeIntervalSince1970).txt" : filename
                    let t = title.isEmpty ? fn : title
                    onAdd(t, fn, selectedType, content, notes)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty && filename.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func browseFile() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select Evidence File"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        if openPanel.runModal() == .OK, let url = openPanel.url {
            filename = url.lastPathComponent
            if title.isEmpty {
                title = url.deletingPathExtension().lastPathComponent
            }
            if let data = try? Data(contentsOf: url) {
                if let str = String(data: data, encoding: .utf8) {
                    content = str
                } else {
                    content = data.base64EncodedString()
                    selectedType = .pcap
                }
            }
        }
    }
}

// MARK: - Post-Mortem Export Sheet

public struct PostMortemExportSheet: View {
    public let markdown: String
    public let html: String
    public let onDismiss: () -> Void

    @State private var selectedFormat = 0
    @State private var copiedToast = false

    public init(markdown: String, html: String, onDismiss: @escaping () -> Void) {
        self.markdown = markdown
        self.html = html
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $selectedFormat) {
                    Text("Markdown Post-Mortem").tag(0)
                    Text("Printable HTML / PDF").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Spacer()

                Button {
                    let text = selectedFormat == 0 ? markdown : html
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copiedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedToast = false
                    }
                } label: {
                    Label(copiedToast ? "Copied!" : "Copy", systemImage: copiedToast ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Button("Save to Disk...") {
                    saveFile()
                }
                .buttonStyle(.borderedProminent)

                Button("Close") { onDismiss() }
                    .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                Text(selectedFormat == 0 ? markdown : html)
                    .font(Theme.monoText(11))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .frame(width: 760, height: 560)
    }

    private func saveFile() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Incident Post-Mortem"
        if selectedFormat == 0 {
            savePanel.nameFieldStringValue = "incident_post_mortem.md"
            savePanel.allowedContentTypes = [.plainText]
        } else {
            savePanel.nameFieldStringValue = "incident_post_mortem.html"
            savePanel.allowedContentTypes = [.html]
        }
        if savePanel.runModal() == .OK, let url = savePanel.url {
            let content = selectedFormat == 0 ? markdown : html
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
