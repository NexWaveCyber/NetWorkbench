import SwiftUI
import WiFiKit
import AppKit
import UniformTypeIdentifiers

public struct WiFiStudioView: View {
    @State private var currentLink: WiFiCurrentLink? = nil
    @State private var nearbyAPs: [NearbyAP] = []
    @State private var roamingEvents: [WiFiRoamingEvent] = []
    @State private var congestion: [ChannelCongestion] = []
    @State private var recommendations: [WiFiChannelRecommendation] = []
    @State private var coChannelWarning: WiFiCoChannelWarning? = nil
    @State private var rssiSamples: [(timestamp: Date, rssi: Int, noise: Int)] = []

    @State private var isScanning = false
    @State private var isAutoRefresh = true
    @State private var selectedBandFilter: String = "All"
    @State private var searchText = ""
    @State private var toastMessage: String? = nil
    @State private var timerTask: Task<Void, Never>? = nil

    @ObservedObject private var locationAuthorizer = WiFiLocationAuthorizer.shared

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerBar

                    if !locationAuthorizer.isAuthorized {
                        locationPermissionBanner
                    }

                    if let link = currentLink {
                        rfHealthHeroCard(link: link)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            apAssociationCard(link: link)
                            channelBandCard(link: link)
                        }
                    } else {
                        disconnectedStateCard
                    }

                    // Algorithmic Channel Optimizer (Grade A++++ Pro Section)
                    channelOptimizerSection

                    // Spectrum & Co-Channel Distribution
                    spectrumCongestionSection

                    // AP Roaming Audit Trail
                    if !roamingEvents.isEmpty {
                        roamingAuditSection
                    }

                    // Surrounding Visible Wi-Fi Environments
                    nearbyNetworksSection
                }
                .padding(20)
                .padding(.bottom, 40)
            }

            // Floating Toast Notification
            if let toast = toastMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.emeraldHealthy)
                    Text(toast)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.borderHighlight, lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.surfaceBackground)
        .onAppear {
            if locationAuthorizer.isNotDetermined {
                locationAuthorizer.requestAuthorization()
            }
            startLiveMonitor()
        }
        .onDisappear {
            stopLiveMonitor()
        }
        .onChange(of: locationAuthorizer.authorizationStatus) { _, status in
            if locationAuthorizer.isAuthorized {
                Task {
                    await pollTelemetry()
                    await performFullScan()
                }
            }
        }
    }

    // MARK: - Location Permission Banner

    private var locationPermissionBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: locationAuthorizer.isDenied ? "location.slash.fill" : "location.circle.fill")
                .font(.title2)
                .foregroundStyle(locationAuthorizer.isDenied ? Theme.solarAmber : Theme.azurePro)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(locationAuthorizer.isDenied ? "Location Permission Required for Wi-Fi Names" : "Enable Location to View Wi-Fi (SSID) Names")
                        .font(.subheadline.bold())
                    Text("macOS Security")
                        .font(.system(size: 9, weight: .heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.1))
                        .cornerRadius(3)
                }

                Text(locationAuthorizer.isDenied
                    ? "macOS redacts Wi-Fi network names (SSIDs) until Location Services is enabled for NexWave Network Workbench in System Settings."
                    : "macOS considers Wi-Fi names geolocation data. Granting permission unlocks real over-the-air network names for all surrounding APs."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if locationAuthorizer.isDenied {
                Button(action: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                        Text("Open Settings")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.solarAmber.opacity(0.2))
                    .foregroundStyle(Theme.solarAmber)
                    .cornerRadius(7)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: {
                    locationAuthorizer.requestAuthorization()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap.fill")
                        Text("Grant Permission")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.azurePro)
                    .foregroundStyle(.white)
                    .cornerRadius(7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(locationAuthorizer.isDenied ? Theme.solarAmber.opacity(0.08) : Theme.azurePro.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(locationAuthorizer.isDenied ? Theme.solarAmber.opacity(0.3) : Theme.azurePro.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "wifi")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.cyanPulse)
                    Text("Wi-Fi Studio")
                        .font(.title2.bold())

                    if let link = currentLink {
                        Text(link.interfaceName)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.azurePro.opacity(0.2))
                            .foregroundStyle(Theme.azurePro)
                            .clipShape(Capsule())

                        Text("Grade A++++")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.emeraldHealthy.opacity(0.18))
                            .foregroundStyle(Theme.emeraldHealthy)
                            .clipShape(Capsule())
                    }
                }
                Text("Enterprise CoreWLAN RF telemetry, Layer 2/3 association, AP roaming audit, and algorithmic channel optimization.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                // Live Polling Toggle
                Toggle(isOn: $isAutoRefresh) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isAutoRefresh ? Theme.emeraldHealthy : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text("Live Polling")
                            .font(.caption.bold())
                    }
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isAutoRefresh ? Theme.emeraldHealthy.opacity(0.12) : Theme.cardBackground)
                .cornerRadius(8)
                .onChange(of: isAutoRefresh) { _, enabled in
                    if enabled { startLiveMonitor() } else { stopLiveMonitor() }
                }

                // Scan Spectrum Button
                Button(action: {
                    Task { await performFullScan() }
                }) {
                    HStack(spacing: 6) {
                        if isScanning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                        Text(isScanning ? "Scanning RF..." : "Scan Spectrum")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.azurePro.opacity(0.15))
                    .foregroundStyle(Theme.azurePro)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isScanning)

                // Export RF Survey Menu
                Menu {
                    Button(action: exportMarkdownToClipboard) {
                        Label("Copy Markdown Survey Report", systemImage: "doc.on.clipboard")
                    }
                    Button(action: exportJSONToClipboard) {
                        Label("Copy JSON Telemetry Payload", systemImage: "curlybraces")
                    }
                    Divider()
                    Button(action: saveSurveyReport) {
                        Label("Save RF Survey Report (.md)...", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export Survey")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.purpleInferred.opacity(0.15))
                    .foregroundStyle(Theme.purpleInferred)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - RF Health Hero Card

    private func rfHealthHeroCard(link: WiFiCurrentLink) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: link.signalQuality.colorHex))
                        .frame(width: 12, height: 12)
                    Text("RF LINK HEALTH: \(link.signalQuality.rawValue.uppercased()) (\(link.signalQuality.scorePercentage)%)")
                        .font(.headline.bold())
                        .foregroundStyle(Color(hex: link.signalQuality.colorHex))
                }

                Spacer()

                Text(link.signalQuality.advice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Signal Health Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 10)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: link.signalQuality.colorHex).opacity(0.7),
                                    Color(hex: link.signalQuality.colorHex)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(link.signalQuality.scorePercentage) / 100.0, height: 10)
                }
            }
            .frame(height: 10)

            // Co-Channel Contention Banner
            if let warning = coChannelWarning {
                HStack(spacing: 10) {
                    Image(systemName: warning.severity == .clean ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(hex: warning.severity.badgeColor))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(warning.severity.rawValue.uppercased())
                                .font(.caption.bold())
                                .foregroundStyle(Color(hex: warning.severity.badgeColor))
                            Text("• Channel \(warning.channel) (\(warning.band.rawValue))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(warning.advisory)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color(hex: warning.severity.badgeColor).opacity(0.08))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: warning.severity.badgeColor).opacity(0.25), lineWidth: 1))
            }

            // Primary 4 Telemetry Metrics
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                telemetryTile(
                    title: "SIGNAL (RSSI)",
                    value: "\(link.rssi) dBm",
                    subtext: estimatedDistance(rssi: link.rssi, band: link.band),
                    color: Color(hex: link.signalQuality.colorHex),
                    icon: "antenna.radiowaves.left.and.right"
                )

                telemetryTile(
                    title: "NOISE FLOOR",
                    value: "\(link.noise) dBm",
                    subtext: link.noise <= -85 ? "Quiet Spectrum" : "Elevated Noise",
                    color: link.noise <= -85 ? Theme.cyanPulse : Theme.amberWarning,
                    icon: "waveform.path"
                )

                telemetryTile(
                    title: "SNR RATIO",
                    value: "\(link.snr) dB",
                    subtext: link.snr >= 35 ? "Pristine Margin" : (link.snr >= 20 ? "Acceptable Margin" : "Degraded Margin"),
                    color: link.snr >= 25 ? Theme.signalEmerald : Theme.pulseCrimson,
                    icon: "chart.bar.xaxis"
                )

                telemetryTile(
                    title: "PHY TX RATE",
                    value: link.transmitRate > 0 ? "\(Int(link.transmitRate)) Mbps" : "Auto",
                    subtext: link.mcsIndex != nil ? "MCS \(link.mcsIndex!) • 2x2 MIMO" : link.phyMode.displayName,
                    color: Theme.neonCyan,
                    icon: "bolt.fill"
                )
            }

            // Live Sparkline of RSSI
            if !rssiSamples.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Live Signal Variance (Last 60s)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        let minRssi = rssiSamples.map(\.rssi).min() ?? link.rssi
                        let maxRssi = rssiSamples.map(\.rssi).max() ?? link.rssi
                        Text("Range: [\(minRssi) dBm ... \(maxRssi) dBm] | Current: \(link.rssi) dBm")
                            .font(Theme.monoText(10))
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(0..<rssiSamples.count, id: \.self) { idx in
                            let sample = rssiSamples[idx]
                            let normalizedHeight = max(4.0, min(36.0, CGFloat(sample.rssi + 100) * 0.6))
                            VStack(spacing: 0) {
                                Spacer()
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        sample.rssi >= -55 ? Theme.signalEmerald :
                                        (sample.rssi >= -70 ? Theme.solarAmber : Theme.pulseCrimson)
                                    )
                                    .frame(height: normalizedHeight)
                            }
                        }
                    }
                    .frame(height: 36)
                    .padding(8)
                    .background(Theme.cardBackground.opacity(0.6))
                    .cornerRadius(6)
                }
            }
        }
        .padding(18)
        .background(Theme.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: link.signalQuality.colorHex).opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private func telemetryTile(title: String, value: String, subtext: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(Theme.monoText(18, weight: .bold))
                .foregroundStyle(.primary)
            Text(subtext)
                .font(.caption2)
                .foregroundStyle(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.secondaryBackground.opacity(0.6))
        .cornerRadius(8)
    }

    // MARK: - AP Association Card

    private func apAssociationCard(link: WiFiCurrentLink) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "network")
                    .foregroundStyle(Theme.cyanPulse)
                Text("Access Point Association")
                    .font(.subheadline.bold())
                Spacer()
                Text("Layer 2/3")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                detailRow(label: "SSID (Network)", value: link.ssid, isMono: false)

                // BSSID with Hardware Vendor Badge
                HStack {
                    Text("BSSID (Hardware)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let vendor = link.vendorName {
                        Text(vendor)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Theme.azurePro.opacity(0.18))
                            .foregroundStyle(Theme.azurePro)
                            .cornerRadius(4)
                    }
                    Text(link.bssid)
                        .font(Theme.monoText(11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    Button(action: {
                        copyToClipboard(link.bssid, message: "Copied BSSID to clipboard")
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)

                detailRow(label: "Security Protocol", value: link.security, isMono: false)
                detailRow(label: "Hardware Client MAC", value: link.macAddress, isMono: true)
                if let dhcp = link.dhcpServer {
                    detailRow(label: "DHCP Server Gateway", value: dhcp, isMono: true)
                }
                detailRow(label: "Country Code", value: link.countryCode, isMono: true)
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderLight, lineWidth: 1))
    }

    // MARK: - Channel & Band Card

    private func channelBandCard(link: WiFiCurrentLink) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "dot.radiowaves.up.forward")
                    .foregroundStyle(Theme.azurePro)
                Text("Spectrum & Radio Configuration")
                    .font(.subheadline.bold())
                Spacer()
                Text("PHY Layer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                detailRow(label: "Frequency Band", value: link.band.rawValue, isMono: false)
                detailRow(label: "Operating Channel", value: bondedSpanString(channel: link.channel, width: link.channelWidth), isMono: true)
                detailRow(label: "Channel Width", value: link.channelWidth.rawValue, isMono: true)
                detailRow(label: "PHY Standard", value: link.phyMode.displayName, isMono: false)
                detailRow(label: "Theoretical Max Link", value: link.transmitRate > 0 ? "\(Int(link.transmitRate)) Mbps" : "Auto", isMono: true)
                if let mcs = link.mcsIndex {
                    detailRow(label: "Modulation (MCS Index)", value: "MCS \(mcs)", isMono: true)
                }
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderLight, lineWidth: 1))
    }

    private func detailRow(label: String, value: String, isMono: Bool) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(isMono ? Theme.monoText(11, weight: .semibold) : .caption.weight(.semibold))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Algorithmic Channel Optimizer (Grade A++++ Section)

    private var channelOptimizerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(Theme.purpleInferred)
                        Text("Algorithmic RF Channel Optimization")
                            .font(.headline.bold())

                        Text("AUTOMATED ADVICE")
                            .font(.system(size: 8, weight: .heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.purpleInferred.opacity(0.18))
                            .foregroundStyle(Theme.purpleInferred)
                            .clipShape(Capsule())
                    }
                    Text("Calculates lowest interference floor across non-overlapping standard channels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if recommendations.isEmpty {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.purpleInferred)
                    Text("Click 'Scan Spectrum' above to run the algorithmic RF interference optimizer across surrounding channels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderLight, lineWidth: 1))
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(recommendations) { rec in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(rec.band.rawValue)
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(hex: rec.band.badgeColor))
                                Spacer()
                                Text("\(rec.cleanlinessScore)/100 Clean")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(rec.cleanlinessScore >= 80 ? Theme.signalEmerald : Theme.solarAmber)
                            }

                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("Ch \(rec.recommendedChannel)")
                                    .font(Theme.monoText(20, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text("(\(rec.channelWidth))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            // Cleanliness Score Bar
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 6)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(rec.cleanlinessScore >= 80 ? Theme.signalEmerald : Theme.solarAmber)
                                    .frame(width: CGFloat(rec.cleanlinessScore) * 1.6, height: 6)
                            }
                            .frame(height: 6)

                            Text(rec.reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        .padding(14)
                        .background(Theme.cardBackground)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderLight, lineWidth: 1))
                    }
                }
            }
        }
    }

    // MARK: - Spectrum & Channel Congestion Section

    private var spectrumCongestionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .foregroundStyle(Theme.neonCyan)
                        Text("Channel Spectrum Distribution")
                            .font(.headline.bold())
                    }
                    Text("Shows co-channel density of visible access points to identify clean channels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if congestion.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Click 'Scan Spectrum' above to inspect co-channel interference on surrounding frequencies.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground)
                .cornerRadius(10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(congestion) { item in
                            VStack(spacing: 6) {
                                Text("Ch \(item.channel)")
                                    .font(Theme.monoText(11, weight: item.isCurrentChannel ? .bold : .regular))
                                    .foregroundStyle(item.isCurrentChannel ? Theme.neonCyan : .primary)

                                // Bar
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(width: 34, height: 60)

                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(
                                            item.isCurrentChannel ? Theme.cyanPulse :
                                            (item.apCount > 3 ? Theme.pulseCrimson : (item.apCount > 1 ? Theme.solarAmber : Theme.azurePro))
                                        )
                                        .frame(width: 34, height: min(60.0, max(8.0, CGFloat(item.apCount * 14))))
                                }

                                Text("\(item.apCount) AP\(item.apCount == 1 ? "" : "s")")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(item.apCount > 3 ? Theme.pulseCrimson : .secondary)

                                if item.isCurrentChannel {
                                    Text("ACTIVE")
                                        .font(.system(size: 8, weight: .heavy))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Theme.cyanPulse.opacity(0.2))
                                        .foregroundStyle(Theme.cyanPulse)
                                        .cornerRadius(3)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                            .background(item.isCurrentChannel ? Theme.azurePro.opacity(0.12) : Color.clear)
                            .cornerRadius(8)
                        }
                    }
                    .padding(14)
                }
                .background(Theme.cardBackground)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderLight, lineWidth: 1))
            }
        }
    }

    // MARK: - AP Roaming Audit Section

    private var roamingAuditSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.swap")
                    .foregroundStyle(Theme.purpleInferred)
                Text("AP Roaming History Log")
                    .font(.headline.bold())
                Spacer()
                Text("\(roamingEvents.count) Event\(roamingEvents.count == 1 ? "" : "s") Recorded")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(roamingEvents) { event in
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title3)
                            .foregroundStyle(Theme.purpleInferred)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("BSSID Roam:")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)

                                if let prevV = event.previousVendor {
                                    Text(prevV)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Theme.azurePro.opacity(0.15))
                                        .foregroundStyle(Theme.azurePro)
                                        .cornerRadius(3)
                                }
                                Text(event.previousBSSID)
                                    .font(Theme.monoText(11))

                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                if let newV = event.newVendor {
                                    Text(newV)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Theme.emeraldHealthy.opacity(0.15))
                                        .foregroundStyle(Theme.emeraldHealthy)
                                        .cornerRadius(3)
                                }
                                Text(event.newBSSID)
                                    .font(Theme.monoText(11, weight: .bold))

                                Spacer()
                                Text(event.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 14) {
                                Text("Ch: \(event.previousChannel) ➔ Ch: \(event.newChannel)")
                                    .font(Theme.monoText(11))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 4) {
                                    Text("RSSI:")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(event.previousRSSI) dBm ➔ \(event.newRSSI) dBm")
                                        .font(Theme.monoText(11, weight: .semibold))
                                    Text("(\(event.rssiDelta >= 0 ? "+\(event.rssiDelta)" : "\(event.rssiDelta)") dBm)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(event.rssiDelta >= 0 ? Theme.signalEmerald : Theme.pulseCrimson)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Theme.cardBackground)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Nearby Networks Table

    private var nearbyNetworksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.indent")
                            .foregroundStyle(Theme.azurePro)
                        Text("Visible Wi-Fi Environments (\(filteredNearbyAPs.count))")
                            .font(.headline.bold())
                    }
                    Text("Over-the-air spectrum scan of surrounding enterprise and consumer SSIDs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Band Filter Picker
                Picker("", selection: $selectedBandFilter) {
                    Text("All Bands").tag("All")
                    Text("2.4 GHz").tag("2.4 GHz")
                    Text("5 GHz").tag("5 GHz")
                    Text("6 GHz").tag("6 GHz (Wi-Fi 6E/7)")
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }

            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter by SSID, BSSID, Channel, or Vendor...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Theme.cardBackground)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))

            if filteredNearbyAPs.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text(isScanning ? "Scanning surrounding frequencies..." : "No matching networks discovered.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                    Spacer()
                }
                .background(Theme.cardBackground)
                .cornerRadius(10)
            } else {
                VStack(spacing: 4) {
                    // Header
                    HStack {
                        Text("SSID / BSSID / VENDOR")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("CHANNEL / BAND")
                            .font(.caption.bold())
                            .frame(width: 140, alignment: .leading)
                        Text("SIGNAL / NOISE")
                            .font(.caption.bold())
                            .frame(width: 130, alignment: .leading)
                        Text("SECURITY")
                            .font(.caption.bold())
                            .frame(width: 130, alignment: .leading)
                        Text("PHY")
                            .font(.caption.bold())
                            .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.secondaryBackground)
                    .cornerRadius(6)

                    ForEach(filteredNearbyAPs) { ap in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(ap.ssid)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(ap.isCurrentAssociation ? Theme.cyanPulse : .primary)
                                    if ap.isCurrentAssociation {
                                        Text("CONNECTED")
                                            .font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Theme.emeraldHealthy.opacity(0.2))
                                            .foregroundStyle(Theme.emeraldHealthy)
                                            .cornerRadius(3)
                                    }
                                }

                                HStack(spacing: 6) {
                                    if let vendor = ap.vendorName {
                                        Text(vendor)
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Theme.azurePro.opacity(0.15))
                                            .foregroundStyle(Theme.azurePro)
                                            .cornerRadius(3)
                                    }
                                    Text(ap.bssid)
                                        .font(Theme.monoText(10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            // Channel / Band
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ch \(ap.channel) (\(ap.channelWidth.rawValue))")
                                    .font(Theme.monoText(11, weight: .semibold))
                                Text(ap.band.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(Color(hex: ap.band.badgeColor))
                            }
                            .frame(width: 140, alignment: .leading)

                            // Signal / Noise
                            HStack(spacing: 8) {
                                if let rssi = ap.rssi {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(rssi) dBm")
                                            .font(Theme.monoText(11, weight: .bold))
                                            .foregroundStyle(
                                                rssi >= -55 ? Theme.signalEmerald :
                                                (rssi >= -70 ? Theme.solarAmber : Theme.pulseCrimson)
                                            )
                                        if let noise = ap.noise {
                                            Text("Noise: \(noise) dBm")
                                                .font(Theme.monoText(9))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                } else {
                                    Text("N/A")
                                        .font(Theme.monoText(11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 130, alignment: .leading)

                            // Security
                            Text(ap.security)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(width: 130, alignment: .leading)

                            // PHY Mode
                            Text(ap.phyMode)
                                .font(Theme.monoText(10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.cardBackground)
                                .cornerRadius(4)
                                .frame(width: 90, alignment: .trailing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(ap.isCurrentAssociation ? Theme.azurePro.opacity(0.08) : Theme.cardBackground)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(ap.isCurrentAssociation ? Theme.cyanPulse.opacity(0.4) : Theme.borderLight, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private var filteredNearbyAPs: [NearbyAP] {
        nearbyAPs.filter { ap in
            let matchesBand = selectedBandFilter == "All" || ap.band.rawValue == selectedBandFilter
            let matchesSearch = searchText.isEmpty ||
                ap.ssid.localizedCaseInsensitiveContains(searchText) ||
                ap.bssid.localizedCaseInsensitiveContains(searchText) ||
                (ap.vendorName?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                String(ap.channel).contains(searchText)
            return matchesBand && matchesSearch
        }
    }

    // MARK: - Disconnected State

    private var disconnectedStateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundStyle(Theme.pulseCrimson)
            Text("No Active Wi-Fi Interface Associated")
                .font(.headline)
            Text("Please ensure Wi-Fi is powered on and connected to an access point on interface en0.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground)
        .cornerRadius(12)
    }

    // MARK: - Export Helpers

    private func exportMarkdownToClipboard() {
        let engine = WiFiEngine.shared
        Task {
            let report = await engine.generateSurveyReport(currentLink: currentLink, networks: nearbyAPs)
            let md = report.toMarkdown()
            copyToClipboard(md, message: "Copied Markdown RF Survey to clipboard")
        }
    }

    private func exportJSONToClipboard() {
        let engine = WiFiEngine.shared
        Task {
            let report = await engine.generateSurveyReport(currentLink: currentLink, networks: nearbyAPs)
            let json = report.toJSON()
            copyToClipboard(json, message: "Copied JSON Telemetry Payload to clipboard")
        }
    }

    private func saveSurveyReport() {
        let engine = WiFiEngine.shared
        Task {
            let report = await engine.generateSurveyReport(currentLink: currentLink, networks: nearbyAPs)
            let md = report.toMarkdown()

            await MainActor.run {
                let panel = NSSavePanel()
                let mdType = UTType(filenameExtension: "md") ?? .plainText
                panel.allowedContentTypes = [mdType, .plainText]
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd_HHmm"
                panel.nameFieldStringValue = "NexWave_WiFi_Survey_\(df.string(from: Date())).md"
                panel.prompt = "Save Survey Report"

                if panel.runModal() == .OK, let url = panel.url {
                    try? md.write(to: url, atomically: true, encoding: .utf8)
                    copyToClipboard("", message: "Saved RF Survey to \(url.lastPathComponent)")
                }
            }
        }
    }

    private func copyToClipboard(_ text: String, message: String) {
        if !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            toastMessage = message
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation {
                if toastMessage == message {
                    toastMessage = nil
                }
            }
        }
    }

    private func estimatedDistance(rssi: Int, band: WiFiBand) -> String {
        let freq: Double
        switch band {
        case .ghz2_4: freq = 2412.0
        case .ghz5: freq = 5180.0
        case .ghz6: freq = 6100.0
        case .unknown: freq = 5000.0
        }
        let exp = (Double(abs(rssi)) - 27.55 - 20.0 * log10(freq)) / 20.0
        let meters = max(0.5, pow(10.0, exp))
        if meters < 1.5 {
            return "< 1m (Immediate Proximity)"
        } else if meters < 15 {
            return String(format: "~%.1fm (Line-of-Sight)", meters)
        } else {
            return String(format: "~%.0fm (Attenuated / Through Wall)", meters)
        }
    }

    private func bondedSpanString(channel: Int, width: WiFiChannelWidth) -> String {
        switch width {
        case .mhz40:
            let start = channel % 8 == 0 ? channel - 4 : channel
            return "Ch \(channel) (\(start)-\(start + 4) bonded, 40 MHz)"
        case .mhz80:
            let anchors = [36, 52, 100, 116, 132, 149]
            if let base = anchors.first(where: { abs($0 - channel) < 16 }) {
                return "Ch \(channel) (\(base)-\(base + 12) bonded, 80 MHz)"
            }
            return "Ch \(channel) (80 MHz bonded)"
        case .mhz160:
            return "Ch \(channel) (160 MHz bonded wideband)"
        case .mhz320:
            return "Ch \(channel) (320 MHz ultra-wideband)"
        default:
            return "Ch \(channel) (20 MHz standard)"
        }
    }

    // MARK: - Live Telemetry Controller

    private func startLiveMonitor() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                await pollTelemetry()
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s tick
            }
        }
    }

    private func stopLiveMonitor() {
        timerTask?.cancel()
        timerTask = nil
    }

    @MainActor
    private func pollTelemetry() async {
        let engine = WiFiEngine.shared
        if let link = await engine.fetchCurrentLink() {
            self.currentLink = link
            self.coChannelWarning = await engine.evaluateCoChannelContention(currentLink: link, networks: self.nearbyAPs)
        }
        self.roamingEvents = await engine.getRoamingHistory()
        let samples = await engine.getRSSIHistory()
        self.rssiSamples = samples
    }

    @MainActor
    private func performFullScan() async {
        isScanning = true
        let engine = WiFiEngine.shared
        let nets = await engine.scanNearbyNetworks()
        self.nearbyAPs = nets
        if let link = currentLink {
            self.congestion = await engine.calculateChannelCongestion(from: nets, currentChannel: link.channel)
            self.recommendations = await engine.recommendOptimalChannels(from: nets, currentChannel: link.channel)
            self.coChannelWarning = await engine.evaluateCoChannelContention(currentLink: link, networks: nets)
        } else {
            self.recommendations = await engine.recommendOptimalChannels(from: nets, currentChannel: 0)
        }
        isScanning = false
    }
}
