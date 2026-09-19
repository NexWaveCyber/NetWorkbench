import SwiftUI
import AppKit
import PersistenceKit
import NetworkCore

public struct HistoryWorkspaceView: View {
    public enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All Statuses"
        case healthy = "Healthy"
        case degraded = "Degraded"
        case failed = "Failed"

        public var id: String { rawValue }
    }

    public enum TimeFilter: String, CaseIterable, Identifiable {
        case all = "All Time"
        case today = "Today"
        case last24h = "Last 24 Hours"
        case last7d = "Last 7 Days"

        public var id: String { rawValue }
    }

    @Bindable var state: AppState

    // Filters
    @State private var filterQuery: String = ""
    @State private var selectedStatus: StatusFilter = .all
    @State private var selectedTargetType: String = "All Types"
    @State private var selectedTimeFilter: TimeFilter = .all
    @State private var fetchLimit: Int = 100

    // Inspection & Comparison Modals
    @State private var inspectRecord: DiagnosticHistoryRecord? = nil
    @State private var comparisonFirst: DiagnosticHistoryRecord? = nil
    @State private var comparisonSecond: DiagnosticHistoryRecord? = nil
    @State private var isShowingComparison: Bool = false

    // Alerts & Confirmations
    @State private var showingClearHistoryAlert: Bool = false
    @State private var showingPurgeSheet: Bool = false
    @State private var purgeDays: Int = 30
    @State private var copiedJsonId: String? = nil

    public init(state: AppState) {
        self.state = state
    }

    // Target types discovered in history
    public var availableTargetTypes: [String] {
        var set = Set(state.recentHistory.map { $0.targetType })
        set.insert("All Types")
        return ["All Types"] + set.filter { $0 != "All Types" }.sorted()
    }

    // Filtered records
    public var filteredHistory: [DiagnosticHistoryRecord] {
        var list = state.recentHistory

        // Text query
        let q = filterQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.target.lowercased().contains(q) ||
                $0.summary.lowercased().contains(q) ||
                $0.targetType.lowercased().contains(q)
            }
        }

        // Status filter
        switch selectedStatus {
        case .all:
            break
        case .healthy:
            list = list.filter { $0.tcpHealthy && ($0.packetLoss ?? 0) == 0 && $0.dnsHealthy }
        case .degraded:
            list = list.filter {
                ($0.tcpHealthy && (($0.packetLoss ?? 0) > 0 || ($0.pingLatency ?? 0) > 60.0)) ||
                ($0.httpStatus != nil && $0.httpStatus! >= 400 && $0.httpStatus! < 500)
            }
        case .failed:
            list = list.filter {
                !$0.tcpHealthy || !$0.dnsHealthy || ($0.packetLoss ?? 0) >= 50 || ($0.httpStatus != nil && $0.httpStatus! >= 500)
            }
        }

        // Target type filter
        if selectedTargetType != "All Types" {
            list = list.filter { $0.targetType == selectedTargetType }
        }

        // Time range filter
        let now = Date().timeIntervalSince1970
        switch selectedTimeFilter {
        case .all:
            break
        case .today:
            let startOfToday = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
            list = list.filter { $0.timestamp >= startOfToday }
        case .last24h:
            list = list.filter { $0.timestamp >= (now - 86400) }
        case .last7d:
            list = list.filter { $0.timestamp >= (now - 7 * 86400) }
        }

        return list
    }

    // Analytics KPIs
    private var totalRunsCount: Int { state.recentHistory.count }
    private var healthyRunsCount: Int {
        state.recentHistory.filter { $0.tcpHealthy && ($0.packetLoss ?? 0) == 0 && $0.dnsHealthy }.count
    }
    private var passRatePct: Double {
        guard totalRunsCount > 0 else { return 100.0 }
        return (Double(healthyRunsCount) / Double(totalRunsCount)) * 100.0
    }
    private var averageLatencyMs: Double {
        let latencies = state.recentHistory.compactMap { $0.pingLatency }
        guard !latencies.isEmpty else { return 0.0 }
        return latencies.reduce(0, +) / Double(latencies.count)
    }
    private var anomaliesCount: Int {
        state.recentHistory.filter { !$0.tcpHealthy || !$0.dnsHealthy || ($0.packetLoss ?? 0) > 0 }.count
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider().overlay(Theme.borderLight)

            // KPI Summary Cards
            kpiSummaryBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            Divider().overlay(Theme.borderLight)

            // Search & Filter Toolbar
            filterToolbar
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

            Divider().overlay(Theme.borderLight)

            // History Data Grid
            if filteredHistory.isEmpty {
                emptyHistoryView
            } else {
                historyDataTable
            }
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("Diagnostic History")
        .sheet(item: $inspectRecord) { rec in
            diagnosticSnapshotInspector(rec)
        }
        .sheet(isPresented: $isShowingComparison) {
            runComparisonSheet
        }
        .sheet(isPresented: $showingPurgeSheet) {
            purgeOptionsSheet
        }
        .alert("Clear All Diagnostic History?", isPresented: $showingClearHistoryAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All History", role: .destructive) {
                state.clearAllHistory()
            }
        } message: {
            Text("This will permanently delete all saved diagnostic logs and test runs from the local SQLite database. This cannot be undone.")
        }
        .onAppear {
            state.refreshHistory(limit: fetchLimit)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.cyanPulse.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.cyanPulse)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("DIAGNOSTIC LOGS & TELEMETRY")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(Theme.cyanPulse)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("SQLITE WAL AUDIT TRAIL")
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text("Diagnostic Run History")
                    .font(.system(size: 18, weight: .bold))
            }

            Spacer()

            // Compare Selected Runs
            if comparisonFirst != nil && comparisonSecond != nil {
                Button(action: { isShowingComparison = true }) {
                    Label("Compare 2 Runs", systemImage: "arrow.left.and.right.square.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.quantumViolet)
            }

            // Export Menu
            Menu {
                Button("Export History to CSV (.csv)") {
                    exportHistoryCSV()
                }
                Button("Export History to JSON (.json)") {
                    exportHistoryJSON()
                }
            } label: {
                Label("Export", systemImage: "arrow.up.doc")
                    .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderedButton)

            // Maintenance Menu
            Menu {
                Button("Purge Records Older Than...") {
                    showingPurgeSheet = true
                }
                Divider()
                Button("Clear All History", role: .destructive) {
                    showingClearHistoryAlert = true
                }
            } label: {
                Label("Manage", systemImage: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderedButton)

            Button("Refresh") {
                state.refreshHistory(limit: fetchLimit)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.surfaceBackground)
    }

    // MARK: - KPI Summary Bar

    private var kpiSummaryBar: some View {
        HStack(spacing: 16) {
            kpiCard(
                title: "TOTAL RUNS",
                value: "\(totalRunsCount)",
                sub: "Logged in SQLite",
                icon: "waveform.path.ecg",
                color: Theme.cyanPulse
            )

            kpiCard(
                title: "SUCCESS RATE",
                value: String(format: "%.1f%%", passRatePct),
                sub: "\(healthyRunsCount) passed tests",
                icon: "checkmark.seal.fill",
                color: passRatePct >= 90 ? Theme.signalEmerald : Theme.solarAmber
            )

            kpiCard(
                title: "MEAN RTT LATENCY",
                value: averageLatencyMs > 0 ? String(format: "%.1f ms", averageLatencyMs) : "N/A",
                sub: "Average ping time",
                icon: "speedometer",
                color: averageLatencyMs < 40 ? Theme.signalEmerald : (averageLatencyMs < 80 ? Theme.solarAmber : Color.red)
            )

            kpiCard(
                title: "ANOMALIES DETECTED",
                value: "\(anomaliesCount)",
                sub: "Loss or timeouts",
                icon: "exclamationmark.triangle.fill",
                color: anomaliesCount > 0 ? Theme.solarAmber : Theme.signalEmerald
            )
        }
    }

    private func kpiCard(title: String, value: String, sub: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.monoText(9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(Theme.monoText(16, weight: .bold))
                    .foregroundStyle(.primary)
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .engineeringCard(padding: 10)
    }

    // MARK: - Filter Toolbar

    private var filterToolbar: some View {
        HStack(spacing: 12) {
            // Search Input
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter by target, summary, or IP...", text: $filterQuery)
                    .textFieldStyle(.plain)
                if !filterQuery.isEmpty {
                    Button(action: { filterQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Status Filter
            Picker("Status", selection: $selectedStatus) {
                ForEach(StatusFilter.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .frame(width: 130)

            // Target Type Filter
            Picker("Type", selection: $selectedTargetType) {
                ForEach(availableTargetTypes, id: \.self) { t in
                    Text(t).tag(t)
                }
            }
            .frame(width: 140)

            // Time Filter
            Picker("Time", selection: $selectedTimeFilter) {
                ForEach(TimeFilter.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .frame(width: 140)

            // Limit Selector
            Picker("Limit", selection: $fetchLimit) {
                Text("25").tag(25)
                Text("50").tag(50)
                Text("100").tag(100)
                Text("500").tag(500)
            }
            .frame(width: 80)
            .onChange(of: fetchLimit) { _, newLimit in
                state.refreshHistory(limit: newLimit)
            }
        }
    }

    // MARK: - Empty State

    private var emptyHistoryView: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 44))
                .foregroundStyle(Theme.cyanPulse.opacity(0.4))
            Text("No Matching Diagnostic Runs Found")
                .font(.system(size: 16, weight: .bold))
            Text("Try broadening your search query, adjusting your status filter, or execute a new test in the Diagnose workspace.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 12) {
                Button("Reset Filters") {
                    filterQuery = ""
                    selectedStatus = .all
                    selectedTargetType = "All Types"
                    selectedTimeFilter = .all
                }
                .buttonStyle(.bordered)

                Button("Run New Diagnostic") {
                    state.selectedWorkspace = .diagnose
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyanPulse)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - History Table

    private var historyDataTable: some View {
        Table(filteredHistory) {
            TableColumn("Health") { item in
                protocolHealthDots(item)
            }
            .width(60)

            TableColumn("Target") { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.target)
                        .font(Theme.monoText(12, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(item.targetType)
                        .font(Theme.monoText(9))
                        .foregroundStyle(.secondary)
                }
            }
            .width(170)

            TableColumn("RTT Latency") { item in
                if let lat = item.pingLatency {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(latencyColor(lat))
                            .frame(width: 6, height: 6)
                        Text(String(format: "%.1f ms", lat))
                            .font(Theme.monoText(11, weight: .semibold))
                            .foregroundStyle(latencyColor(lat))
                    }
                } else {
                    Text("Timeout")
                        .font(Theme.monoText(10))
                        .foregroundStyle(.red)
                }
            }
            .width(95)

            TableColumn("Loss") { item in
                if let loss = item.packetLoss {
                    Text(String(format: "%.1f%%", loss))
                        .font(Theme.monoText(11, weight: .semibold))
                        .foregroundStyle(loss > 0 ? Color.red : Theme.signalEmerald)
                } else {
                    Text("-").foregroundStyle(.secondary)
                }
            }
            .width(60)

            TableColumn("HTTP") { item in
                if let status = item.httpStatus {
                    Text("\(status)")
                        .font(Theme.monoText(10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(httpStatusColor(status).opacity(0.15))
                        .foregroundStyle(httpStatusColor(status))
                        .clipShape(Capsule())
                } else {
                    Text("-").foregroundStyle(.secondary)
                }
            }
            .width(60)

            TableColumn("Summary") { item in
                Text(item.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TableColumn("Timestamp") { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(relativeTime(item.timestamp))
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(Date(timeIntervalSince1970: item.timestamp).formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .width(130)

            TableColumn("Actions") { item in
                rowActions(item)
            }
            .width(170)
        }
    }

    // Protocol mini dots (DNS, ICMP, TCP, TLS/HTTP)
    private func protocolHealthDots(_ item: DiagnosticHistoryRecord) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(item.dnsHealthy ? Theme.signalEmerald : Color.red)
                .frame(width: 6, height: 6)
                .help(item.dnsHealthy ? "DNS Resolution: Passed" : "DNS Resolution: Failed")

            Circle()
                .fill((item.pingLatency != nil && (item.packetLoss ?? 0) < 50) ? Theme.signalEmerald : Color.red)
                .frame(width: 6, height: 6)
                .help((item.pingLatency != nil) ? "ICMP Ping: OK" : "ICMP Ping: Failed")

            Circle()
                .fill(item.tcpHealthy ? Theme.signalEmerald : Color.red)
                .frame(width: 6, height: 6)
                .help(item.tcpHealthy ? "TCP Handshake: OK" : "TCP Handshake: Failed")

            Circle()
                .fill(item.tlsHealthy ? Theme.signalEmerald : Color.orange)
                .frame(width: 6, height: 6)
                .help(item.tlsHealthy ? "TLS/Security: Valid" : "TLS/Security: Anomaly")
        }
    }

    private func rowActions(_ item: DiagnosticHistoryRecord) -> some View {
        HStack(spacing: 6) {
            // Inspect Button
            Button(action: { inspectRecord = item }) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Inspect full diagnostic snapshot")

            // Re-Test Button
            Button(action: {
                state.retestHistoryTarget(item)
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Re-run diagnostic on this target")

            // Promote to Investigation Button
            Button(action: {
                state.createInvestigationFromHistoryRecord(item)
            }) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Promote this test to an Investigation incident")

            // More Menu (Compare, Delete)
            Menu {
                Button("Set as Comparison Run 1") {
                    comparisonFirst = item
                    state.toastMessage = "Set Run 1: \(item.target)"
                }
                Button("Set as Comparison Run 2") {
                    comparisonSecond = item
                    state.toastMessage = "Set Run 2: \(item.target)"
                }
                Divider()
                Button("Delete Record", role: .destructive) {
                    state.deleteHistoryRecord(id: item.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10))
            }
            .menuStyle(.borderlessButton)
        }
    }

    // MARK: - Diagnostic Snapshot Inspector Modal

    private func diagnosticSnapshotInspector(_ rec: DiagnosticHistoryRecord) -> some View {
        VStack(spacing: 16) {
            // Inspector Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("DIAGNOSTIC SNAPSHOT")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(Theme.cyanPulse)
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(rec.targetType.uppercased())
                            .font(Theme.monoText(10))
                            .foregroundStyle(.secondary)
                    }
                    Text(rec.target)
                        .font(.system(size: 18, weight: .bold))
                }

                Spacer()

                Button("Close") { inspectRecord = nil }
                    .buttonStyle(.plain)
            }

            Divider().overlay(Theme.borderLight)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Overall Summary Card
                    HStack(spacing: 12) {
                        Image(systemName: rec.tcpHealthy ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(rec.tcpHealthy ? Theme.signalEmerald : Color.red)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(rec.summary)
                                .font(.system(size: 13, weight: .semibold))
                            Text("Recorded on \(Date(timeIntervalSince1970: rec.timestamp).formatted(date: .complete, time: .complete))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Multi-Layer Protocol Breakdown
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        layerInspectionCard(
                            layer: "DNS RESOLUTION",
                            status: rec.dnsHealthy ? "HEALTHY" : "FAILED",
                            color: rec.dnsHealthy ? Theme.signalEmerald : Color.red,
                            details: rec.dnsHealthy ? "Upstream DNS resolved successfully" : "DNS lookup failed or timed out"
                        )

                        layerInspectionCard(
                            layer: "ICMP LATENCY",
                            status: rec.pingLatency != nil ? String(format: "%.1f ms", rec.pingLatency!) : "TIMEOUT",
                            color: rec.pingLatency != nil ? latencyColor(rec.pingLatency!) : Color.red,
                            details: "Packet Loss: \(String(format: "%.1f%%", rec.packetLoss ?? 0.0))"
                        )

                        layerInspectionCard(
                            layer: "TCP TRANSPORT",
                            status: rec.tcpHealthy ? "PORT OPEN" : "REFUSED / DOWN",
                            color: rec.tcpHealthy ? Theme.signalEmerald : Color.red,
                            details: rec.tcpHealthy ? "SYN-ACK handshake verified" : "No TCP response on target port"
                        )

                        layerInspectionCard(
                            layer: "TLS & APPLICATION",
                            status: rec.httpStatus != nil ? "HTTP \(rec.httpStatus!)" : (rec.tlsHealthy ? "VALID" : "ANOMALY"),
                            color: rec.tlsHealthy ? Theme.signalEmerald : Color.orange,
                            details: rec.tlsHealthy ? "Certificate valid & trusted" : "Certificate expired or untrusted"
                        )
                    }

                    // Raw Telemetry JSON Payload
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("RAW TELEMETRY JSON DATA")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(rec.rawJson, forType: .string)
                                copiedJsonId = rec.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    if copiedJsonId == rec.id { copiedJsonId = nil }
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedJsonId == rec.id ? "checkmark" : "doc.on.doc")
                                    Text(copiedJsonId == rec.id ? "Copied JSON" : "Copy JSON")
                                }
                                .font(.system(size: 10))
                            }
                            .buttonStyle(.bordered)
                        }

                        Text(rec.rawJson.isEmpty || rec.rawJson == "{}" ? "{\n  \"target\": \"\(rec.target)\",\n  \"status\": \"\(rec.summary)\"\n}" : rec.rawJson)
                            .font(Theme.monoText(10))
                            .foregroundStyle(Theme.cyanPulse)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .textSelection(.enabled)
                    }
                }
            }

            // Modal Actions Footer
            HStack(spacing: 12) {
                Button(action: {
                    state.retestHistoryTarget(rec)
                    inspectRecord = nil
                }) {
                    Label("Re-Test Target Now", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    state.createInvestigationFromHistoryRecord(rec)
                    inspectRecord = nil
                }) {
                    Label("Promote to Investigation", systemImage: "briefcase.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.quantumViolet)
            }
        }
        .padding(24)
        .frame(width: 580, height: 560)
        .background(Theme.secondaryBackground)
    }

    private func layerInspectionCard(layer: String, status: String, color: Color, details: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(layer)
                    .font(Theme.monoText(9, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(status)
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(color)
            }
            Text(details)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
        }
        .engineeringCard(padding: 10)
    }

    // MARK: - Run Comparison Modal

    private var runComparisonSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Side-by-Side Diagnostic Run Comparison", systemImage: "arrow.left.and.right.square.fill")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Close") { isShowingComparison = false }
                    .buttonStyle(.plain)
            }

            Divider().overlay(Theme.borderLight)

            if let r1 = comparisonFirst, let r2 = comparisonSecond {
                ScrollView {
                    VStack(spacing: 14) {
                        // Header comparison
                        HStack(spacing: 16) {
                            comparisonTargetPill(label: "RUN 1 (Baseline)", rec: r1)
                            comparisonTargetPill(label: "RUN 2 (Comparison)", rec: r2)
                        }

                        // Metrics Matrix
                        VStack(spacing: 8) {
                            comparisonRow(
                                title: "Recorded Timestamp",
                                val1: Date(timeIntervalSince1970: r1.timestamp).formatted(),
                                val2: Date(timeIntervalSince1970: r2.timestamp).formatted()
                            )

                            comparisonRow(
                                title: "DNS Status",
                                val1: r1.dnsHealthy ? "Healthy" : "Failed",
                                val2: r2.dnsHealthy ? "Healthy" : "Failed",
                                highlightDiff: r1.dnsHealthy != r2.dnsHealthy
                            )

                            let lat1 = r1.pingLatency ?? 0
                            let lat2 = r2.pingLatency ?? 0
                            let delta = lat2 - lat1
                            comparisonRow(
                                title: "RTT Latency",
                                val1: String(format: "%.1f ms", lat1),
                                val2: String(format: "%.1f ms (%@%.1f ms)", lat2, delta >= 0 ? "+" : "", delta),
                                highlightDiff: abs(delta) > 5.0
                            )

                            comparisonRow(
                                title: "Packet Loss",
                                val1: String(format: "%.1f%%", r1.packetLoss ?? 0),
                                val2: String(format: "%.1f%%", r2.packetLoss ?? 0),
                                highlightDiff: (r1.packetLoss ?? 0) != (r2.packetLoss ?? 0)
                            )

                            comparisonRow(
                                title: "TCP Connection",
                                val1: r1.tcpHealthy ? "Connected" : "Refused",
                                val2: r2.tcpHealthy ? "Connected" : "Refused",
                                highlightDiff: r1.tcpHealthy != r2.tcpHealthy
                            )

                            comparisonRow(
                                title: "HTTP Status",
                                val1: r1.httpStatus != nil ? "\(r1.httpStatus!)" : "N/A",
                                val2: r2.httpStatus != nil ? "\(r2.httpStatus!)" : "N/A",
                                highlightDiff: r1.httpStatus != r2.httpStatus
                            )
                        }
                        .engineeringCard(padding: 14)
                    }
                }
            } else {
                Text("Select two history records using row menus to view diff.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 620, height: 480)
        .background(Theme.secondaryBackground)
    }

    private func comparisonTargetPill(label: String, rec: DiagnosticHistoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.monoText(9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(rec.target)
                .font(Theme.monoText(13, weight: .bold))
                .foregroundStyle(.primary)
            Text(rec.targetType)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func comparisonRow(title: String, val1: String, val2: String, highlightDiff: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)

            Text(val1)
                .font(Theme.monoText(11, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            Text(val2)
                .font(Theme.monoText(11, weight: .bold))
                .foregroundStyle(highlightDiff ? Theme.solarAmber : Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Purge Options Sheet

    private var purgeOptionsSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Purge Historic Records", systemImage: "trash")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Cancel") { showingPurgeSheet = false }
                    .buttonStyle(.plain)
            }

            Text("Select an age threshold to purge old diagnostic logs and reclaim SQLite storage space:")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Picker("Purge Records Older Than", selection: $purgeDays) {
                Text("Older than 7 days").tag(7)
                Text("Older than 14 days").tag(14)
                Text("Older than 30 days").tag(30)
                Text("Older than 90 days").tag(90)
            }
            .pickerStyle(.radioGroup)
            .padding(10)

            HStack(spacing: 12) {
                Button("Purge Selected Records", role: .destructive) {
                    state.purgeHistory(olderThanDays: purgeDays)
                    showingPurgeSheet = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Theme.secondaryBackground)
    }

    // MARK: - Export Logic

    private func exportHistoryCSV() {
        var csv = "Target,TargetType,Timestamp,DateTime,DNSHealthy,PingLatencyMs,PacketLossPct,TCPHealthy,TLSHealthy,HTTPStatus,Summary\n"
        for rec in filteredHistory {
            let dt = Date(timeIntervalSince1970: rec.timestamp).formatted()
            let cleanSummary = rec.summary.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\"\(rec.target)\",\"\(rec.targetType)\",\(rec.timestamp),\"\(dt)\",\(rec.dnsHealthy),\(rec.pingLatency ?? 0),\(rec.packetLoss ?? 0),\(rec.tcpHealthy),\(rec.tlsHealthy),\(rec.httpStatus ?? 0),\"\(cleanSummary)\"\n"
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NexWave_Diagnostic_History.csv"
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                try? csv.write(to: url, atomically: true, encoding: .utf8)
                state.toastMessage = "Exported history to \(url.lastPathComponent)"
            }
        }
    }

    private func exportHistoryJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(filteredHistory),
              let json = String(data: data, encoding: .utf8) else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NexWave_Diagnostic_History.json"
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                try? json.write(to: url, atomically: true, encoding: .utf8)
                state.toastMessage = "Exported history JSON to \(url.lastPathComponent)"
            }
        }
    }

    // MARK: - Helpers

    private func latencyColor(_ lat: Double) -> Color {
        if lat < 30.0 { return Theme.signalEmerald }
        if lat < 80.0 { return Theme.solarAmber }
        return Color.red
    }

    private func httpStatusColor(_ st: Int) -> Color {
        if st >= 200 && st < 300 { return Theme.signalEmerald }
        if st >= 300 && st < 400 { return Theme.azurePro }
        if st >= 400 && st < 500 { return Theme.solarAmber }
        return Color.red
    }

    private func relativeTime(_ ts: Double) -> String {
        let delta = Date().timeIntervalSince1970 - ts
        if delta < 60 { return "Just now" }
        if delta < 3600 { return "\(Int(delta / 60))m ago" }
        if delta < 86400 { return "\(Int(delta / 3600))h ago" }
        return "\(Int(delta / 86400))d ago"
    }
}
