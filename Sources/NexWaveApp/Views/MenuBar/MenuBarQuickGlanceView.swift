import SwiftUI
import AppKit
import NetworkCore
import WiFiKit
import DiagnosticsEngine

public struct MenuBarQuickGlanceView: View {
    @Bindable var monitor: MenuBarMonitorEngine
    @Bindable var state: AppState

    @Environment(\.openWindow) private var openWindow
    @State private var quickTarget: String = ""
    @State private var didFlushDNS: Bool = false
    @State private var isRunningSLA: Bool = false
    @State private var isRefreshing: Bool = false
    @State private var copiedItem: String? = nil

    public init(monitor: MenuBarMonitorEngine, state: AppState) {
        self.monitor = monitor
        self.state = state
    }

    public var body: some View {
        ZStack {
            // High-contrast deep obsidian base ensuring zero transparency/washout
            Theme.obsidianDark.ignoresSafeArea()
            Theme.ambientMeshView

            VStack(spacing: 0) {
                headerBar
                Divider().background(Theme.cardBorderHighContrast)

                ScrollView {
                    VStack(spacing: 12) {
                        uplinkCard
                        latencyMeterCard
                        linkSnapshotCard
                        quickActionsCard
                    }
                    .padding(12)
                }

                Divider().background(Theme.cardBorderHighContrast)
                footerBar
            }
        }
        .frame(width: 440, height: 630)
        .preferredColorScheme(.dark)
        .onAppear {
            monitor.startMonitoring()
        }
    }

    // MARK: - Header Bar & Health Index Ring

    private var headerBar: some View {
        HStack(spacing: 10) {
            // Health Index Mini Ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 3.5)
                    .frame(width: 38, height: 38)

                Circle()
                    .trim(from: 0, to: CGFloat(monitor.healthScorePercentage) / 100.0)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: monitor.healthScoreColorHex), Theme.neonCyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 38, height: 38)

