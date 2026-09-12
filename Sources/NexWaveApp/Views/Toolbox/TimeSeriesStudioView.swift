import SwiftUI
import TimeSeriesKit
import PersistenceKit

public struct TimeSeriesStudioView: View {
    @State private var targets: [MonitorTargetConfig] = [
        MonitorTargetConfig(target: "172.16.16.1", name: "Default Gateway", intervalSeconds: 2.5, latencyThresholdMs: 50.0, packetLossThresholdPct: 5.0),
        MonitorTargetConfig(target: "1.1.1.1", name: "Cloudflare DNS", intervalSeconds: 2.5, latencyThresholdMs: 60.0, packetLossThresholdPct: 5.0),
        MonitorTargetConfig(target: "8.8.8.8", name: "Google Anycast DNS", intervalSeconds: 2.5, latencyThresholdMs: 70.0, packetLossThresholdPct: 5.0)
    ]
    @State private var selectedTargetIndex: Int = 0
    @State private var selectedRange: TimeRange = .lastHour
    @State private var buckets: [AggregatedBucket] = []
    @State private var alerts: [SLAMonitorAlert] = []

    // Scrubber hover state
    @State private var scrubIndex: Int? = nil
    @State private var isShowingAddSheet = false
    @State private var newTargetHost = ""
    @State private var newTargetName = ""

