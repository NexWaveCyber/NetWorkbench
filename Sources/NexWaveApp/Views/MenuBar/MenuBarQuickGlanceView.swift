import SwiftUI
import WiFiKit

public struct MenuBarQuickGlanceView: View {
    @Bindable var monitor: MenuBarMonitorEngine
    @Bindable var state: AppState

    @Environment(\.openWindow) private var openWindow
    @State private var quickTarget: String = ""
    @State private var didFlushDNS = false
    @State private var copiedItem: String? = nil

    public init(monitor: MenuBarMonitorEngine, state: AppState) {
        self.monitor = monitor
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    uplinkCard
                    latencyMeterCard

                    if let wifi = monitor.wifiLink {
                        wifiSnapshotCard(wifi: wifi)
                    }

                    quickActionsCard
                }
                .padding(14)
            }

            Divider()
            footerBar
        }
        .frame(width: 360, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            monitor.startMonitoring()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(hex: monitor.healthStatus.colorHex).opacity(0.2))
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(Color(hex: monitor.healthStatus.colorHex))
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("NexWave Quick Glance")
                    .font(.system(size: 12, weight: .bold))
                Text(monitor.healthStatus.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: monitor.healthStatus.colorHex))
            }

            Spacer()

            Button(action: openMainApp) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11))
                    Text("Open App")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.azurePro.opacity(0.15))
                .foregroundStyle(Theme.azurePro)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Open main NexWave workbench window")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Uplink Details Card

    private var uplinkCard: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: monitor.wifiLink != nil ? "wifi" : "network")
                        .font(.caption)
                        .foregroundStyle(Theme.cyanPulse)
                    Text("Uplink (\(monitor.activeInterface))")
                        .font(.system(size: 11, weight: .bold))
                }
                Spacer()
                Text("Active Gateway")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Local IP Row
            HStack {
                Text("Local IP:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(monitor.localIP)
                    .font(Theme.monoText(11, weight: .semibold))
                Spacer()
                copyButton(text: monitor.localIP, key: "local")
            }

            // Default Gateway Row
            HStack {
                Text("Gateway:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(monitor.defaultGateway)
                    .font(Theme.monoText(11, weight: .semibold))
                Spacer()
                if let rtt = monitor.gatewayLatencyMs {
                    Text(String(format: "%.1f ms", rtt))
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(rtt <= 20 ? Theme.signalEmerald : Theme.solarAmber)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.signalEmerald.opacity(0.12))
                        .cornerRadius(4)
                }
            }

            // Public IP Row
            HStack {
                Text("Public IP:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(monitor.publicIP)
                    .font(Theme.monoText(11, weight: .semibold))
                Spacer()
                if monitor.publicIP != "Resolving..." {
                    copyButton(text: monitor.publicIP, key: "public")
                }
            }
        }
        .padding(10)
        .background(Theme.cardBackground)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
    }

    // MARK: - Latency Sparkline Card

    private var latencyMeterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Real-Time Latency Meter")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.signalEmerald).frame(width: 6, height: 6)
                        Text("Gateway")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Theme.cyanPulse).frame(width: 6, height: 6)
                        Text("Internet")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                // Gateway Latency Box
                VStack(alignment: .leading, spacing: 2) {
                    Text("GATEWAY")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(monitor.gatewayLatencyMs != nil ? String(format: "%.1f ms", monitor.gatewayLatencyMs!) : "Timeout")
                        .font(Theme.monoText(14, weight: .bold))
                        .foregroundStyle(monitor.gatewayLatencyMs != nil ? Theme.signalEmerald : Theme.pulseCrimson)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Theme.secondaryBackground.opacity(0.6))
                .cornerRadius(6)

                // Internet Latency Box
                VStack(alignment: .leading, spacing: 2) {
                    Text("INTERNET (1.1.1.1)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(monitor.internetLatencyMs != nil ? String(format: "%.1f ms", monitor.internetLatencyMs!) : "Timeout")
                        .font(Theme.monoText(14, weight: .bold))
                        .foregroundStyle(monitor.internetLatencyMs != nil ? Theme.cyanPulse : Theme.pulseCrimson)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Theme.secondaryBackground.opacity(0.6))
                .cornerRadius(6)
            }

            // Sparkline Bars
            if !monitor.gatewaySamples.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(0..<monitor.gatewaySamples.count, id: \.self) { idx in
                            let sample = monitor.gatewaySamples[idx]
                            let barHeight = max(3.0, min(24.0, CGFloat(sample) * 1.5))
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(sample <= 15 ? Theme.signalEmerald : (sample <= 50 ? Theme.solarAmber : Theme.pulseCrimson))
                                .frame(height: barHeight)
                        }
                    }
                    .frame(height: 24)
                    .padding(6)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(4)
                }
            }
        }
        .padding(10)
        .background(Theme.cardBackground)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
    }

    // MARK: - Wi-Fi Snapshot Card

    private func wifiSnapshotCard(wifi: WiFiCurrentLink) -> some View {
        VStack(spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.caption)
                        .foregroundStyle(Theme.cyanPulse)
                    Text("Wi-Fi: \(wifi.ssid)")
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                }
                Spacer()
                Text(wifi.signalQuality.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(hex: wifi.signalQuality.colorHex))
            }

            HStack {
                Text("RSSI:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(wifi.rssi) dBm")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(Color(hex: wifi.signalQuality.colorHex))

                Spacer()

                Text("Channel:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Ch \(wifi.channel) (\(wifi.channelWidth.rawValue))")
                    .font(Theme.monoText(10, weight: .semibold))

                Spacer()

                Text("PHY:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(wifi.phyMode.displayName)
                    .font(Theme.monoText(10))
            }
        }
        .padding(10)
        .background(Theme.cardBackground)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
    }

    // MARK: - Quick Actions Card

    private var quickActionsCard: some View {
        VStack(spacing: 8) {
            // Quick Host Diagnose Input
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Quick target (e.g. 8.8.8.8)...", text: $quickTarget)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit {
                        launchQuickDiagnose()
                    }

                if !quickTarget.isEmpty {
                    Button(action: launchQuickDiagnose) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(Theme.neonCyan)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))

            // Action Buttons Row
            HStack(spacing: 8) {
                Button(action: {
                    Task {
                        let success = await monitor.flushDNSCache()
                        if success {
                            didFlushDNS = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                didFlushDNS = false
                            }
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: didFlushDNS ? "checkmark.circle.fill" : "arrow.clockwise")
                            .font(.system(size: 10))
                            .foregroundStyle(didFlushDNS ? Theme.signalEmerald : .primary)
                        Text(didFlushDNS ? "Flushed!" : "Flush DNS")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(didFlushDNS ? Theme.signalEmerald.opacity(0.15) : Theme.cardBackground)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Flushes macOS local DNS resolver cache (dscacheutil)")

                Button(action: {
                    state.selectedWorkspace = .wifi
                    openMainApp()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "wifi")
                            .font(.system(size: 10))
                        Text("Wi-Fi Studio")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Theme.cardBackground)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            Button("Quit NexWave") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)

            Spacer()

            Text("NexWave v1.0")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Helpers

    private func copyButton(text: String, key: String) -> some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copiedItem = key
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedItem == key { copiedItem = nil }
            }
        }) {
            Image(systemName: copiedItem == key ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundStyle(copiedItem == key ? Theme.signalEmerald : .secondary)
        }
        .buttonStyle(.plain)
        .help("Copy to clipboard")
    }

    private func openMainApp() {
        openWindow(id: "main-window")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func launchQuickDiagnose() {
        let trimmed = quickTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.updateTargetClassification(trimmed)
        state.selectedWorkspace = .diagnose
        openMainApp()
        if let target = state.classifiedTarget {
            Task {
                await state.runDiagnosis(target: target)
            }
        }
    }
}