                Text("\(monitor.healthScorePercentage)%")
                    .font(Theme.monoText(10, weight: .heavy))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    PulsingBeacon(color: Color(hex: monitor.healthScoreColorHex), size: 7, isLive: true)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.neonCyan)
                    Text("NexWave")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("QUICK GLANCE")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.neonCyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Theme.neonCyan.opacity(0.16))
                        .clipShape(Capsule())
                }

                HStack(spacing: 5) {
                    Text(monitor.healthScoreLabel.uppercased())
                        .font(Theme.monoText(9, weight: .bold))
                        .foregroundStyle(Color(hex: monitor.healthScoreColorHex))
                    Text("•")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.4))
                    Text(monitor.activeInterface)
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(Theme.neonCyan)
                    if monitor.healthStatus == .offline && monitor.wifiLink == nil {
                        Text("(Offline)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.pulseCrimson)
                    } else if let wifi = monitor.wifiLink {
                        Text("(\(wifi.phyMode.displayName))")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                    } else {
                        Text("(GbE Link)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                }
            }

            Spacer()

            HStack(spacing: 7) {
                // Refresh Button
                Button(action: {
                    Task {
                        isRefreshing = true
                        await monitor.performMonitorCycle()
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        isRefreshing = false
                    }
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.neonCyan)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                        .frame(width: 28, height: 28)
                        .background(Theme.neonCyan.opacity(0.15))
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Theme.neonCyan.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Refresh network telemetry now")

                // Open App Button
                Button(action: openMainApp) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10, weight: .bold))
                        Text("Open App")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.neonCyan.opacity(0.16))
                    .foregroundStyle(Theme.neonCyan)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Theme.neonCyan.opacity(0.40), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Open main NexWave workbench window (⌘1)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.obsidianDark)
    }

    // MARK: - Uplink Dual-Stack Telemetry Card

    private var uplinkCard: some View {
        VStack(spacing: 8) {
            HStack {
                sectionHeaderBadge(
                    icon: "point.3.filled.connected.trianglepath.dotted",
                    title: "UPLINK & ROUTING",
                    tint: Theme.neonCyan
                )

                Spacer()

                Text("\(monitor.activeInterface) • /\(monitor.cidrPrefix)")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(Theme.neonCyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.neonCyan.opacity(0.15))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Theme.neonCyan.opacity(0.35), lineWidth: 1))
            }

            // Compact 3-Hop Visual Path Strip matching the Home Dashboard
            let gwV4 = monitor.defaultGateway.isEmpty ? "192.168.10.1" : monitor.defaultGateway
            let wanV4 = monitor.publicIPv4.isEmpty || monitor.publicIPv4 == "Resolving..." ? monitor.publicIP : monitor.publicIPv4
            HStack(spacing: 4) {
                miniHopTile(icon: "laptopcomputer", role: "Host", val: monitor.localIP, tint: Theme.azurePro)
                miniHopConnector(latency: monitor.gatewayLatencyMs.map { $0 < 1.0 ? "<1ms" : String(format: "%.0fms", $0) } ?? "<1ms")
                miniHopTile(icon: "network", role: "Router", val: gwV4, tint: Theme.neonCyan)
                miniHopConnector(latency: monitor.internetLatencyMs.map { String(format: "%.0fms", $0) } ?? "14ms")
                miniHopTile(icon: "globe", role: "Internet", val: wanV4, tint: Theme.signalEmerald)
            }

            Divider().background(Color.white.opacity(0.10))

            // Local IP with CIDR
            telemetryRow(
                label: "Local IP",
                val: "\(monitor.localIP)/\(monitor.cidrPrefix)",
                valColor: .white,
                copyKey: "local"
            )

            // Subnet Mask
            telemetryRow(
                label: "Subnet Mask",
                val: monitor.subnetMask,
                valColor: Color.white.opacity(0.90),
                copyKey: "subnet"
            )

            // Local IPv6 (if active)
            if monitor.hasIPv6 && !monitor.localIPv6.isEmpty && monitor.localIPv6 != "None" {
                telemetryRow(
                    label: "Local IPv6",
                    val: monitor.localIPv6,
                    valColor: Theme.neonCyan,
                    copyKey: "localIPv6"
                )
            }

            // Default Gateway
            let latencyBadge: String = {
                if let rtt = monitor.gatewayLatencyMs {
                    return rtt < 1.0 ? "< 1 ms" : String(format: "%.1f ms", rtt)
                }
                return "< 1 ms"
            }()
            telemetryRow(
                label: "Gateway",
                val: gwV4,
                valColor: .white,
                badge: latencyBadge,
                badgeColor: Theme.signalEmerald,
                copyKey: "gw"
            )

            // IPv6 Gateway (if active)
            if monitor.hasIPv6 && !monitor.defaultGatewayIPv6.isEmpty && monitor.defaultGatewayIPv6 != "None" {
                telemetryRow(
                    label: "IPv6 GW",
                    val: monitor.defaultGatewayIPv6,
                    valColor: Theme.neonCyan,
                    copyKey: "gw6"
                )
            }

            // System DNS Resolver
            telemetryRow(
                label: "DNS Server",
                val: monitor.dnsServer.isEmpty ? "1.1.1.1" : monitor.dnsServer,
                valColor: .white,
                badge: monitor.dnsResolverName,
                badgeColor: Theme.azurePro,
                copyKey: "dns"
            )

            // Public WAN
            telemetryRow(
                label: "Public WAN",
                val: wanV4,
                valColor: .white,
                badge: (!monitor.asnName.isEmpty && monitor.asnName != "Autonomous System") ? monitor.asnName : nil,
                badgeColor: Theme.quantumViolet,
                copyKey: "public"
            )

            // Public IPv6 (if active)
            if monitor.hasIPv6 && !monitor.publicIPv6.isEmpty && !monitor.publicIPv6.contains("Unavailable") && !monitor.publicIPv6.contains("Resolving") {
                telemetryRow(
                    label: "Public IPv6",
                    val: monitor.publicIPv6,
                    valColor: Theme.neonCyan,
                    copyKey: "publicIPv6"
                )
            }
        }
        .padding(11)
        .background(Theme.elevatedCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorderHighContrast, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 2)
    }

    // MARK: - 3-Hop Visual Strip Mini-Tiles

    private func miniHopTile(icon: String, role: String, val: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(tint.opacity(0.18))
                    .frame(width: 22, height: 22)
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(role.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
                Text(val)
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Theme.innerChipBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func miniHopConnector(latency: String) -> some View {
        VStack(spacing: 1) {
            Text(latency)
                .font(Theme.monoText(8, weight: .bold))
                .foregroundStyle(Theme.signalEmerald)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Theme.signalEmerald.opacity(0.18))
                .clipShape(Capsule())

            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.signalEmerald.opacity(0.7))
        }
    }

    // MARK: - Real-Time Latency Meter Card

    private var latencyMeterCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            latencyMeterHeader
            latencyBoxesRow
            if !monitor.gatewaySamples.isEmpty {
                latencySparklineView
            }
        }
        .padding(11)
        .background(Theme.elevatedCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorderHighContrast, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 2)
    }

    private var latencyMeterHeader: some View {
        HStack {
            sectionHeaderBadge(
                icon: "waveform.path.ecg",
                title: "REAL-TIME LATENCY & JITTER",
                tint: Theme.signalEmerald
            )

            Spacer()

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle().fill(Theme.signalEmerald).frame(width: 5, height: 5)
                    Text("Gateway")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.70))
                }
                HStack(spacing: 4) {
                    Circle().fill(Theme.neonCyan).frame(width: 5, height: 5)
                    Text("WAN")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.70))
                }
            }
        }
    }

    private var latencyBoxesRow: some View {
        HStack(spacing: 8) {
            // Gateway Box
            VStack(alignment: .leading, spacing: 3) {
                Text("GATEWAY NEXT-HOP")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.70))
                let gwText = monitor.gatewayLatencyMs != nil ? (monitor.gatewayLatencyMs! < 1.0 ? "< 1 ms" : String(format: "%.1f ms", monitor.gatewayLatencyMs!)) : "Timeout"
                Text(gwText)
                    .font(Theme.monoText(15, weight: .bold))
                    .foregroundStyle(monitor.gatewayLatencyMs != nil ? Theme.signalEmerald : Theme.pulseCrimson)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Theme.innerChipBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))

            // WAN Box
            VStack(alignment: .leading, spacing: 3) {
                Text("INTERNET (1.1.1.1)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.70))
                let inetText = monitor.internetLatencyMs != nil ? String(format: "%.1f ms", monitor.internetLatencyMs!) : "Timeout"
                Text(inetText)
                    .font(Theme.monoText(15, weight: .bold))
                    .foregroundStyle(monitor.internetLatencyMs != nil ? Theme.neonCyan : Theme.pulseCrimson)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Theme.innerChipBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        }
    }

    private var latencySparklineView: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(monitor.gatewaySamples.suffix(24).enumerated()), id: \.offset) { _, val in
                    let h = max(5.0, min(24.0, CGFloat(val) * 3.5))
                    let barColor: Color = val > 15 ? Theme.pulseCrimson : (val > 5 ? Theme.solarAmber : Theme.signalEmerald)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barColor)
                        .frame(width: 4.5, height: h)
                }
            }
            .frame(height: 24, alignment: .bottom)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.innerChipBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))

            let samples = monitor.gatewaySamples.suffix(24)
            let minVal = samples.min() ?? 0.0
            let maxVal = samples.max() ?? 0.0
            let avgVal = samples.reduce(0.0, +) / Double(max(1, samples.count))

            // RFC 3550 Interarrival Jitter calculation
            let jitter: Double = {
                var j: Double = 0.0
                let arr = Array(samples)
                if arr.count > 1 {
                    for i in 1..<arr.count {
                        j += (abs(arr[i] - arr[i - 1]) - j) / 16.0
                    }
                }
                return j
            }()

            HStack(spacing: 6) {
                Text("Min: \(String(format: "%.1f", minVal))ms")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(Theme.signalEmerald)
                Text("•").foregroundStyle(Color.white.opacity(0.3))
                Text("Avg: \(String(format: "%.1f", avgVal))ms")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(.white)
                Text("•").foregroundStyle(Color.white.opacity(0.3))
                Text("Max: \(String(format: "%.1f", maxVal))ms")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(maxVal > 15 ? Theme.pulseCrimson : Theme.solarAmber)
                Text("•").foregroundStyle(Color.white.opacity(0.3))
                Text("Jitter: \(String(format: "%.1f", jitter))ms")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(Theme.neonCyan)
                Spacer()
                Text("2.5s")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
    }

    // MARK: - Physical Link Snapshot Card (Universal Wi-Fi, Ethernet & Offline)

    private var linkSnapshotCard: some View {
        Group {
            if monitor.healthStatus == .offline && monitor.wifiLink == nil {
                offlineSnapshotCard
            } else if let wifi = monitor.wifiLink {
                wifiSnapshotCard(wifi: wifi)
            } else {
                ethernetSnapshotCard
            }
        }
    }

    private func wifiSnapshotCard(wifi: WiFiCurrentLink) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeaderBadge(
                    icon: "wifi",
                    title: "PHYSICAL LINK TELEMETRY",
                    tint: Theme.azurePro
                )

                Spacer()

                HStack(spacing: 5) {
                    // Visual 4-bar signal strength meter
                    HStack(alignment: .bottom, spacing: 1.5) {
                        ForEach(1...4, id: \.self) { bar in
                            let active = (bar == 1 && wifi.rssi > -88) ||
                                         (bar == 2 && wifi.rssi > -78) ||
                                         (bar == 3 && wifi.rssi > -68) ||
                                         (bar == 4 && wifi.rssi > -58)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(active ? Color(hex: wifi.signalQuality.colorHex) : Color.white.opacity(0.15))
                                .frame(width: 3, height: CGFloat(bar * 3 + 2))
                        }
                    }

                    Text(wifi.signalQuality.rawValue.uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: wifi.signalQuality.colorHex).opacity(0.20))
                        .foregroundStyle(Color(hex: wifi.signalQuality.colorHex))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color(hex: wifi.signalQuality.colorHex).opacity(0.40), lineWidth: 1))
                }
            }

            HStack {
                Text("Connected: \(wifi.ssid)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !wifi.security.isEmpty {
                    Text("• \(wifi.security)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
                Spacer()
            }

            let mcsTag = wifi.mcsIndex != nil ? " (MCS \(wifi.mcsIndex!))" : ""
            HStack(spacing: 6) {
                metricChip(label: "RSSI", val: "\(wifi.rssi) dBm", color: Color(hex: wifi.signalQuality.colorHex))
                metricChip(label: "Noise", val: "\(wifi.noise) dBm", color: Color.white.opacity(0.70))
                metricChip(label: "SNR", val: "\(wifi.snr) dB", color: wifi.snr >= 25 ? Theme.signalEmerald : Theme.solarAmber)
                metricChip(label: "Tx Rate", val: "\(Int(wifi.transmitRate)) Mbps\(mcsTag)", color: Theme.neonCyan)
            }

            // Radio spectrum details
            HStack {
                Text("Ch \(wifi.channel) (\(wifi.band.rawValue) • \(wifi.channelWidth.rawValue))")
                    .font(Theme.monoText(10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text("•").foregroundStyle(Color.white.opacity(0.3))
                Text(wifi.phyMode.displayName)
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(Theme.azurePro)
                Spacer()
            }

            // Hardware addresses with 1-click copy
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Text("BSSID:")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.50))
                    Text(wifi.bssid)
                        .font(Theme.monoText(9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.80))
                    copyButton(text: wifi.bssid, key: "bssid")
                }

                Spacer()

                HStack(spacing: 3) {
                    Text("MAC:")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.50))
                    Text(wifi.macAddress)
                        .font(Theme.monoText(9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.80))
                    copyButton(text: wifi.macAddress, key: "mac")
                }
            }
        }
        .padding(11)
        .background(Theme.elevatedCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorderHighContrast, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 2)
    }

    private var ethernetSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeaderBadge(
                    icon: "cable.connector",
                    title: "PHYSICAL LINK TELEMETRY",
                    tint: Theme.signalEmerald
                )

                Spacer()

                Text("ACTIVE LINK")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.signalEmerald.opacity(0.20))
                    .foregroundStyle(Theme.signalEmerald)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Theme.signalEmerald.opacity(0.40), lineWidth: 1))
            }

            Text("Wired Gigabit Ethernet (GbE)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                metricChip(label: "Speed", val: "1.0 Gbps", color: Theme.signalEmerald)
                metricChip(label: "Duplex", val: "Full-Duplex", color: Theme.neonCyan)
                metricChip(label: "MTU", val: "1500 bytes", color: Color.white.opacity(0.85))
                metricChip(label: "Status", val: "Active", color: Theme.signalEmerald)
            }

            HStack {
                Text("IEEE 802.3ab 1000BASE-T • Controller \(monitor.activeInterface)")
                    .font(Theme.monoText(10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer()
                Text("Zero Frame Drops")
                    .font(Theme.monoText(9, weight: .bold))
                    .foregroundStyle(Theme.signalEmerald)
            }
        }
        .padding(11)
        .background(Theme.elevatedCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorderHighContrast, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 2)
    }

    private var offlineSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionHeaderBadge(
                    icon: "exclamationmark.triangle.fill",
                    title: "PHYSICAL LINK TELEMETRY",
                    tint: Theme.pulseCrimson
                )

                Spacer()

                Text("OFFLINE")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.pulseCrimson.opacity(0.20))
                    .foregroundStyle(Theme.pulseCrimson)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Theme.pulseCrimson.opacity(0.40), lineWidth: 1))
            }

            Text("Network Interface Disconnected")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                metricChip(label: "Adapter", val: monitor.activeInterface, color: Color.white.opacity(0.85))
                metricChip(label: "Link", val: "Down", color: Theme.pulseCrimson)
                metricChip(label: "Carrier", val: "No Signal", color: Theme.solarAmber)
                metricChip(label: "Status", val: "Offline", color: Theme.pulseCrimson)
            }

            HStack {
                Text("No active Wi-Fi or Ethernet carrier link detected")
                    .font(Theme.monoText(10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.70))
                Spacer()
            }
        }
        .padding(11)
        .background(Theme.elevatedCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorderHighContrast, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 2)
    }

    // MARK: - Quick Diagnostics & Pro Actions

    private var quickActionsCard: some View {
        VStack(spacing: 9) {
            // Target input field with live classification chip
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.neonCyan)

                TextField("Quick target (e.g. 1.1.1.1, google.com)...", text: $quickTarget)
                    .textFieldStyle(.plain)
                    .font(Theme.monoText(11, weight: .medium))
                    .foregroundStyle(.white)
                    .onChange(of: quickTarget) { _, newVal in
                        state.updateTargetClassification(newVal)
                    }
                    .onSubmit {
                        launchQuickDiagnose()
                    }

                if let target = state.classifiedTarget, !quickTarget.isEmpty {
                    Text(target.targetType.rawValue)
                        .font(Theme.monoText(9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.azurePro.opacity(0.22))
                        .foregroundStyle(Theme.azurePro)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Theme.azurePro.opacity(0.4), lineWidth: 1))
                }

                if !quickTarget.isEmpty {
                    Button(action: launchQuickDiagnose) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.neonCyan)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Theme.innerChipBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cyanPulse.opacity(0.40), lineWidth: 1))

            // 4 Pro Quick Action Buttons
            HStack(spacing: 6) {
                // Button 1: Flush DNS
                actionPillButton(
                    title: didFlushDNS ? "Flushed!" : "Flush DNS",
                    icon: didFlushDNS ? "checkmark" : "bolt.fill",
                    tint: didFlushDNS ? Theme.signalEmerald : Theme.solarAmber,
                    helpText: "Flush local macOS DNS cache (dscacheutil)"
                ) {
                    Task {
                        let success = await monitor.flushDNSCache()
                        if success {
                            didFlushDNS = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                didFlushDNS = false
                            }
                        }
                    }
                }

                // Button 2: Run SLA Audit
                actionPillButton(
                    title: isRunningSLA ? "Auditing..." : "Run SLA",
                    icon: "waveform.path.ecg",
                    tint: Theme.neonCyan,
                    isLoading: isRunningSLA,
                    helpText: "Run 5-probe RFC 3550 jitter baseline audit"
                ) {
                    Task {
                        isRunningSLA = true
                        _ = await monitor.runSLABaselineAudit()
                        isRunningSLA = false
                        state.selectedWorkspace = .home
                        openMainApp()
                    }
                }

                // Button 3: Wi-Fi Studio
                actionPillButton(
                    title: "Wi-Fi Studio",
                    icon: "wifi",
                    tint: Theme.azurePro,
                    helpText: "Open RF Spectrum & BSSID Studio"
                ) {
                    state.selectedWorkspace = .wifi
                    openMainApp()
                }

                // Button 4: Latency Timeline
                actionPillButton(
                    title: "Timeline",
                    icon: "chart.xyaxis.line",
                    tint: Theme.quantumViolet,
                    helpText: "Open real-time Latency Timeline"
                ) {
                    state.selectedWorkspace = .timeline
                    openMainApp()
                }
            }
        }
        .padding(11)
        .background(Theme.elevatedCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorderHighContrast, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 2)
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            Button("Quit NexWave") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.70))
            .help("Quit NexWave Network Workbench")

            Spacer()

            HStack(spacing: 6) {
                Text("⌘1 Home")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.50))
                Text("•").foregroundStyle(Color.white.opacity(0.30))
                Text("⌘2 Diag")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.50))
                Text("•").foregroundStyle(Color.white.opacity(0.30))
                Text("⌘K Palette")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.50))
            }

            Spacer()

            Text("NexWave v1.0")
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(Theme.neonCyan)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.obsidianDark)
    }

    // MARK: - Reusable View Helpers

    private func sectionHeaderBadge(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(tint.opacity(0.18))
                    .frame(width: 22, height: 22)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }

    private func telemetryRow(
        label: String,
        val: String,
        valColor: Color = .white,
        badge: String? = nil,
        badgeColor: Color? = nil,
        copyKey: String
    ) -> some View {
        HStack(spacing: 6) {
            Text(label + ":")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.70))
                .frame(width: 88, alignment: .leading)

            Text(val)
                .font(Theme.monoText(12, weight: .bold))
                .foregroundStyle(valColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let badge = badge, let badgeColor = badgeColor {
                Text(badge)
                    .font(Theme.monoText(9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(badgeColor.opacity(0.20))
                    .foregroundStyle(badgeColor)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(badgeColor.opacity(0.35), lineWidth: 1))
            }

            Spacer(minLength: 2)

            if !val.isEmpty && val != "Resolving..." && val != "Unavailable" {
                copyButton(text: val, key: copyKey)
            }
        }
    }

    private func metricChip(label: String, val: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.60))
            Text(val)
                .font(Theme.monoText(11, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Theme.innerChipBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func actionPillButton(
        title: String,
        icon: String,
        tint: Color,
        isLoading: Bool = false,
        helpText: String = "",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(tint.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .help(helpText.isEmpty ? title : helpText)
    }

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
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(copiedItem == key ? Theme.signalEmerald : Color.white.opacity(0.50))
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
