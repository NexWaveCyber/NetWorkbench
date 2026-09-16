import SwiftUI
import UniformTypeIdentifiers
import InvestigationKit
import PersistenceKit

public struct InvestigationsWorkspaceView: View {
    @Bindable var state: AppState
    @State private var showingNewSheet = false
    @State private var newTitle = ""
    @State private var newDescription = ""
    @State private var newSeverity = InvestigationSeverity.medium
    @State private var timelineEvents: [TimelineEventRecord] = []
    @State private var newEventText = ""

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        NavigationSplitView {
            // MARK: - Investigations Master List
            VStack(spacing: 0) {
                HStack {
                    Text("INVESTIGATIONS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()

                    Button(action: { importBundle() }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Import Investigation Bundle (.nwi)")

                    Button(action: { showingNewSheet = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .help("Create New Investigation")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                List(selection: $state.selectedInvestigation) {
                    ForEach(state.investigations) { inv in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(inv.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                                statusBadge(inv.status)
                            }

                            HStack {
                                Text(inv.severity.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(severityColor(inv.severity).opacity(0.12))
                                    .foregroundStyle(severityColor(inv.severity))
                                    .clipShape(Capsule())

                                Text("•")
                                    .foregroundStyle(.secondary)

                                Text(inv.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(inv)
                    }
                }
                .listStyle(.inset)
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            // MARK: - Investigation Detail & Chronological Timeline
            if let inv = state.selectedInvestigation {
                investigationDetailView(inv: inv)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "briefcase")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Select an investigation to view its timeline and evidence.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: state.selectedInvestigation) { _, newInv in
            loadTimeline(for: newInv)
        }
        .onAppear {
            if state.selectedInvestigation == nil {
                state.selectedInvestigation = state.investigations.first
            }
            loadTimeline(for: state.selectedInvestigation)
        }
        .sheet(isPresented: $showingNewSheet) {
            newInvestigationSheet
        }
    }

    private func investigationDetailView(inv: Investigation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(inv.title)
                            .font(.system(size: 18, weight: .bold))
                        Text(inv.description.isEmpty ? "No description provided." : inv.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        exportBundle(for: inv)
                    } label: {
                        Label("Export Bundle (.nwi)", systemImage: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.cyanPulse.opacity(0.35), lineWidth: 1))
                    .help("Export complete incident bundle for team collaboration")

                    statusBadge(inv.status)
                }

                HStack(spacing: 16) {
                    Label("Opened \(inv.createdAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Label("Severity: \(inv.severity.rawValue)", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(severityColor(inv.severity))

                    if let res = inv.resolution {
                        Label("Resolution: \(res)", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.signalEmerald)
                    }
                }
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Timeline Header
            HStack {
                Text("CHRONOLOGICAL TIMELINE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(timelineEvents.count) Events")
                    .font(Theme.monoText(11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Timeline Scroll
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(timelineEvents) { event in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(categoryColor(event.category))
                                    .frame(width: 10, height: 10)
                                    .shadow(color: categoryColor(event.category).opacity(0.6), radius: 4, x: 0, y: 0)
                                    .padding(.top, 4)

                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [categoryColor(event.category).opacity(0.3), Color.primary.opacity(0.08)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 1.5)
                                    .frame(minHeight: 36)
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(event.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    Spacer()
                                    HStack(spacing: 3) {
                                        Image(systemName: "clock")
                                            .font(.system(size: 9))
                                        Text(Date(timeIntervalSince1970: event.timestamp).formatted(date: .omitted, time: .standard))
                                            .font(Theme.monoText(11))
                                    }
                                    .foregroundStyle(.secondary)
                                }

                                if !event.detail.isEmpty {
                                    Text(event.detail)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.primary.opacity(0.85))
                                }
                            }
                            .padding(.bottom, 16)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Divider()

            // Quick Add Note
            HStack(spacing: 10) {
                TextField("Add timeline observation or engineering note...", text: $newEventText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addTimelineNote()
                    }

                Button("Add Note") {
                    addTimelineNote()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newEventText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func addTimelineNote() {
        guard let inv = state.selectedInvestigation else { return }
        let text = newEventText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let ev = TimelineEventRecord(
            investigationId: inv.id,
            timestamp: Date().timeIntervalSince1970,
            title: "Engineering Note",
            detail: text,
            category: "Manual"
        )
        _ = try? state.investigationManager.createInvestigation(title: inv.title) // ensure db exists
        try? state.database.execute(sql: "INSERT INTO timeline_events (id, investigation_id, timestamp, title, detail, category) VALUES ('\(ev.id)', '\(ev.investigationId)', \(ev.timestamp), 'Engineering Note', '\(text)', 'Manual');")

        newEventText = ""
        loadTimeline(for: inv)
    }

    private func loadTimeline(for inv: Investigation?) {
        guard let inv = inv else {
            timelineEvents = []
            return
        }
        timelineEvents = (try? state.investigationManager.fetchTimeline(forInvestigationId: inv.id)) ?? []
    }

    private func exportBundle(for inv: Investigation) {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Investigation Bundle"
        savePanel.prompt = "Export"
        let cleanTitle = inv.title.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        savePanel.nameFieldStringValue = "\(cleanTitle).nwi"
        if let nwiType = UTType(filenameExtension: "nwi") {
            savePanel.allowedContentTypes = [nwiType, .data]
        } else {
            savePanel.allowedContentTypes = [.data]
        }

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try state.investigationManager.exportInvestigationBundle(
                    id: inv.id,
                    to: url,
                    notes: "Exported from NexWave Studio on \(Date().formatted())"
                )
                state.toastMessage = "Exported '\(url.lastPathComponent)' successfully."
            } catch {
                state.toastMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func importBundle() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Import Investigation Bundle (.nwi)"
        openPanel.prompt = "Import"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        if let nwiType = UTType(filenameExtension: "nwi") {
            openPanel.allowedContentTypes = [nwiType, .data]
        } else {
            openPanel.allowedContentTypes = [.data]
        }

        if openPanel.runModal() == .OK, let url = openPanel.url {
            do {
                let imported = try state.investigationManager.importInvestigationBundle(from: url)
                state.refreshInvestigations()
                state.selectedInvestigation = imported
                state.toastMessage = "Imported investigation '\(imported.title)' successfully."
            } catch {
                state.toastMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private var newInvestigationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create New Investigation")
                .font(.system(size: 16, weight: .bold))

            TextField("Title (e.g. DC01 Rack 8 intermittent connectivity)", text: $newTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Problem description or ticket reference...", text: $newDescription)
                .textFieldStyle(.roundedBorder)

            Picker("Severity", selection: $newSeverity) {
                ForEach(InvestigationSeverity.allCases) { sev in
                    Text(sev.rawValue).tag(sev)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    showingNewSheet = false
                }
                .buttonStyle(.plain)

                Button("Create") {
                    if let inv = try? state.investigationManager.createInvestigation(title: newTitle, description: newDescription, severity: newSeverity) {
                        state.refreshInvestigations()
                        state.selectedInvestigation = inv
                    }
                    newTitle = ""
                    newDescription = ""
                    showingNewSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func statusBadge(_ status: InvestigationStatus) -> some View {
        Text(status.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }

    private func severityColor(_ s: InvestigationSeverity) -> Color {
        switch s {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }

    private func categoryColor(_ c: String) -> Color {
        switch c {
        case "Diagnostic": return Color.blue
        case "Manual": return Color.green
        case "Config": return Color.purple
        default: return Color.orange
        }
    }
}
