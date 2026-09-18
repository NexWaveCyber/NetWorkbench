import SwiftUI
import UniformTypeIdentifiers
import InvestigationKit
import PersistenceKit

public struct InvestigationsWorkspaceView: View {
    @Bindable var state: AppState

    // Master List Filter & Search State
    @State private var searchText = ""
    @State private var statusFilter: String = "All"

    // Detail Tabs
    @State private var selectedDetailTab: InvestigationTab = .overview

    // New Investigation Modal
    @State private var showingNewSheet = false
    @State private var newTitle = ""
    @State private var newDescription = ""
    @State private var newSeverity = InvestigationSeverity.medium
    @State private var newCommander = ""
    @State private var newAffectedServices = ""
    @State private var newBlastRadius = ""

    // Active Investigation Sub-items
    @State private var timelineEvents: [TimelineEventRecord] = []
    @State private var evidenceItems: [EvidenceItem] = []
    @State private var hypotheses: [InvestigationHypothesis] = []
    @State private var actionItems: [InvestigationActionItem] = []
    @State private var rcaRecord: InvestigationRCA?
    
    // Cached demo drill templates to avoid re-instantiating heavy bundle models on every SwiftUI body evaluation
    private static let demoDrills = InvestigationBundleManager.createDemoInvestigations()

    // Quick Add Timeline
    @State private var newEventText = ""
    @State private var newEventCategory = "Manual"
    @State private var timelineFilterCategory: String = "All"
    @State private var timelineSearchText = ""

    // Sheets & Inspectors
    @State private var inspectedEvidence: EvidenceItem?
    @State private var showingAddEvidenceSheet = false
    @State private var showingAddHypothesisSheet = false
    @State private var newHypothesisStatement = ""
    @State private var newHypothesisTest = ""
    @State private var showingAddActionSheet = false
    @State private var newActionTitle = ""
    @State private var newActionPhase = ActionPhase.mitigation
    @State private var newActionAssignee = ""
    @State private var showingPostMortemSheet = false
    @State private var isTargetedForDrop = false
    @State private var resolutionEditMode = false
    @State private var resolutionText = ""

    public enum InvestigationTab: String, CaseIterable, Identifiable {
        case overview = "Overview & SLA"
        case timeline = "Timeline"
        case evidence = "Evidence Locker"
        case rca = "Root Cause (5-Whys)"
        case runbook = "Runbook"
        case postMortem = "Post-Mortem"

        public var id: String { rawValue }

        public var iconName: String {
            switch self {
            case .overview: return "gauge.with.needle"
            case .timeline: return "clock.arrow.circlepath"
            case .evidence: return "archivebox.fill"
            case .rca: return "arrow.triangle.branch"
            case .runbook: return "checklist"
            case .postMortem: return "doc.text.fill"
            }
        }
    }

    public init(state: AppState) {
        self.state = state
    }

