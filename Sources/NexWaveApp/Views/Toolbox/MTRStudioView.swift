import SwiftUI
import TracerouteEngine
import NetworkCore

public struct MTRStudioView: View {
    @State private var targetInput: String = "1.1.1.1"
    @State private var intervalSeconds: Double = 1.0
    @State private var maxHops: Int = 15
    @State private var isRunning: Bool = false
    @State private var mtrReport: MTRReport? = nil

    private let runner = MTRContinuousRunner()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Control Card
                headerControlCard

                if let report = mtrReport, !report.hops.isEmpty {
                    // Summary Telemetry Pill Bar
                    summaryTelemetryBar(report: report)

                    // Hop Table
                    hopTableCard(report: report)
                } else {
                    emptyStateCard
                }
            }
            .padding(24)
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("Continuous MTR Path Monitor")
        .onDisappear {
            Task {
                await runner.pause()
            }
        }
    }

    // MARK: - Header Control Card
    private var headerControlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CONTINUOUS MTR PATH MONITOR")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.neonCyan)
                Spacer()
                Text("RFC 3550 Jitter • Multi-Path Hop Drift • Real-Time Telemetry")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.neonCyan)

                TextField("Enter destination IP or hostname (e.g. 1.1.1.1, 8.8.8.8, cloudflare.com)...", text: $targetInput)
                    .textFieldStyle(.plain)
                    .font(Theme.monoText(15))
                    .disabled(isRunning)

                // Start / Pause Button
                Button(action: toggleMTR) {
                    HStack(spacing: 6) {
                        Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        Text(isRunning ? "Pause Probing" : "Start MTR")
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(isRunning ? AnyShapeStyle(Theme.solarAmber) : AnyShapeStyle(Theme.cyanGlowGradient))
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                // Reset Button
                Button(action: resetMTR) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.primary.opacity(0.06))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Reset statistical counters")
            }
            .padding(12)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cyanPulse.opacity(0.3), lineWidth: 1))

            // Probing Options
            HStack {
                HStack(spacing: 8) {
                    Text("Probe Interval:").font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach([1.0, 2.0, 5.0], id: \.self) { sec in
                        Button("\(Int(sec))s") {
                            intervalSeconds = sec
                            if isRunning { toggleMTR(); toggleMTR() }
                        }
                        .buttonStyle(.plain)
                        .font(Theme.monoText(10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(intervalSeconds == sec ? Theme.neonCyan.opacity(0.2) : Color.primary.opacity(0.04))
                        .foregroundStyle(intervalSeconds == sec ? Theme.neonCyan : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("Max TTL:").font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach([15, 20, 30], id: \.self) { hops in
                        Button("\(hops)") {
                            maxHops = hops
                            if isRunning { toggleMTR(); toggleMTR() }
                        }
                        .buttonStyle(.plain)
                        .font(Theme.monoText(10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(maxHops == hops ? Theme.azurePro.opacity(0.2) : Color.primary.opacity(0.04))
                        .foregroundStyle(maxHops == hops ? Theme.azurePro : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - Summary Telemetry Bar
    private func summaryTelemetryBar(report: MTRReport) -> some View {
        let hasAnyDrift = report.hops.contains(where: { $0.hasDrift })
        let avgLoss = report.hops.isEmpty ? 0.0 : report.hops.reduce(0.0) { $0 + $1.lossPercent } / Double(report.hops.count)

        return HStack(spacing: 14) {
            HUDStatusBadge(
                title: isRunning ? "PROBING ACTIVE (\(report.roundCount) ROUNDS)" : "PAUSED (\(report.roundCount) ROUNDS)",
                color: isRunning ? Theme.signalEmerald : Theme.solarAmber,
                isPulsing: isRunning,
                icon: isRunning ? "waveform.badge.magnifyingglass" : "pause.circle"
            )

            HStack(spacing: 6) {
                Text("Target:").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(report.target).font(Theme.monoText(11, weight: .bold)).foregroundStyle(Theme.neonCyan)
            }

            HStack(spacing: 6) {
                Text("Discovered Hops:").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("\(report.hops.count)").font(Theme.monoText(11, weight: .bold))
            }

            HStack(spacing: 6) {
                Text("Path Loss Avg:").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(String(format: "%.1f%%", avgLoss))
                    .font(Theme.monoText(11, weight: .bold))
                    .foregroundStyle(avgLoss > 5 ? Theme.pulseCrimson : (avgLoss > 0 ? Theme.solarAmber : Theme.signalEmerald))
            }

            Spacer()

            if hasAnyDrift {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                    Text("ECMP / ROUTE DRIFT DETECTED")
                }
                .font(Theme.monoText(9, weight: .bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.solarAmber.opacity(0.18))
                .foregroundStyle(Theme.solarAmber)
                .clipShape(Capsule())
            }
        }
        .engineeringCard(padding: 12)
    }

    // MARK: - Hop Table Card
    private func hopTableCard(report: MTRReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Table Header
            HStack {
                Text("HOP").frame(width: 40, alignment: .leading)
                Text("HOST / IP ADDRESS").frame(minWidth: 180, alignment: .leading)
                Text("LOSS %").frame(width: 70, alignment: .trailing)
                Text("SENT").frame(width: 45, alignment: .trailing)
                Text("LAST").frame(width: 60, alignment: .trailing)
                Text("AVG").frame(width: 60, alignment: .trailing)
                Text("BEST").frame(width: 60, alignment: .trailing)
                Text("WRST").frame(width: 60, alignment: .trailing)
                Text("STDEV").frame(width: 60, alignment: .trailing)
                Text("JITTER").frame(width: 60, alignment: .trailing)
                Text("RTT TREND (30S)").frame(width: 100, alignment: .center)
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.03))

            Divider()

            // Hop Rows
            VStack(spacing: 0) {
                ForEach(report.hops) { hop in
                    hopRow(hop: hop)
                    if hop.hopNumber != report.hops.last?.hopNumber {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderLight, lineWidth: 1))
    }

    private func hopRow(hop: MTRHopSnapshot) -> some View {
        HStack {
            Text("\(hop.hopNumber)")
                .font(Theme.monoText(11, weight: .bold))
                .foregroundStyle(Theme.neonCyan)
                .frame(width: 40, alignment: .leading)

            HStack(spacing: 6) {
                Text(hop.primaryAddress ?? "* * * (Timeout / Rate-Limited)")
                    .font(Theme.monoText(12, weight: hop.primaryAddress != nil ? .medium : .regular))
                    .foregroundStyle(hop.primaryAddress != nil ? Color.primary : .secondary.opacity(0.6))
                    .lineLimit(1)

                if hop.hasDrift {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.solarAmber)
                        .help("Multiple transit IPs discovered for this hop: \(hop.allDiscoveredAddresses.joined(separator: ", "))")
                }
            }
            .frame(minWidth: 180, alignment: .leading)

            // Loss %
            Text(String(format: "%.1f%%", hop.lossPercent))
                .font(Theme.monoText(11, weight: .bold))
                .foregroundStyle(hop.lossPercent > 20 ? Theme.pulseCrimson : (hop.lossPercent > 0 ? Theme.solarAmber : Theme.signalEmerald))
                .frame(width: 70, alignment: .trailing)

            Text("\(hop.sent)")
                .font(Theme.monoText(11))
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .trailing)

            Text(hop.lastRTT.map { String(format: "%.1f", $0) } ?? "-")
                .font(Theme.monoText(11))
                .foregroundStyle(hop.lastRTT != nil ? Color.primary : .secondary)
                .frame(width: 60, alignment: .trailing)

            Text(hop.avgRTT > 0 ? String(format: "%.1f", hop.avgRTT) : "-")
                .font(Theme.monoText(11, weight: .semibold))
                .foregroundStyle(Theme.azurePro)
                .frame(width: 60, alignment: .trailing)

            Text(hop.bestRTT.map { String(format: "%.1f", $0) } ?? "-")
                .font(Theme.monoText(11))
                .foregroundStyle(Theme.signalEmerald)
                .frame(width: 60, alignment: .trailing)

            Text(hop.worstRTT.map { String(format: "%.1f", $0) } ?? "-")
                .font(Theme.monoText(11))
                .foregroundStyle(Theme.pulseCrimson)
                .frame(width: 60, alignment: .trailing)

            Text(hop.stDev > 0 ? String(format: "%.1f", hop.stDev) : "-")
                .font(Theme.monoText(11))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            Text(hop.lastJitter > 0 ? String(format: "%.1f", hop.lastJitter) : "-")
                .font(Theme.monoText(11))
                .foregroundStyle(hop.lastJitter > 15 ? Theme.solarAmber : .secondary)
                .frame(width: 60, alignment: .trailing)

            // Mini sparkline
            miniSparkline(history: hop.history)
                .frame(width: 100, height: 18)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(hop.hasDrift ? Theme.solarAmber.opacity(0.04) : Color.clear)
    }

    private func miniSparkline(history: [Double?]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let valid = history.compactMap { $0 }
            let maxVal = max(valid.max() ?? 10.0, 5.0)

            Path { path in
                guard history.count > 1 else { return }
                let stepX = w / CGFloat(history.count - 1)

                var started = false
                for (i, val) in history.enumerated() {
                    let x = CGFloat(i) * stepX
                    if let v = val {
                        let y = h - (CGFloat(v / maxVal) * (h - 4)) - 2
                        if !started {
                            path.move(to: CGPoint(x: x, y: y))
                            started = true
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
            }
            .stroke(Theme.neonCyan, lineWidth: 1.5)
        }
    }

    // MARK: - Empty State
    private var emptyStateCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.neonCyan.opacity(0.08))
                    .frame(width: 64, height: 64)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.neonCyan)
            }

            Text("Ready for Continuous MTR Analysis")
                .font(.system(size: 16, weight: .bold))

            Text("Click 'Start MTR' to begin live round-robin TTL path monitoring with jitter, standard deviation, and dynamic route drift detection.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .engineeringCard()
    }

    // MARK: - Actions
    private func toggleMTR() {
        if isRunning {
            isRunning = false
            Task {
                await runner.pause()
            }
        } else {
            let target = targetInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty else { return }
            isRunning = true

            Task {
                await runner.start(target: target, maxHops: maxHops, intervalSeconds: intervalSeconds) { update in
                    Task { @MainActor in
                        self.mtrReport = update
                    }
                }
            }
        }
    }

    private func resetMTR() {
        isRunning = false
        Task {
            await runner.reset()
            await MainActor.run {
                self.mtrReport = nil
            }
        }
    }
}