    // Service & Repo
    @State private var repository: TimeSeriesRepository? = nil
    @State private var monitorService: BackgroundMonitorService? = nil
    @State private var refreshTimer: Task<Void, Never>? = nil

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerBar
                controlBar
                timelineCanvasCard
                summaryMetricsGrid
                alertsSection
            }
            .padding(20)
        }
        .background(Theme.surfaceBackground)
        .onAppear {
            setupEngine()
        }
        .onDisappear {
            stopPolling()
        }
        .sheet(isPresented: $isShowingAddSheet) {
            addTargetSheet
        }
    }

    private var activeConfig: MonitorTargetConfig? {
        guard selectedTargetIndex < targets.count else { return nil }
        return targets[selectedTargetIndex]
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.neonCyan)
                    Text("Timeline & SLA Monitor")
                        .font(.title2.bold())
                    Text("PingPlotter Class")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.cyanPulse.opacity(0.18))
                        .foregroundStyle(Theme.neonCyan)
                        .clipShape(Capsule())
                }
                Text("Continuous multi-day background latency tracking, packet loss scrub timeline, and automated SLA breach detection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            // Target Picker
            Picker("", selection: $selectedTargetIndex) {
                ForEach(0..<targets.count, id: \.self) { idx in
                    Text("\(targets[idx].name) (\(targets[idx].target))").tag(idx)
                }
            }
            .frame(width: 280)
            .onChange(of: selectedTargetIndex) { _, _ in
                loadData()
            }

            // Add Target Button
            Button(action: { isShowingAddSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text("Add Target")
                }
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.azurePro.opacity(0.15))
                .foregroundStyle(Theme.azurePro)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Spacer()

            // Range Segmented Picker
            Picker("", selection: $selectedRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            .onChange(of: selectedRange) { _, _ in
                loadData()
            }

            // Refresh Button
            Button(action: loadData) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .padding(6)
                    .background(Theme.cardBackground)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Refresh timeline data")
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderLight, lineWidth: 1))
    }

    // MARK: - Timeline Canvas & Interactive Scrubber

    private var timelineCanvasCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Theme.signalEmerald).frame(width: 8, height: 8)
                    Text(activeConfig != nil ? "\(activeConfig!.name) • \(selectedRange.displayName)" : "Timeline")
                        .font(.subheadline.bold())
                }
                Spacer()

                if let idx = scrubIndex, idx < buckets.count {
                    let b = buckets[idx]
                    HStack(spacing: 12) {
                        Text(b.timestamp, style: .time)
                            .font(Theme.monoText(10))
                            .foregroundStyle(.secondary)
                        Text("Avg: \(String(format: "%.1f ms", b.avgMs))")
                            .font(Theme.monoText(11, weight: .bold))
                            .foregroundStyle(Theme.neonCyan)
                        Text("Min/Max: \(String(format: "%.1f", b.minMs))/\(String(format: "%.1f", b.maxMs)) ms")
                            .font(Theme.monoText(10))
                            .foregroundStyle(.secondary)
                        if b.packetLossPct > 0 {
                            Text("Loss: \(String(format: "%.1f%%", b.packetLossPct))")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(Theme.pulseCrimson)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Theme.secondaryBackground)
                    .cornerRadius(6)
                } else {
                    Text("Hover / drag timeline to inspect point-in-time metrics")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Canvas Chart
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height

                Canvas { context, size in
                    guard !buckets.isEmpty else { return }

                    let maxLatency = max(60.0, (buckets.map { $0.maxMs }.max() ?? 60.0) * 1.15)
                    let stepX = width / CGFloat(max(1, buckets.count - 1))

                    // Draw Background Grid Lines
                    for yFraction in [0.25, 0.5, 0.75, 1.0] {
                        let y = height - (height * CGFloat(yFraction) * 0.85)
                        var gridPath = Path()
                        gridPath.move(to: CGPoint(x: 0, y: y))
                        gridPath.addLine(to: CGPoint(x: width, y: y))
                        context.stroke(gridPath, with: .color(Color.primary.opacity(0.06)), lineWidth: 1)

                        let latValue = maxLatency * yFraction
                        let text = Text("\(Int(latValue))ms").font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary.opacity(0.6))
                        context.draw(text, at: CGPoint(x: 18, y: y - 6))
                    }

                    // Draw Packet Loss Red Columns
                    for (i, b) in buckets.enumerated() {
                        if b.packetLossPct > 0 {
                            let x = CGFloat(i) * stepX
                            let colWidth = max(2.0, stepX * 0.8)
                            let lossHeight = height * CGFloat(b.packetLossPct / 100.0)
                            let rect = CGRect(x: x - colWidth / 2, y: height - lossHeight, width: colWidth, height: lossHeight)
                            context.fill(Path(rect), with: .color(Theme.pulseCrimson.opacity(0.35)))
                        }
                    }

                    // Draw Latency Line & Gradient Fill
                    var linePath = Path()
                    var areaPath = Path()
                    areaPath.move(to: CGPoint(x: 0, y: height))

                    for (i, b) in buckets.enumerated() {
                        let x = CGFloat(i) * stepX
                        let normalizedY = height - (height * CGFloat(b.avgMs / maxLatency) * 0.85)
                        let pt = CGPoint(x: x, y: max(10, min(height, normalizedY)))

                        if i == 0 {
                            linePath.move(to: pt)
                            areaPath.addLine(to: pt)
                        } else {
                            linePath.addLine(to: pt)
                            areaPath.addLine(to: pt)
                        }
                    }

                    if let last = buckets.indices.last {
                        let lastX = CGFloat(last) * stepX
                        areaPath.addLine(to: CGPoint(x: lastX, y: height))
                        areaPath.closeSubpath()
                    }

                    // Gradient Fill under the line
                    let gradient = Gradient(colors: [Theme.neonCyan.opacity(0.25), Theme.azurePro.opacity(0.02)])
                    context.fill(areaPath, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: height)))

                    // Stroke Latency Line
                    context.stroke(linePath, with: .color(Theme.neonCyan), lineWidth: 2)

                    // Draw Scrubber Line if active
                    if let sIdx = scrubIndex, sIdx < buckets.count {
                        let sx = CGFloat(sIdx) * stepX
                        var scrubPath = Path()
                        scrubPath.move(to: CGPoint(x: sx, y: 0))
                        scrubPath.addLine(to: CGPoint(x: sx, y: height))
                        context.stroke(scrubPath, with: .color(Color.white.opacity(0.8)), lineWidth: 1.5)

                        let b = buckets[sIdx]
                        let sy = height - (height * CGFloat(b.avgMs / maxLatency) * 0.85)
                        let circleRect = CGRect(x: sx - 4, y: sy - 4, width: 8, height: 8)
                        context.fill(Path(ellipseIn: circleRect), with: .color(Theme.signalEmerald))
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let stepX = width / CGFloat(max(1, buckets.count - 1))
                            let idx = Int(round(value.location.x / stepX))
                            if idx >= 0 && idx < buckets.count {
                                scrubIndex = idx
                            }
                        }
                        .onEnded { _ in
                            scrubIndex = nil
                        }
                )
            }
            .frame(height: 220)
            .background(Color.primary.opacity(0.02))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
        }
        .padding(16)
        .background(Theme.cardBackground)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderLight, lineWidth: 1))
    }

    // MARK: - Summary Metrics Grid

    private var summaryMetricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricTile(title: "MIN RTT", value: String(format: "%.1f ms", calcMin()), color: Theme.signalEmerald, icon: "arrow.down.to.line")
            metricTile(title: "AVG RTT", value: String(format: "%.1f ms", calcAvg()), color: Theme.neonCyan, icon: "chart.bar.fill")
            metricTile(title: "MAX RTT", value: String(format: "%.1f ms", calcMax()), color: Theme.solarAmber, icon: "arrow.up.to.line")
            metricTile(title: "RFC 3550 JITTER", value: String(format: "%.1f ms", calcJitter()), color: Theme.azurePro, icon: "waveform.path")
            metricTile(
                title: "PACKET LOSS",
                value: String(format: "%.1f%%", calcLoss()),
                color: calcLoss() > 0 ? Theme.pulseCrimson : Theme.signalEmerald,
                icon: "exclamationmark.triangle.fill"
            )
        }
    }

    private func metricTile(title: String, value: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(Theme.monoText(16, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
    }

    // MARK: - SLA Alerts Section

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(Theme.solarAmber)
                    Text("SLA Breach & Anomaly History (\(alerts.count))")
                        .font(.headline.bold())
                }
                Spacer()
                if let cfg = activeConfig {
                    Text("SLA Limits: Loss > \(Int(cfg.packetLossThresholdPct))% • Latency > \(Int(cfg.latencyThresholdMs))ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if alerts.isEmpty {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(Theme.signalEmerald)
                    Text("Zero SLA violations recorded. Latency and packet loss are well within configured engineering thresholds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground)
                .cornerRadius(8)
            } else {
                VStack(spacing: 6) {
                    ForEach(alerts.prefix(8)) { alert in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: alert.alertType.badgeColor))
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(alert.alertType.rawValue)
                                        .font(.caption.bold())
                                        .foregroundStyle(Color(hex: alert.alertType.badgeColor))
                                    Text("• \(alert.targetName) (\(alert.target))")
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(alert.timestamp, style: .time)
                                        .font(Theme.monoText(10))
                                        .foregroundStyle(.secondary)
                                }
                                Text(alert.message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(Theme.cardBackground)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))
                    }
                }
            }
        }
    }

    // MARK: - Add Target Sheet

    private var addTargetSheet: some View {
        VStack(spacing: 16) {
            Text("Add Continuous Monitor Target")
                .font(.headline.bold())

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target IP or Hostname").font(.caption.bold())
                    TextField("e.g. 192.168.1.1 or vpn.corp.com", text: $newTargetHost)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Display Name").font(.caption.bold())
                    TextField("e.g. Branch Router or Core Switch", text: $newTargetName)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.vertical, 8)

            HStack {
                Button("Cancel") {
                    isShowingAddSheet = false
                }
                Spacer()
                Button("Add & Start Monitoring") {
                    let host = newTargetHost.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !host.isEmpty else { return }
                    let name = newTargetName.isEmpty ? host : newTargetName
                    let config = MonitorTargetConfig(target: host, name: name)
                    targets.append(config)
                    Task {
                        await monitorService?.addConfig(config)
                    }
                    selectedTargetIndex = targets.count - 1
                    isShowingAddSheet = false
                    newTargetHost = ""
                    newTargetName = ""
                    loadData()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    // MARK: - Engine Setup & Data Loading

    private func setupEngine() {
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dbPath = appSupport.appendingPathComponent("NexWave/network_workbench.sqlite").path
            let db = try SQLiteDatabase(path: dbPath)
            let repo = TimeSeriesRepository(database: db)
            self.repository = repo

            let service = BackgroundMonitorService(repository: repo)
            self.monitorService = service
            Task {
                await service.updateConfigs(targets)
                await service.startAll()
            }
        } catch {
            print("Failed to initialize TimeSeriesRepository: \(error)")
        }

        loadData()
        startPolling()
    }

    private func startPolling() {
        refreshTimer?.cancel()
        refreshTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s refresh
                await MainActor.run {
                    loadData()
                }
            }
        }
    }

    private func stopPolling() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    private func loadData() {
        guard let repo = repository, let cfg = activeConfig else { return }
        let now = Date()
        let start = selectedRange.startDate(from: now)

        do {
            let b = try repo.fetchBuckets(target: cfg.target, from: start, to: now, bucketCount: selectedRange.targetBucketCount)
            self.buckets = b
            let a = try repo.fetchAlerts(target: cfg.target, limit: 10)
            self.alerts = a
        } catch {
            print("Error loading time series data: \(error)")
        }
    }

    // Calculation Helpers
    private func calcMin() -> Double {
        let valid = buckets.map { $0.minMs }.filter { $0 > 0 }
        return valid.min() ?? 0.0
    }

    private func calcMax() -> Double {
        buckets.map { $0.maxMs }.max() ?? 0.0
    }

    private func calcAvg() -> Double {
        let valid = buckets.map { $0.avgMs }.filter { $0 > 0 }
        guard !valid.isEmpty else { return 0.0 }
        return valid.reduce(0, +) / Double(valid.count)
    }

    private func calcJitter() -> Double {
        let valid = buckets.map { $0.jitterMs }
        guard !valid.isEmpty else { return 0.0 }
        return valid.reduce(0, +) / Double(valid.count)
    }

    private func calcLoss() -> Double {
        let valid = buckets.map { $0.packetLossPct }
        guard !valid.isEmpty else { return 0.0 }
        return valid.reduce(0, +) / Double(valid.count)
    }
}