    // Filtered investigations list
    private var filteredInvestigations: [Investigation] {
        state.investigations.filter { inv in
            let matchesSearch = searchText.isEmpty ||
                inv.title.localizedCaseInsensitiveContains(searchText) ||
                inv.description.localizedCaseInsensitiveContains(searchText) ||
                (inv.commander?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                inv.affectedServices.contains { $0.localizedCaseInsensitiveContains(searchText) }

            let matchesStatus: Bool
            switch statusFilter {
            case "Active": matchesStatus = inv.status.isActive
            case "Resolved": matchesStatus = (inv.status == .resolved)
            case "Archived": matchesStatus = (inv.status == .archived)
            default: matchesStatus = true
            }

            return matchesSearch && matchesStatus
        }
    }

    public var body: some View {
        NavigationSplitView {
            // MARK: - Investigations Master List
            VStack(spacing: 0) {
                // Header & Action Bar
                HStack {
                    Text("INCIDENTS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()

                    // Enterprise Drill Incident Templates
                    Menu {
                        ForEach(Self.demoDrills, id: \.investigation.id) { demo in
                            Button(demo.investigation.title) {
                                loadDemoIncident(demo)
                            }
                        }
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                    }
                    .menuStyle(.borderlessButton)
                    .help("Load Enterprise Incident Drill Template")

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
                    .help("Create New Incident")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                // Search & Filter
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Search incidents...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

                // Status Filter Pills
                Picker("", selection: $statusFilter) {
                    Text("All (\(state.investigations.count))").tag("All")
                    Text("Active").tag("Active")
                    Text("Resolved").tag("Resolved")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                Divider()

                // Incident Rows
                List(selection: $state.selectedInvestigation) {
                    ForEach(filteredInvestigations) { inv in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(inv.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                                statusBadge(inv.status)
                            }

                            HStack(spacing: 6) {
                                Text(inv.severity.priorityPill)
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(severityColor(inv.severity).opacity(0.15))
                                    .foregroundStyle(severityColor(inv.severity))
                                    .clipShape(Capsule())

                                if inv.isSLAOverdue {
                                    Text("SLA!")
                                        .font(.system(size: 8, weight: .heavy))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Theme.crimsonCritical.opacity(0.2))
                                        .foregroundStyle(Theme.crimsonCritical)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }

                                Text("•")
                                    .foregroundStyle(.secondary)

                                Text("\(String(format: "%.0f", inv.durationMinutes))m")
                                    .font(Theme.monoText(10))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if let cmd = inv.commander, !cmd.isEmpty {
                                    Text(cmd.components(separatedBy: " ").first ?? cmd)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(inv)
                        .contextMenu {
                            Button("Mark as Resolved") {
                                resolveInvestigation(inv)
                            }
                            Button("Export Bundle (.nwi)") {
                                exportBundle(for: inv)
                            }
                            Divider()
                            Button(role: .destructive) {
                                deleteInvestigation(inv)
                            } label: {
                                Label("Delete Incident", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            .overlay {
                if isTargetedForDrop {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.cyanPulse, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .background(Theme.cyanPulse.opacity(0.12))
                        .overlay(
                            VStack(spacing: 6) {
                                Image(systemName: "arrow.down.doc.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Theme.cyanPulse)
                                Text("Drop .nwi Investigation Bundle")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.cyanPulse)
                            }
                        )
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
                handleFileDrop(providers: providers)
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
        } detail: {
            // MARK: - Investigation Detail View
            if let inv = state.selectedInvestigation {
                investigationDetailView(inv: inv)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "briefcase.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.cyanPulse.opacity(0.6))
                    Text("Select an incident to view SLA metrics, timeline, and evidence.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: state.selectedInvestigation) { _, newInv in
            loadInvestigationData(for: newInv)
        }
        .onAppear {
            if state.selectedInvestigation == nil {
                state.selectedInvestigation = state.investigations.first
            }
            loadInvestigationData(for: state.selectedInvestigation)
        }
        .sheet(isPresented: $showingNewSheet) {
            newInvestigationSheet
        }
        .sheet(item: $inspectedEvidence) { item in
            EvidenceInspectorSheet(item: item) {
                inspectedEvidence = nil
            }
        }
        .sheet(isPresented: $showingAddEvidenceSheet) {
            if let inv = state.selectedInvestigation {
                AddEvidenceSheet(investigationId: inv.id) { title, fn, type, content, notes in
                    _ = try? state.investigationManager.attachEvidence(
                        investigationId: inv.id,
                        title: title,
                        filename: fn,
                        type: type,
                        content: content,
                        sourceWorkbench: "Evidence Locker",
                        notes: notes
                    )
                    loadInvestigationData(for: inv)
                } onDismiss: {
                    showingAddEvidenceSheet = false
                }
            }
        }
        .sheet(isPresented: $showingPostMortemSheet) {
            if let inv = state.selectedInvestigation {
                let md = (try? state.investigationManager.generatePostMortemMarkdown(id: inv.id)) ?? ""
                let html = (try? state.investigationManager.generatePostMortemHTML(id: inv.id)) ?? ""
                PostMortemExportSheet(markdown: md, html: html) {
                    showingPostMortemSheet = false
                }
            }
        }
    }

    // MARK: - Investigation Detail Canvas

    private func investigationDetailView(inv: Investigation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Bar
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(inv.title)
                                .font(.system(size: 18, weight: .bold))
                            statusBadge(inv.status)
                        }
                        Text(inv.description.isEmpty ? "No description provided." : inv.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Quick Action Buttons
                    HStack(spacing: 8) {
                        Button {
                            copySlackJiraTriage(for: inv)
                        } label: {
                            Label("Slack/Jira", systemImage: "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .help("Copy Slack or Jira incident triage markdown")

                        Button {
                            showingPostMortemSheet = true
                        } label: {
                            Label("Post-Mortem", systemImage: "doc.text.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .help("Generate Executive Post-Mortem report")

                        Button {
                            exportBundle(for: inv)
                        } label: {
                            Label("Export .nwi", systemImage: "square.and.arrow.up")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .help("Export complete .nwi incident archive")
                    }
                }

                // Interactive Status & Incident Attributes
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Text("Status:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Picker("", selection: Binding(
                            get: { inv.status },
                            set: { newStatus in
                                updateStatus(for: inv, to: newStatus)
                            }
                        )) {
                            ForEach(InvestigationStatus.allCases) { st in
                                Text(st.rawValue).tag(st)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }

                    HStack(spacing: 6) {
                        Text("Severity:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(inv.severity.priorityPill)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(severityColor(inv.severity))
                    }

                    if let cmd = inv.commander, !cmd.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.cyanPulse)
                            Text("Lead: \(cmd)")
                                .font(.system(size: 11))
                        }
                    }

                    Spacer()

                    Text("Opened \(inv.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(Theme.monoText(11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Segmented Detail Tabs
            HStack(spacing: 0) {
                ForEach(InvestigationTab.allCases) { tab in
                    Button {
                        selectedDetailTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 11))
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: selectedDetailTab == tab ? .bold : .medium))
                            
                            // Badge counts
                            if tab == .timeline && !timelineEvents.isEmpty {
                                Text("\(timelineEvents.count)")
                                    .font(Theme.monoText(9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.1))
                                    .clipShape(Capsule())
                            } else if tab == .evidence && !evidenceItems.isEmpty {
                                Text("\(evidenceItems.count)")
                                    .font(Theme.monoText(9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Theme.cyanPulse.opacity(0.18))
                                    .foregroundStyle(Theme.cyanPulse)
                                    .clipShape(Capsule())
                            } else if tab == .runbook && !actionItems.isEmpty {
                                let pending = actionItems.filter { !$0.isCompleted }.count
                                if pending > 0 {
                                    Text("\(pending)")
                                        .font(Theme.monoText(9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Theme.solarAmber.opacity(0.2))
                                        .foregroundStyle(Theme.solarAmber)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .foregroundStyle(selectedDetailTab == tab ? Theme.cyanPulse : .secondary)
                        .background(selectedDetailTab == tab ? Theme.cyanPulse.opacity(0.1) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Active Tab View Content
            VStack {
                switch selectedDetailTab {
                case .overview:
                    overviewTabView(inv: inv)
                case .timeline:
                    timelineTabView(inv: inv)
                case .evidence:
                    evidenceTabView(inv: inv)
                case .rca:
                    rcaTabView(inv: inv)
                case .runbook:
                    runbookTabView(inv: inv)
                case .postMortem:
                    postMortemTabView(inv: inv)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: - Tab 1: Overview & SLA Metrics

    private func overviewTabView(inv: Investigation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // SLA & Incident KPI Cards
                HStack(spacing: 12) {
                    IncidentMetricCard(
                        title: "Outage Duration",
                        value: "\(String(format: "%.0f", inv.durationMinutes))m",
                        subtitle: inv.status.isActive ? "Active Outage" : "Closed",
                        tint: Theme.cyanPulse
                    )

                    IncidentMetricCard(
                        title: "Time to Mitigate",
                        value: inv.mttmMinutes != nil ? "\(String(format: "%.0f", inv.mttmMinutes!))m" : "Pending",
                        subtitle: "Detection ➔ Workaround",
                        tint: Theme.solarAmber
                    )

                    IncidentMetricCard(
                        title: "Time to Resolve",
                        value: inv.mttrMinutes != nil ? "\(String(format: "%.0f", inv.mttrMinutes!))m" : "In Progress",
                        subtitle: "Detection ➔ Resolution",
                        tint: Theme.signalEmerald
                    )

                    IncidentMetricCard(
                        title: "SLA Target (\(Int(inv.severity.slaTargetMinutes))m)",
                        value: inv.isSLAOverdue ? "Breached" : "Compliant",
                        subtitle: inv.isSLAOverdue ? "\(Int(inv.durationMinutes - inv.severity.slaTargetMinutes))m Overdue" : "Within \(inv.severity.priorityPill) SLA",
                        tint: inv.isSLAOverdue ? Theme.crimsonCritical : Theme.signalEmerald,
                        isAlert: inv.isSLAOverdue
                    )
                }

                // Blast Radius & Affected Scope
                VStack(alignment: .leading, spacing: 10) {
                    Label("BLAST RADIUS & AFFECTED INFRASTRUCTURE", systemImage: "target")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Estimated Impact")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(inv.blastRadius ?? "Unspecified blast radius")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Affected Services")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            if inv.affectedServices.isEmpty {
                                Text("No services tagged")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(inv.affectedServices.joined(separator: ", "))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.cyanPulse)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Affected Devices")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            if inv.affectedDevices.isEmpty {
                                Text("No devices tagged")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(inv.affectedDevices.joined(separator: ", "))
                                    .font(Theme.monoText(12, weight: .semibold))
                                    .foregroundStyle(Theme.electricAzure)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Resolution Summary Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("RESOLUTION & CLOSING SUMMARY", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.signalEmerald)
                        Spacer()
                        if !resolutionEditMode {
                            Button("Edit Resolution") {
                                resolutionText = inv.resolution ?? ""
                                resolutionEditMode = true
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.cyanPulse)
                        } else {
                            Button("Save") {
                                saveResolution(for: inv)
                            }
                            .buttonStyle(.borderedProminent)
                            .font(.system(size: 11))
                        }
                    }

                    if resolutionEditMode {
                        TextEditor(text: $resolutionText)
                            .font(.system(size: 12))
                            .frame(height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                    } else if let res = inv.resolution, !res.isEmpty {
                        Text(res)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.signalEmerald.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.signalEmerald.opacity(0.3), lineWidth: 1))
                    } else {
                        HStack {
                            Text("No resolution recorded. When the incident is resolved, document the fix here.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Resolve Incident...") {
                                resolutionText = ""
                                resolutionEditMode = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(18)
        }
    }

    // MARK: - Tab 2: Timeline

    private func timelineTabView(inv: Investigation) -> some View {
        VStack(spacing: 0) {
            // Timeline Filter Bar
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                    Picker("Category", selection: $timelineFilterCategory) {
                        Text("All Categories").tag("All")
                        Text("Diagnostics").tag("Diagnostic")
                        Text("Syslog / Traps").tag("Syslog")
                        Text("Config Changes").tag("Config")
                        Text("Actions").tag("Action")
                        Text("Manual Notes").tag("Manual")
                        Text("Status Changes").tag("StatusChange")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Filter timeline...", text: $timelineSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                Text("\(filteredTimelineEvents.count) Events")
                    .font(Theme.monoText(11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Chronological Event Stream
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredTimelineEvents) { event in
                        HStack(alignment: .top, spacing: 14) {
                            // Timeline dot & line
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(categoryColor(event.category))
                                    .frame(width: 10, height: 10)
                                    .shadow(color: categoryColor(event.category).opacity(0.6), radius: 4, x: 0, y: 0)
                                    .padding(.top, 4)

                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [categoryColor(event.category).opacity(0.4), Color.primary.opacity(0.06)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 1.5)
                                    .frame(minHeight: 36)
                            }

                            // Event Body
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(event.title)
                                        .font(.system(size: 13, weight: .semibold))

                                    Text(event.category)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(categoryColor(event.category).opacity(0.12))
                                        .foregroundStyle(categoryColor(event.category))
                                        .clipShape(Capsule())

                                    Spacer()

                                    // Time & Offset
                                    HStack(spacing: 4) {
                                        let offset = (event.timestamp - inv.detectedAt.timeIntervalSince1970) / 60.0
                                        Text("+\(String(format: "%.0f", max(0, offset)))m")
                                            .font(Theme.monoText(10, weight: .bold))
                                            .foregroundStyle(Theme.cyanPulse)

                                        Text(Date(timeIntervalSince1970: event.timestamp).formatted(date: .omitted, time: .standard))
                                            .font(Theme.monoText(10))
                                            .foregroundStyle(.secondary)
                                    }

                                    Button {
                                        deleteTimelineEvent(event.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                }

                                if !event.detail.isEmpty {
                                    Text(event.detail)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.primary.opacity(0.85))
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.bottom, 16)
                        }
                    }
                }
                .padding(18)
            }

            Divider()

            // Quick Add Event Bar
            HStack(spacing: 10) {
                Picker("", selection: $newEventCategory) {
                    Text("Manual Note").tag("Manual")
                    Text("Diagnostic Observation").tag("Diagnostic")
                    Text("Config Action").tag("Config")
                    Text("Mitigation Step").tag("Action")
                }
                .pickerStyle(.menu)
                .frame(width: 140)

                TextField("Add observation, telemetry note, or action taken...", text: $newEventText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTimelineNote(inv: inv) }

                Button("Log Event") {
                    addTimelineNote(inv: inv)
                }
                .buttonStyle(.borderedProminent)
                .disabled(newEventText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var filteredTimelineEvents: [TimelineEventRecord] {
        timelineEvents.filter { e in
            let matchesCategory = (timelineFilterCategory == "All") || (e.category == timelineFilterCategory)
            let matchesSearch = timelineSearchText.isEmpty ||
                e.title.localizedCaseInsensitiveContains(timelineSearchText) ||
                e.detail.localizedCaseInsensitiveContains(timelineSearchText)
            return matchesCategory && matchesSearch
        }
    }

    // MARK: - Tab 3: Evidence Locker (Forensic Vault)

    private func evidenceTabView(inv: Investigation) -> some View {
        VStack(spacing: 0) {
            // Evidence Action Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FORENSIC EVIDENCE VAULT & CHAIN-OF-CUSTODY")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(evidenceItems.count) Artifacts Attached &bull; Cryptographically Verified (SHA-256)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    showingAddEvidenceSheet = true
                } label: {
                    Label("Attach Evidence...", systemImage: "paperclip")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if evidenceItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.cyanPulse.opacity(0.4))
                    Text("No forensic evidence attached yet.")
                        .font(.system(size: 13, weight: .medium))
                    Text("Attach PCAP packet traces, CLI command dumps, config diffs, or diagnostic probe outputs.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Attach First Artifact...") {
                        showingAddEvidenceSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(evidenceItems) { item in
                            EvidenceItemRow(
                                item: item,
                                onInspect: { inspectedEvidence = item },
                                onDelete: { deleteEvidence(item.id) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: - Tab 4: Root Cause Analysis (5-Whys & Hypotheses)

    private func rcaTabView(inv: Investigation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Section 1: Hypothesis Matrix
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("INCIDENT HYPOTHESES TESTING MATRIX", systemImage: "flask.fill")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.solarAmber)
                        Spacer()
                        Button("Add Hypothesis...") {
                            showingAddHypothesisSheet = true
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.cyanPulse)
                    }

                    if hypotheses.isEmpty {
                        Text("No hypotheses formulated yet. Add theories to systematically confirm or refute potential root causes.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        VStack(spacing: 8) {
                            ForEach(hypotheses) { hyp in
                                HypothesisCard(
                                    hypothesis: hyp,
                                    onStatusChange: { newStatus, findings in
                                        updateHypothesisStatus(hyp.id, status: newStatus, findings: findings)
                                    },
                                    onDelete: {
                                        deleteHypothesis(hyp.id)
                                    }
                                )
                            }
                        }
                    }
                }

                Divider()

                // Section 2: 5-Whys Root Cause Tree Card
                FiveWhysTreeCard(rca: rcaRecord) { updatedRCA in
                    var rcaToSave = updatedRCA
                    if rcaToSave.investigationId.isEmpty {
                        rcaToSave = InvestigationRCA(
                            id: UUID().uuidString,
                            investigationId: inv.id,
                            problemStatement: updatedRCA.problemStatement,
                            why1: updatedRCA.why1,
                            why2: updatedRCA.why2,
                            why3: updatedRCA.why3,
                            why4: updatedRCA.why4,
                            why5: updatedRCA.why5,
                            rootCause: updatedRCA.rootCause,
                            preventativeStrategy: updatedRCA.preventativeStrategy
                        )
                    }
                    try? state.investigationManager.saveRCA(rcaToSave)
                    rcaRecord = rcaToSave
                    state.toastMessage = "Saved 5-Whys Root Cause Analysis!"
                }
            }
            .padding(18)
        }
        .sheet(isPresented: $showingAddHypothesisSheet) {
            addHypothesisSheet(inv: inv)
        }
    }

    private func addHypothesisSheet(inv: Investigation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Propose Incident Hypothesis")
                .font(.system(size: 15, weight: .bold))

            TextField("Hypothesis (e.g. SFP+ optical power attenuation causing packet drop)", text: $newHypothesisStatement)
                .textFieldStyle(.roundedBorder)

            TextField("Proposed Verification Test (e.g. Read DOM optic telemetry)", text: $newHypothesisTest)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { showingAddHypothesisSheet = false }
                    .buttonStyle(.plain)
                Button("Add Hypothesis") {
                    _ = try? state.investigationManager.addHypothesis(
                        investigationId: inv.id,
                        statement: newHypothesisStatement,
                        proposedTest: newHypothesisTest
                    )
                    newHypothesisStatement = ""
                    newHypothesisTest = ""
                    showingAddHypothesisSheet = false
                    loadInvestigationData(for: inv)
                }
                .buttonStyle(.borderedProminent)
                .disabled(newHypothesisStatement.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    // MARK: - Tab 5: Mitigation Runbook & Action Items

    private func runbookTabView(inv: Investigation) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("INCIDENT MITIGATION & RECOVERY RUNBOOK")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    let completed = actionItems.filter { $0.isCompleted }.count
                    Text("\(completed) of \(actionItems.count) Tasks Completed")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    showingAddActionSheet = true
                } label: {
                    Label("Add Task...", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if actionItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.solarAmber.opacity(0.4))
                    Text("No runbook tasks created yet.")
                        .font(.system(size: 13, weight: .medium))
                    Text("Create immediate mitigation steps, verification checks, and post-incident hardening tasks.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button("Add First Action Item...") {
                        showingAddActionSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(ActionPhase.allCases) { phase in
                            let phaseItems = actionItems.filter { $0.phase == phase }
                            if !phaseItems.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(phase.displayName.uppercased())
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(phaseColor(phase))

                                    VStack(spacing: 6) {
                                        ForEach(phaseItems) { item in
                                            ActionItemRow(
                                                item: item,
                                                onToggle: { isComp in
                                                    toggleActionItem(item.id, isCompleted: isComp)
                                                },
                                                onDelete: {
                                                    deleteActionItem(item.id)
                                                }
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(isPresented: $showingAddActionSheet) {
            addActionSheet(inv: inv)
        }
    }

    private func addActionSheet(inv: Investigation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Runbook Action Item")
                .font(.system(size: 15, weight: .bold))

            TextField("Action Item Title (e.g. Prepend BGP path to AS65001)", text: $newActionTitle)
                .textFieldStyle(.roundedBorder)

            Picker("Phase", selection: $newActionPhase) {
                ForEach(ActionPhase.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }

            TextField("Assignee (Optional)", text: $newActionAssignee)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { showingAddActionSheet = false }
                    .buttonStyle(.plain)
                Button("Add Task") {
                    _ = try? state.investigationManager.addActionItem(
                        investigationId: inv.id,
                        title: newActionTitle,
                        phase: newActionPhase,
                        assignee: newActionAssignee.isEmpty ? nil : newActionAssignee
                    )
                    newActionTitle = ""
                    newActionAssignee = ""
                    showingAddActionSheet = false
                    loadInvestigationData(for: inv)
                }
                .buttonStyle(.borderedProminent)
                .disabled(newActionTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func phaseColor(_ p: ActionPhase) -> Color {
        switch p {
        case .mitigation: return Theme.crimsonCritical
        case .verification: return Theme.cyanPulse
        case .postMortem: return Theme.quantumViolet
        }
    }

    // MARK: - Tab 6: Post-Mortem & Review

    private func postMortemTabView(inv: Investigation) -> some View {
        let md = (try? state.investigationManager.generatePostMortemMarkdown(id: inv.id)) ?? ""
        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EXECUTIVE INCIDENT POST-MORTEM")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Auto-generated from live timeline, forensic evidence ledger, and 5-Whys analysis.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    copySlackJiraTriage(for: inv)
                } label: {
                    Label("Copy Slack/Jira", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Button("Export Formatted Reports...") {
                    showingPostMortemSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                Text(md)
                    .font(Theme.monoText(11))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
        }
    }

    // MARK: - Data Operations

    private func loadInvestigationData(for inv: Investigation?) {
        guard let inv = inv else {
            timelineEvents = []
            evidenceItems = []
            hypotheses = []
            actionItems = []
            rcaRecord = nil
            return
        }
        timelineEvents = (try? state.investigationManager.fetchTimeline(forInvestigationId: inv.id)) ?? []
        evidenceItems = (try? state.investigationManager.listEvidence(forInvestigationId: inv.id)) ?? []
        hypotheses = (try? state.investigationManager.listHypotheses(forInvestigationId: inv.id)) ?? []
        actionItems = (try? state.investigationManager.listActionItems(forInvestigationId: inv.id)) ?? []
        rcaRecord = try? state.investigationManager.fetchRCA(forInvestigationId: inv.id)
    }

    private func updateStatus(for inv: Investigation, to newStatus: InvestigationStatus) {
        do {
            try state.investigationManager.updateInvestigationStatus(id: inv.id, status: newStatus)
            state.refreshInvestigations()
            if let updated = state.investigations.first(where: { $0.id == inv.id }) {
                state.selectedInvestigation = updated
                loadInvestigationData(for: updated)
            }
            state.toastMessage = "Incident status updated to '\(newStatus.rawValue)'"
        } catch {
            state.toastMessage = "Status update failed: \(error.localizedDescription)"
        }
    }

    private func saveResolution(for inv: Investigation) {
        do {
            try state.investigationManager.updateInvestigationStatus(
                id: inv.id,
                status: .resolved,
                resolution: resolutionText
            )
            resolutionEditMode = false
            state.refreshInvestigations()
            if let updated = state.investigations.first(where: { $0.id == inv.id }) {
                state.selectedInvestigation = updated
                loadInvestigationData(for: updated)
            }
            state.toastMessage = "Incident resolved successfully!"
        } catch {
            state.toastMessage = "Failed to save resolution: \(error.localizedDescription)"
        }
    }

    private func resolveInvestigation(_ inv: Investigation) {
        updateStatus(for: inv, to: .resolved)
    }

    private func deleteInvestigation(_ inv: Investigation) {
        do {
            try state.investigationManager.deleteInvestigation(id: inv.id)
            state.refreshInvestigations()
            state.selectedInvestigation = state.investigations.first
            loadInvestigationData(for: state.selectedInvestigation)
            state.toastMessage = "Incident deleted."
        } catch {
            state.toastMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func addTimelineNote(inv: Investigation) {
        let text = newEventText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        try? state.investigationManager.addTimelineEvent(
            investigationId: inv.id,
            title: newEventCategory == "Manual" ? "Engineering Note" : "\(newEventCategory) Log",
            detail: text,
            category: newEventCategory
        )

        newEventText = ""
        loadInvestigationData(for: inv)
    }

    private func deleteTimelineEvent(_ id: String) {
        guard let inv = state.selectedInvestigation else { return }
        try? state.investigationManager.deleteTimelineEvent(id: id)
        loadInvestigationData(for: inv)
    }

    private func deleteEvidence(_ id: String) {
        guard let inv = state.selectedInvestigation else { return }
        try? state.investigationManager.deleteEvidence(id: id)
        loadInvestigationData(for: inv)
    }

    private func updateHypothesisStatus(_ id: String, status: HypothesisStatus, findings: String) {
        guard let inv = state.selectedInvestigation else { return }
        try? state.investigationManager.updateHypothesisStatus(id: id, investigationId: inv.id, status: status, findings: findings)
        loadInvestigationData(for: inv)
    }

    private func deleteHypothesis(_ id: String) {
        guard let inv = state.selectedInvestigation else { return }
        try? state.investigationManager.deleteHypothesis(id: id)
        loadInvestigationData(for: inv)
    }

    private func toggleActionItem(_ id: String, isCompleted: Bool) {
        guard let inv = state.selectedInvestigation else { return }
        try? state.investigationManager.toggleActionItem(id: id, investigationId: inv.id, isCompleted: isCompleted)
        loadInvestigationData(for: inv)
    }

    private func deleteActionItem(_ id: String) {
        guard let inv = state.selectedInvestigation else { return }
        try? state.investigationManager.deleteActionItem(id: id)
        loadInvestigationData(for: inv)
    }

    private func exportBundle(for inv: Investigation) {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Investigation Bundle (.nwi)"
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
                loadInvestigationData(for: imported)
                state.toastMessage = "Imported investigation '\(imported.title)' successfully."
            } catch {
                state.toastMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private func loadDemoIncident(_ bundle: InvestigationBundle) {
        do {
            try InvestigationBundleManager.importIntoDatabase(
                bundle: bundle,
                investigationRepo: InvestigationRepository(database: state.database),
                evidenceRepo: EvidenceRepository(database: state.database),
                hypothesisRepo: HypothesisRepository(database: state.database),
                actionItemRepo: ActionItemRepository(database: state.database),
                rcaRepo: RCARepository(database: state.database),
                historyRepo: DiagnosticHistoryRepository(database: state.database)
            )
            state.refreshInvestigations()
            state.selectedInvestigation = state.investigations.first { $0.id == bundle.investigation.id }
            loadInvestigationData(for: state.selectedInvestigation)
            state.toastMessage = "Loaded enterprise incident: '\(bundle.investigation.title)'"
        } catch {
            state.toastMessage = "Failed to load drill: \(error.localizedDescription)"
        }
    }

    private func copySlackJiraTriage(for inv: Investigation) {
        let summary = IncidentPostMortemGenerator.generateSlackJiraTriage(
            investigation: inv,
            timeline: timelineEvents,
            evidenceCount: evidenceItems.count,
            rca: rcaRecord
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        state.toastMessage = "Copied Slack/Jira incident triage summary!"
    }

    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url = url, url.pathExtension.lowercased() == "nwi" else { return }
            DispatchQueue.main.async {
                do {
                    let imported = try state.investigationManager.importInvestigationBundle(from: url)
                    state.refreshInvestigations()
                    state.selectedInvestigation = imported
                    loadInvestigationData(for: imported)
                    state.toastMessage = "Imported '\(imported.title)' successfully."
                } catch {
                    state.toastMessage = "Import error: \(error.localizedDescription)"
                }
            }
        }
        return true
    }

    // MARK: - New Investigation Sheet

    private var newInvestigationSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Declare New Incident")
                .font(.system(size: 16, weight: .bold))

            TextField("Title (e.g. DC01 Core Transit BGP Route Flap)", text: $newTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Problem description or symptom...", text: $newDescription)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Picker("Severity", selection: $newSeverity) {
                    ForEach(InvestigationSeverity.allCases) { sev in
                        Text(sev.priorityPill).tag(sev)
                    }
                }

                TextField("Incident Commander", text: $newCommander)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Affected Services (comma-separated, e.g. BGP, DNS, SAN)", text: $newAffectedServices)
                .textFieldStyle(.roundedBorder)

            TextField("Blast Radius (e.g. 14,000 branch users, 2 Datacenters)", text: $newBlastRadius)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { showingNewSheet = false }
                    .buttonStyle(.plain)

                Button("Open Incident") {
                    let services = newAffectedServices.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    if let inv = try? state.investigationManager.createInvestigation(
                        title: newTitle,
                        description: newDescription,
                        severity: newSeverity,
                        commander: newCommander.isEmpty ? nil : newCommander,
                        affectedServices: services,
                        blastRadius: newBlastRadius.isEmpty ? nil : newBlastRadius
                    ) {
                        state.refreshInvestigations()
                        state.selectedInvestigation = inv
                        loadInvestigationData(for: inv)
                    }
                    newTitle = ""
                    newDescription = ""
                    newCommander = ""
                    newAffectedServices = ""
                    newBlastRadius = ""
                    showingNewSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    // MARK: - Helpers & Styling

    private func statusBadge(_ status: InvestigationStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
                .font(.system(size: 9))
            Text(status.rawValue)
                .font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(statusColor(status).opacity(0.15))
        .foregroundStyle(statusColor(status))
        .clipShape(Capsule())
    }

    private func statusColor(_ s: InvestigationStatus) -> Color {
        switch s {
        case .open: return Theme.solarAmber
        case .investigating: return Theme.cyanPulse
        case .mitigating: return Theme.electricAzure
        case .monitoring: return Theme.quantumViolet
        case .resolved: return Theme.signalEmerald
        case .archived: return .secondary
        }
    }

    private func severityColor(_ s: InvestigationSeverity) -> Color {
        switch s {
        case .low: return Theme.electricAzure
        case .medium: return Theme.solarAmber
        case .high: return Color.orange
        case .critical: return Theme.crimsonCritical
        }
    }

    private func categoryColor(_ c: String) -> Color {
        switch c {
        case "Diagnostic": return Theme.signalEmerald
        case "Syslog": return Theme.solarAmber
        case "Config": return Theme.quantumViolet
        case "Action": return Theme.cyanPulse
        case "StatusChange": return Color.blue
        default: return .secondary
        }
    }
}
