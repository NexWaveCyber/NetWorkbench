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
    @State private var stickyClientAnomaly: WiFiStickyClientAnomaly? = nil
    @State private var rssiSamples: [(timestamp: Date, rssi: Int, noise: Int)] = []

    // Spectrum View Controls
    @State private var selectedSpectrumBand: WiFiBand = .ghz5
    @State private var spectrumDisplayMode: SpectrumDisplayMode = .parabolicCurves

    // Filtering & Sorting
    @State private var selectedBandFilter: String = "All"
    @State private var quickFilter: APQuickFilter = .all
    @State private var searchText = ""
    @State private var sortColumn: APSortColumn = .signal
    @State private var sortAscending: Bool = false

    // Inspection & Modals
    @State private var selectedAPForDetail: NearbyAP? = nil
    @State private var toastMessage: String? = nil

    // Engine & Monitoring
    @State private var isScanning = false
    @State private var isAutoRefresh = true
    @State private var timerTask: Task<Void, Never>? = nil

    @ObservedObject private var locationAuthorizer = WiFiLocationAuthorizer.shared

    public init() {}

    public enum SpectrumDisplayMode: String, CaseIterable {
        case parabolicCurves = "RF Parabolic Spectrum"
        case channelDensity = "Channel Congestion Bars"
    }

    public enum APSortColumn {
        case ssid, bssid, channel, band, width, freq, signal, snr, security, vendor, phy
    }

    public enum APQuickFilter: String, CaseIterable {
        case all = "All Networks"
        case connectedSSID = "Connected ESSID"
        case strong = "Strong (≥ -60 dBm)"
        case weak = "Weak (≤ -75 dBm)"
        case dfs = "DFS Channels"
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerBar

                    if !locationAuthorizer.isAuthorized {
                        locationPermissionBanner
                    }

                    if let anomaly = stickyClientAnomaly {
                        stickyClientWarningBanner(anomaly: anomaly)
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

                    // Interactive Parabolic RF Spectrum & Contention
                    spectrumCongestionSection

                    // AP Roaming Audit Trail
                    if !roamingEvents.isEmpty {
                        roamingAuditSection
                    }

                    // Surrounding Visible Wi-Fi Environments (Multi-Column Sortable Table)
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
        .sheet(item: $selectedAPForDetail) { ap in
            apDetailSheet(ap: ap)
        }
        .onAppear {
            if locationAuthorizer.isNotDetermined {
                locationAuthorizer.requestAuthorization()
            }
            startLiveMonitor()
            Task {
                await pollTelemetry()
                if let link = currentLink {
                    selectedSpectrumBand = link.band
                }
                await performFullScan()
            }
        }
        .onDisappear {
            stopLiveMonitor()
        }
        .onChange(of: locationAuthorizer.authorizationStatus) { _, _ in
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

    // MARK: - Sticky Client Anomaly Banner

    private func stickyClientWarningBanner(anomaly: WiFiStickyClientAnomaly) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(Theme.solarAmber)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Suboptimal Association Detected (Sticky Client)")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.solarAmber)

                    Text("+\(anomaly.rssiDelta) dB Gain Available")
                        .font(.system(size: 9, weight: .heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.solarAmber.opacity(0.2))
                        .foregroundStyle(Theme.solarAmber)
                        .cornerRadius(4)
                }

                Text("Client is clinging to degraded BSSID `\(anomaly.currentBSSID)` (\(anomaly.currentRSSI) dBm) despite candidate AP `\(anomaly.candidateBSSID)` (\(anomaly.candidateVendor ?? "Unknown")) offering \(anomaly.candidateRSSI) dBm on Ch \(anomaly.candidateChannel) (\(anomaly.candidateBand.rawValue)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(anomaly.recommendation)
                    .font(.caption2)
                    .foregroundStyle(Theme.azurePro)
            }

            Spacer()

            Button(action: {
                Task {
                    await pollTelemetry()
                    await performFullScan()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Re-evaluate")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.solarAmber.opacity(0.18))
                .foregroundStyle(Theme.solarAmber)
                .cornerRadius(7)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.solarAmber.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.solarAmber.opacity(0.35), lineWidth: 1)
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
                    Button(action: exportCSVToClipboard) {
                        Label("Copy CSV Inventory Table", systemImage: "tablecells")
                    }
                    Button(action: exportJSONToClipboard) {
                        Label("Copy JSON Telemetry Payload", systemImage: "curlybraces")
                    }
                    Divider()
                    Button(action: saveSurveyReport) {
                        Label("Save RF Survey Report (.md)...", systemImage: "square.and.arrow.down")
                    }
                    Button(action: saveCSVInventory) {
                        Label("Save AP Inventory (.csv)...", systemImage: "tablecells.badge.ellipsis")
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

    // MARK: - RF Health Hero Card (with Dual-Trace Time-Series Graph)

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
                                    Color(hex: link.signalQuality.colorHex),
                                    Color(hex: link.signalQuality.colorHex).opacity(0.7)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(14, geo.size.width * CGFloat(link.signalQuality.scorePercentage) / 100.0), height: 10)
                }
            }
            .frame(height: 10)

            // Primary 4-Metric Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                telemetryTile(
                    title: "SIGNAL STRENGTH",
                    value: "\(link.rssi) dBm",
                    subtext: link.rssi >= -55 ? "Optimal RSSI" : (link.rssi >= -70 ? "Adequate RSSI" : "Weak RSSI"),
                    color: link.rssi >= -65 ? Theme.signalEmerald : (link.rssi >= -75 ? Theme.solarAmber : Theme.pulseCrimson),
                    icon: "antenna.radiowaves.left.and.right"
                )

                telemetryTile(
                    title: "NOISE FLOOR",
                    value: "\(link.noise) dBm",
                    subtext: link.noise <= -85 ? "Quiet RF Noise" : "High Interference",
                    color: link.noise <= -85 ? Theme.cyanPulse : Theme.solarAmber,
                    icon: "waveform.path.ecg"
                )

                telemetryTile(
                    title: "SNR MARGIN",
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

            // Calibrated Dual-Trace Signal & Noise Graph
            if !rssiSamples.isEmpty {
                RFDualTraceGraphView(samples: rssiSamples, currentRSSI: link.rssi, currentNoise: link.noise)
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
                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .foregroundStyle(Theme.cyanPulse)
                    Text("Layer 2/3 Association")
                        .font(.headline.bold())
                }
                Spacer()
                Text("BSSID")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.azurePro.opacity(0.18))
                    .foregroundStyle(Theme.azurePro)
                    .cornerRadius(4)
            }

            VStack(spacing: 10) {
                summaryRow(label: "Connected SSID", value: link.ssid, isMono: false)
                summaryRow(label: "BSSID (AP MAC)", value: link.bssid, isMono: true)
                if let vendor = link.vendorName {
                    summaryRow(label: "Hardware Vendor", value: vendor, isMono: false)
                }
                summaryRow(label: "Client Interface", value: "\(link.interfaceName) (\(link.macAddress))", isMono: true)
                if let dhcp = link.dhcpServer {
                    summaryRow(label: "DHCP Server IP", value: dhcp, isMono: true)
                }
                summaryRow(label: "Security Suite", value: link.security, isMono: false)
                summaryRow(label: "Regulatory Domain", value: "\(link.countryCode) (802.11d)", isMono: true)
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
                HStack(spacing: 8) {
                    Image(systemName: "wave.3.forward.circle.fill")
                        .foregroundStyle(Theme.azurePro)
                    Text("RF Spectrum Geometry")
                        .font(.headline.bold())
                }
                Spacer()
                Text(link.band.rawValue)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(hex: link.band.badgeColor).opacity(0.2))
                    .foregroundStyle(Color(hex: link.band.badgeColor))
                    .clipShape(Capsule())
            }

            VStack(spacing: 10) {
                summaryRow(label: "Primary Channel", value: "Channel \(link.channel)", isMono: true)
                summaryRow(label: "Channel Bandwidth", value: link.channelWidth.rawValue, isMono: false)
                summaryRow(label: "Center Frequency", value: "\(Int(link.centerFrequencyMHz)) MHz", isMono: true)
                if let unii = link.uniiSubBand {
                    summaryRow(label: "Sub-Band & DFS", value: "\(unii) \(link.isDFS ? "(DFS Radar)" : "(Non-DFS)")", isMono: false)
                }
                summaryRow(label: "802.11 Protocol", value: link.phyMode.displayName, isMono: false)
                summaryRow(label: "MCS Spatial Stream", value: link.mcsIndex != nil ? "Index \(link.mcsIndex!) (2x2 NSS)" : "Dynamic Rate Adaptation", isMono: true)
                summaryRow(label: "Spectrum Span", value: "\(Int(link.frequencySpanMHz.lowerBound)) – \(Int(link.frequencySpanMHz.upperBound)) MHz", isMono: true)
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderLight, lineWidth: 1))
    }

    private func summaryRow(label: String, value: String, isMono: Bool) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(isMono ? Theme.monoText(11, weight: .semibold) : .caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    // MARK: - Disconnected State Card

    private var disconnectedStateCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundStyle(Theme.solarAmber)

            Text("No Active Wi-Fi Connection")
                .font(.headline.bold())

            Text("Wi-Fi interface is disconnected or turned off. Connect to a network or click 'Scan Spectrum' below to survey surrounding radio environments.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderLight, lineWidth: 1))
    }

    // MARK: - Algorithmic Channel Optimizer

    private var channelOptimizerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.purpleInferred)
                    Text("Algorithmic RF Channel Optimizer")
                        .font(.headline.bold())
                }

                Spacer()

                Text("Grade A++++")
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.purpleInferred.opacity(0.18))
                    .foregroundStyle(Theme.purpleInferred)
                    .cornerRadius(4)
            }

            // Co-Channel & OBSS Warning Banner
            if let warning = coChannelWarning {
                HStack(spacing: 12) {
                    Image(systemName: warning.severity == .clean ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.title3)
                        .foregroundStyle(Color(hex: warning.severity.badgeColor))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Current Channel Contention: \(warning.severity.rawValue)")
                                .font(.caption.bold())
                                .foregroundStyle(Color(hex: warning.severity.badgeColor))

                            if warning.obssOverlappingAPCount > 0 {
                                Text("(\(warning.obssOverlappingAPCount) Bonded Overlaps)")
                                    .font(Theme.monoText(10))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(warning.advisory)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color(hex: warning.severity.badgeColor).opacity(0.08))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: warning.severity.badgeColor).opacity(0.25), lineWidth: 1))
            }

            // Recommendations Grid
            if recommendations.isEmpty {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Theme.azurePro)
                    Text("Click 'Scan Spectrum' above to calculate optimal non-interfering channels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground)
                .cornerRadius(10)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(recommendations) { rec in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(rec.band.rawValue)
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(hex: rec.band.badgeColor))
                                Spacer()
                                Text("\(rec.cleanlinessScore)% Clean")
                                    .font(Theme.monoText(10, weight: .bold))
                                    .foregroundStyle(rec.cleanlinessScore >= 80 ? Theme.signalEmerald : Theme.solarAmber)
                            }

                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("Channel \(rec.recommendedChannel)")
                                    .font(Theme.monoText(20, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text("(\(rec.channelWidth))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            // Score bar
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(height: 5)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(rec.cleanlinessScore >= 80 ? Theme.signalEmerald : Theme.solarAmber)
                                        .frame(width: max(8, g.size.width * CGFloat(rec.cleanlinessScore) / 100.0), height: 5)
                                }
                            }
                            .frame(height: 5)

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

    // MARK: - Interactive Parabolic Spectrum & Congestion Section

    private var spectrumCongestionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.path.badge.plus")
                            .foregroundStyle(Theme.neonCyan)
                        Text("Interactive RF Spectrum & Channel Geometry")
                            .font(.headline.bold())
                    }
                    Text("Calibrated RF spectrum visualization modeled after WiFi Explorer Pro, featuring true parabolic channel lobes and bonded overlap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Display Mode Picker
                Picker("", selection: $spectrumDisplayMode) {
                    ForEach(SpectrumDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 340)
            }

            // Band Selector Tabs
            HStack(spacing: 8) {
                bandTabButton(title: "2.4 GHz ISM", band: .ghz2_4)
                bandTabButton(title: "5 GHz UNII-1/2/3", band: .ghz5)
                bandTabButton(title: "6 GHz Wi-Fi 6E/7", band: .ghz6)
                Spacer()

                let countInBand = nearbyAPs.filter { $0.band == selectedSpectrumBand }.count
                Text("\(countInBand) BSSIDs in Band")
                    .font(Theme.monoText(11))
                    .foregroundStyle(.secondary)
            }

            if nearbyAPs.isEmpty && currentLink == nil {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Click 'Scan Spectrum' above to sweep over-the-air RF frequencies.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground)
                .cornerRadius(10)
            } else {
                if spectrumDisplayMode == .parabolicCurves {
                    RFSpectrumCanvasView(
                        band: selectedSpectrumBand,
                        networks: nearbyAPs,
                        currentLink: currentLink,
                        selectedAP: $selectedAPForDetail
                    )
                    .frame(height: 250)
                    .background(Theme.cardBackground)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderLight, lineWidth: 1))
                } else {
                    channelDensityBarSection
                }
            }
        }
    }

    private func bandTabButton(title: String, band: WiFiBand) -> some View {
        Button(action: { selectedSpectrumBand = band }) {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(selectedSpectrumBand == band ? Color(hex: band.badgeColor).opacity(0.2) : Theme.cardBackground)
                .foregroundStyle(selectedSpectrumBand == band ? Color(hex: band.badgeColor) : .secondary)
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(selectedSpectrumBand == band ? Color(hex: band.badgeColor).opacity(0.5) : Theme.borderLight, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var channelDensityBarSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                let filteredCongestion = congestion.filter { $0.band == selectedSpectrumBand }
                if filteredCongestion.isEmpty {
                    Text("No APs detected on \(selectedSpectrumBand.rawValue).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(20)
                } else {
                    ForEach(filteredCongestion) { item in
                        VStack(spacing: 6) {
                            Text("Ch \(item.channel)")
                                .font(Theme.monoText(11, weight: item.isCurrentChannel ? .bold : .regular))
                                .foregroundStyle(item.isCurrentChannel ? Theme.neonCyan : .primary)

                            // Bar
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 34, height: 80)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        item.isCurrentChannel ? Theme.cyanPulse :
                                        (item.apCount > 3 ? Theme.pulseCrimson : (item.apCount > 1 ? Theme.solarAmber : Theme.azurePro))
                                    )
                                    .frame(width: 34, height: min(80.0, max(8.0, CGFloat(item.apCount * 16))))
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
            }
            .padding(14)
        }
        .background(Theme.cardBackground)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderLight, lineWidth: 1))
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

    // MARK: - Nearby Networks (Multi-Column Sortable Table)

    private var nearbyNetworksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.indent")
                            .foregroundStyle(Theme.azurePro)
                        Text("Visible Wi-Fi Environments (\(filteredAndSortedNearbyAPs.count))")
                            .font(.headline.bold())
                    }
                    Text("Over-the-air spectrum scan with IEEE 802.11 Layer 2/3 physical metrics, OUI resolution, and interactive column sorting.")
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

            // Quick Filter Chips Row
            HStack(spacing: 8) {
                ForEach(APQuickFilter.allCases, id: \.self) { filter in
                    Button(action: { quickFilter = filter }) {
                        Text(filter.rawValue)
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(quickFilter == filter ? Theme.azurePro.opacity(0.2) : Theme.cardBackground)
                            .foregroundStyle(quickFilter == filter ? Theme.azurePro : .secondary)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(quickFilter == filter ? Theme.azurePro : Theme.borderLight, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
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

            if filteredAndSortedNearbyAPs.isEmpty {
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
                    // Interactive Header
                    HStack {
                        headerSortButton(title: "SSID / BSSID / VENDOR", col: .ssid)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        headerSortButton(title: "CH / BAND", col: .channel)
                            .frame(width: 120, alignment: .leading)
                        headerSortButton(title: "WIDTH", col: .width)
                            .frame(width: 80, alignment: .leading)
                        headerSortButton(title: "FREQ", col: .freq)
                            .frame(width: 80, alignment: .leading)
                        headerSortButton(title: "SIGNAL", col: .signal)
                            .frame(width: 110, alignment: .leading)
                        headerSortButton(title: "SNR", col: .snr)
                            .frame(width: 80, alignment: .leading)
                        headerSortButton(title: "SECURITY", col: .security)
                            .frame(width: 120, alignment: .leading)
                        headerSortButton(title: "PHY", col: .phy)
                            .frame(width: 80, alignment: .trailing)
                        Text("")
                            .frame(width: 32)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.secondaryBackground)
                    .cornerRadius(6)

                    ForEach(filteredAndSortedNearbyAPs) { ap in
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
                                Text("Ch \(ap.channel)")
                                    .font(Theme.monoText(11, weight: .semibold))
                                Text(ap.band.rawValue)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color(hex: ap.band.badgeColor))
                            }
                            .frame(width: 120, alignment: .leading)

                            // Width
                            Text(ap.channelWidth.rawValue)
                                .font(Theme.monoText(10))
                                .frame(width: 80, alignment: .leading)

                            // Center Frequency
                            Text("\(Int(ap.centerFrequencyMHz)) MHz")
                                .font(Theme.monoText(10))
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)

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
                                            Text("N: \(noise) dBm")
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
                            .frame(width: 110, alignment: .leading)

                            // SNR
                            if let snr = ap.snr {
                                Text("\(snr) dB")
                                    .font(Theme.monoText(10, weight: .bold))
                                    .foregroundStyle(snr >= 25 ? Theme.signalEmerald : Theme.solarAmber)
                                    .frame(width: 80, alignment: .leading)
                            } else {
                                Text("—")
                                    .font(Theme.monoText(10))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .leading)
                            }

                            // Security
                            Text(ap.security)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(width: 120, alignment: .leading)

                            // PHY Mode
                            Text(ap.phyMode)
                                .font(Theme.monoText(10))
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .trailing)

                            // Inspector Button
                            Button(action: { selectedAPForDetail = ap }) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(Theme.azurePro)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 32)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(ap.isCurrentAssociation ? Theme.azurePro.opacity(0.08) : Theme.cardBackground)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(ap.isCurrentAssociation ? Theme.cyanPulse.opacity(0.35) : Theme.borderLight, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private func headerSortButton(title: String, col: APSortColumn) -> some View {
        Button(action: {
            if sortColumn == col {
                sortAscending.toggle()
            } else {
                sortColumn = col
                sortAscending = (col == .ssid || col == .bssid || col == .channel)
            }
        }) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption2.bold())
                if sortColumn == col {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.cyanPulse)
                }
            }
            .foregroundStyle(sortColumn == col ? Theme.cyanPulse : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var filteredAndSortedNearbyAPs: [NearbyAP] {
        var list = nearbyAPs

        // 1. Band filter
        if selectedBandFilter != "All" {
            list = list.filter { $0.band.rawValue == selectedBandFilter }
        }

        // 2. Quick filter
        switch quickFilter {
        case .all:
            break
        case .connectedSSID:
            if let currentSSID = currentLink?.ssid, !currentSSID.isEmpty {
                list = list.filter { $0.ssid.lowercased() == currentSSID.lowercased() }
            }
        case .strong:
            list = list.filter { ($0.rssi ?? -100) >= -60 }
        case .weak:
            list = list.filter { ($0.rssi ?? -100) <= -75 }
        case .dfs:
            list = list.filter { $0.isDFS }
        }

        // 3. Search query
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.ssid.lowercased().contains(q) ||
                $0.bssid.lowercased().contains(q) ||
                ($0.vendorName ?? "").lowercased().contains(q) ||
                "\($0.channel)".contains(q) ||
                $0.security.lowercased().contains(q)
            }
        }

        // 4. Sorting
        return list.sorted { a, b in
            let result: Bool
            switch sortColumn {
            case .ssid:
                result = a.ssid.localizedCaseInsensitiveCompare(b.ssid) == .orderedAscending
            case .bssid:
                result = a.bssid < b.bssid
            case .channel:
                result = a.channel < b.channel
            case .band:
                result = a.band.rawValue < b.band.rawValue
            case .width:
                result = a.channelWidth.widthMHz < b.channelWidth.widthMHz
            case .freq:
                result = a.centerFrequencyMHz < b.centerFrequencyMHz
            case .signal:
                result = (a.rssi ?? -100) < (b.rssi ?? -100)
            case .snr:
                result = (a.snr ?? 0) < (b.snr ?? 0)
            case .security:
                result = a.security < b.security
            case .vendor:
                result = (a.vendorName ?? "") < (b.vendorName ?? "")
            case .phy:
                result = a.phyMode < b.phyMode
            }
            return sortAscending ? result : !result
        }
    }

    // MARK: - AP Detail Sheet

    private func apDetailSheet(ap: NearbyAP) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(Theme.cyanPulse)
                        Text(ap.ssid.isEmpty ? "Hidden Network" : ap.ssid)
                            .font(.title2.bold())
                    }
                    Text("Detailed IEEE 802.11 Layer 1/2 Radio Profile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { selectedAPForDetail = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            VStack(spacing: 12) {
                summaryRow(label: "BSSID (Access Point MAC)", value: ap.bssid, isMono: true)
                if let vendor = ap.vendorName {
                    summaryRow(label: "IEEE OUI Hardware Vendor", value: vendor, isMono: false)
                }
                summaryRow(label: "Operating Channel", value: "Ch \(ap.channel) (\(ap.band.rawValue))", isMono: true)
                summaryRow(label: "Channel Bandwidth", value: ap.channelWidth.rawValue, isMono: false)
                summaryRow(label: "Center Frequency", value: "\(Int(ap.centerFrequencyMHz)) MHz", isMono: true)
                summaryRow(label: "Spectrum Span", value: "\(Int(ap.frequencySpanMHz.lowerBound)) – \(Int(ap.frequencySpanMHz.upperBound)) MHz", isMono: true)
                if let unii = ap.uniiSubBand {
                    summaryRow(label: "UNII Sub-Band", value: "\(unii) \(ap.isDFS ? "(DFS Radar Sensitive)" : "")", isMono: false)
                }
                summaryRow(label: "Received Signal (RSSI)", value: ap.rssi != nil ? "\(ap.rssi!) dBm" : "N/A", isMono: true)
                summaryRow(label: "Noise Floor", value: ap.noise != nil ? "\(ap.noise!) dBm" : "N/A", isMono: true)
                if let snr = ap.snr {
                    summaryRow(label: "Signal-to-Noise Ratio (SNR)", value: "\(snr) dB", isMono: true)
                }
                summaryRow(label: "Security Suite", value: ap.security, isMono: false)
                summaryRow(label: "PHY Standard", value: ap.phyMode, isMono: false)
                summaryRow(label: "Active Connected Link", value: ap.isCurrentAssociation ? "Yes (Current Host Association)" : "No (Neighbor BSSID)", isMono: false)
            }

            Spacer()

            HStack {
                Button(action: {
                    copyToClipboard(ap.bssid, message: "Copied BSSID \(ap.bssid)")
                }) {
                    Label("Copy BSSID", systemImage: "doc.on.doc")
                        .font(.caption.bold())
                }

                Button(action: {
                    let summary = "SSID: \(ap.ssid)\nBSSID: \(ap.bssid)\nVendor: \(ap.vendorName ?? "Unknown")\nCh \(ap.channel) (\(ap.channelWidth.rawValue), \(ap.band.rawValue))\nRSSI: \(ap.rssi ?? 0) dBm"
                    copyToClipboard(summary, message: "Copied AP telemetry")
                }) {
                    Label("Copy Full AP Details", systemImage: "list.clipboard")
                        .font(.caption.bold())
                }

                Spacer()
            }
        }
        .padding(24)
        .frame(width: 520, height: 480)
        .background(Theme.surfaceBackground)
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

    private func exportCSVToClipboard() {
        let engine = WiFiEngine.shared
        Task {
            let report = await engine.generateSurveyReport(currentLink: currentLink, networks: nearbyAPs)
            let csv = report.toCSV()
            copyToClipboard(csv, message: "Copied CSV AP Inventory to clipboard")
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

    private func saveCSVInventory() {
        let engine = WiFiEngine.shared
        Task {
            let report = await engine.generateSurveyReport(currentLink: currentLink, networks: nearbyAPs)
            let csv = report.toCSV()

            await MainActor.run {
                let panel = NSSavePanel()
                let csvType = UTType(filenameExtension: "csv") ?? .commaSeparatedText
                panel.allowedContentTypes = [csvType, .plainText]
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd_HHmm"
                panel.nameFieldStringValue = "NexWave_WiFi_Inventory_\(df.string(from: Date())).csv"
                panel.prompt = "Save AP Inventory CSV"

                if panel.runModal() == .OK, let url = panel.url {
                    try? csv.write(to: url, atomically: true, encoding: .utf8)
                    copyToClipboard("", message: "Saved AP Inventory to \(url.lastPathComponent)")
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

    // MARK: - Live Telemetry Controller

    private func startLiveMonitor() {
        timerTask?.cancel()
        timerTask = Task {
            var tickCount = 0
            while !Task.isCancelled {
                await pollTelemetry()
                tickCount += 1
                if tickCount >= 8 {
                    tickCount = 0
                    if !isScanning {
                        await performFullScan()
                    }
                }
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
            self.stickyClientAnomaly = await engine.evaluateStickyClientAnomaly(currentLink: link, networks: self.nearbyAPs)
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
            self.stickyClientAnomaly = await engine.evaluateStickyClientAnomaly(currentLink: link, networks: nets)
        } else {
            self.recommendations = await engine.recommendOptimalChannels(from: nets, currentChannel: 0)
        }
        isScanning = false
    }
}

// MARK: - Parabolic RF Spectral Curve Canvas

struct RFSpectrumCanvasView: View {
    let band: WiFiBand
    let networks: [NearbyAP]
    let currentLink: WiFiCurrentLink?
    @Binding var selectedAP: NearbyAP?

    @State private var hoveredAP: NearbyAP? = nil
    @State private var hoverLocation: CGPoint = .zero
    @State private var isHovering: Bool = false

    private let leftMargin: CGFloat = 55.0
    private let rightMargin: CGFloat = 25.0
    private let topMargin: CGFloat = 30.0
    private let bottomMargin: CGFloat = 32.0

    private var domain: (minFreq: Double, maxFreq: Double) {
        switch band {
        case .ghz2_4:
            return (2400.0, 2495.0)
        case .ghz5:
            return (5160.0, 5845.0)
        case .ghz6:
            return (5935.0, 7115.0)
        case .unknown:
            return (5160.0, 5845.0)
        }
    }

    private var standardChannels: [(ch: Int, freq: Double, label: String)] {
        switch band {
        case .ghz2_4:
            return [
                (1, 2412, "1"), (3, 2422, "3"), (6, 2437, "6"),
                (9, 2452, "9"), (11, 2462, "11"), (14, 2484, "14")
            ]
        case .ghz5:
            return [
                (36, 5180, "36"), (44, 5220, "44"), (52, 5260, "52"), (60, 5300, "60"),
                (100, 5500, "100"), (116, 5580, "116"), (132, 5660, "132"), (149, 5745, "149"), (161, 5805, "161")
            ]
        case .ghz6:
            return [
                (37, 6135, "37 PSC"), (69, 6295, "69 PSC"), (101, 6455, "101 PSC"),
                (133, 6615, "133 PSC"), (165, 6775, "165 PSC"), (197, 6935, "197 PSC")
            ]
        case .unknown:
            return []
        }
    }

    private var apsInBand: [NearbyAP] {
        var aps = networks.filter { $0.band == band }

        if let link = currentLink, link.band == band {
            if let idx = aps.firstIndex(where: { $0.isCurrentAssociation || $0.bssid.lowercased() == link.bssid.lowercased() }) {
                let existing = aps[idx]
                aps[idx] = NearbyAP(
                    ssid: link.ssid,
                    bssid: link.bssid,
                    vendorName: link.vendorName ?? existing.vendorName,
                    channel: link.channel,
                    band: link.band,
                    channelWidth: link.channelWidth,
                    rssi: link.rssi,
                    noise: link.noise,
                    security: link.security,
                    phyMode: link.phyMode.displayName,
                    isCurrentAssociation: true
                )
            } else {
                aps.append(
                    NearbyAP(
                        ssid: link.ssid,
                        bssid: link.bssid,
                        vendorName: link.vendorName,
                        channel: link.channel,
                        band: link.band,
                        channelWidth: link.channelWidth,
                        rssi: link.rssi,
                        noise: link.noise,
                        security: link.security,
                        phyMode: link.phyMode.displayName,
                        isCurrentAssociation: true
                    )
                )
            }
        }

        return aps.sorted { a, _ in !a.isCurrentAssociation }
    }

    private func drawableW(for size: CGSize) -> CGFloat {
        max(10, size.width - leftMargin - rightMargin)
    }

    private func drawableH(for size: CGSize) -> CGFloat {
        max(10, size.height - topMargin - bottomMargin)
    }

    private func baseLineY(for size: CGSize) -> CGFloat {
        size.height - bottomMargin
    }

    private func xFor(freq: Double, size: CGSize) -> CGFloat {
        let d = domain
        let clampedFreq = max(d.minFreq, min(d.maxFreq, freq))
        let ratio = (clampedFreq - d.minFreq) / (d.maxFreq - d.minFreq)
        return leftMargin + CGFloat(ratio) * drawableW(for: size)
    }

    private func yFor(signal: Double, size: CGSize) -> CGFloat {
        let clamped = max(-100.0, min(-20.0, signal))
        let ratio = (clamped - (-100.0)) / (-20.0 - (-100.0))
        return baseLineY(for: size) - CGFloat(ratio) * drawableH(for: size)
    }

    private func findAP(at location: CGPoint, in aps: [NearbyAP], size: CGSize) -> NearbyAP? {
        let base = baseLineY(for: size)
        guard location.x >= leftMargin - 5 && location.x <= (size.width - rightMargin + 5) &&
              location.y >= topMargin - 15 && location.y <= base + 15 else {
            return nil
        }

        var bestMatch: (ap: NearbyAP, score: CGFloat)? = nil

        for ap in aps {
            let span = ap.frequencySpanMHz
            let xL = xFor(freq: span.lowerBound, size: size)
            let xR = xFor(freq: span.upperBound, size: size)
            let xC = xFor(freq: ap.centerFrequencyMHz, size: size)
            guard xR > xL + 2 else { continue }

            let isConn = ap.isCurrentAssociation
            let sig = Double(isConn ? (currentLink?.rssi ?? ap.rssi ?? -50) : (ap.rssi ?? -85))
            let yPeak = yFor(signal: sig, size: size)

            let halfSpan = max(4.0, (xR - xL) / 2.0)
            let dx = abs(location.x - xC)

            if dx <= halfSpan + 8.0 {
                let u = min(1.0, dx / halfSpan)
                let curveY = yPeak + (base - yPeak) * (u * u)

                let distFromPeak = hypot(location.x - xC, location.y - yPeak)
                let isInsideCurve = location.y >= (curveY - 18) && location.y <= (base + 8)

                if distFromPeak < 32 || isInsideCurve {
                    let score = distFromPeak - (isConn ? 120 : 0)
                    if bestMatch == nil || score < (bestMatch?.score ?? .infinity) {
                        bestMatch = (ap, score)
                    }
                }
            }
        }

        return bestMatch?.ap
    }

    var body: some View {
        let channels = standardChannels
        let aps = apsInBand

        GeometryReader { geo in
            let size = geo.size
            let base = baseLineY(for: size)

            ZStack {
                Canvas { context, canvasSize in
                    // 1. Draw horizontal dBm reference grid lines
                    let gridLevels: [(dBm: Double, label: String)] = [
                        (-30, "-30 dBm"),
                        (-50, "-50 dBm"),
                        (-70, "-70 dBm"),
                        (-85, "-85 dBm")
                    ]

                    for grid in gridLevels {
                        let y = yFor(signal: grid.dBm, size: canvasSize)
                        var line = Path()
                        line.move(to: CGPoint(x: leftMargin, y: y))
                        line.addLine(to: CGPoint(x: canvasSize.width - rightMargin, y: y))
                        context.stroke(line, with: .color(Color.primary.opacity(0.08)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        let text = Text(grid.label)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color.secondary.opacity(0.6))
                        context.draw(text, at: CGPoint(x: 28, y: y))
                    }

                    // 2. Draw channel vertical grid ticks & labels
                    for chInfo in channels {
                        let x = xFor(freq: chInfo.freq, size: canvasSize)
                        if x >= leftMargin && x <= (canvasSize.width - rightMargin) {
                            var vline = Path()
                            vline.move(to: CGPoint(x: x, y: topMargin))
                            vline.addLine(to: CGPoint(x: x, y: base))
                            context.stroke(vline, with: .color(Color.primary.opacity(0.05)), lineWidth: 1)

                            let chText = Text(chInfo.label)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(Color.secondary)
                            context.draw(chText, at: CGPoint(x: x, y: base + 14))
                        }
                    }

                    // 3. Draw Watermark if no APs in band
                    if aps.isEmpty {
                        let emptyMsg = Text("No \(band.displayName) BSSIDs detected in range.\nClick 'Scan Spectrum' or switch frequency bands.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.secondary.opacity(0.6))
                        context.draw(emptyMsg, at: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2))
                    }

                    // 4. Draw Parabolic Curves for APs in this band
                    for ap in aps {
                        let isConn = ap.isCurrentAssociation
                        let isHovered = (hoveredAP?.bssid == ap.bssid)
                        let span = ap.frequencySpanMHz
                        let xL = xFor(freq: span.lowerBound, size: canvasSize)
                        let xR = xFor(freq: span.upperBound, size: canvasSize)
                        let xC = xFor(freq: ap.centerFrequencyMHz, size: canvasSize)
                        guard xR > xL + 2 else { continue }

                        let sig = Double(isConn ? (currentLink?.rssi ?? ap.rssi ?? -50) : (ap.rssi ?? -85))
                        let yPeak = yFor(signal: sig, size: canvasSize)

                        var curve = Path()
                        curve.move(to: CGPoint(x: xL, y: base))
                        // Ascending cubic bezier
                        curve.addCurve(
                            to: CGPoint(x: xC, y: yPeak),
                            control1: CGPoint(x: xL + (xC - xL) * 0.35, y: base),
                            control2: CGPoint(x: xC - (xC - xL) * 0.25, y: yPeak)
                        )
                        // Descending cubic bezier
                        curve.addCurve(
                            to: CGPoint(x: xR, y: base),
                            control1: CGPoint(x: xC + (xR - xC) * 0.25, y: yPeak),
                            control2: CGPoint(x: xR - (xR - xC) * 0.35, y: base)
                        )
                        curve.closeSubpath()

                        let curveColor = isConn ? Theme.cyanPulse : Color(hex: ap.band.badgeColor)

                        // Fill gradient
                        context.fill(
                            curve,
                            with: .linearGradient(
                                Gradient(colors: [
                                    curveColor.opacity(isConn ? 0.45 : (isHovered ? 0.35 : 0.18)),
                                    curveColor.opacity(0.03)
                                ]),
                                startPoint: CGPoint(x: xC, y: yPeak),
                                endPoint: CGPoint(x: xC, y: base)
                            )
                        )

                        // Hover plumb line & highlight
                        if isHovered {
                            var plumbLine = Path()
                            plumbLine.move(to: CGPoint(x: xC, y: yPeak))
                            plumbLine.addLine(to: CGPoint(x: xC, y: base))
                            context.stroke(plumbLine, with: .color(Theme.solarAmber.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                            context.stroke(curve, with: .color(Theme.solarAmber), lineWidth: 2.2)
                        }

                        // Stroke
                        if isConn {
                            // Outer glow
                            context.stroke(curve, with: .color(Theme.cyanPulse.opacity(0.35)), lineWidth: 5)
                            context.stroke(curve, with: .color(Theme.neonCyan), lineWidth: 2.5)

                            // Peak indicator diamond
                            var diamond = Path()
                            diamond.move(to: CGPoint(x: xC, y: yPeak - 5))
                            diamond.addLine(to: CGPoint(x: xC + 4, y: yPeak))
                            diamond.addLine(to: CGPoint(x: xC, y: yPeak + 5))
                            diamond.addLine(to: CGPoint(x: xC - 4, y: yPeak))
                            diamond.closeSubpath()
                            context.fill(diamond, with: .color(Theme.neonCyan))

                            // Peak text label
                            let labelText = Text("CONNECTED • \(ap.ssid) (\(Int(sig)) dBm)")
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundColor(Theme.neonCyan)
                            context.draw(labelText, at: CGPoint(x: xC, y: max(14, yPeak - 12)))
                        } else {
                            if !isHovered {
                                context.stroke(curve, with: .color(curveColor.opacity(0.85)), lineWidth: 1.5)
                            }

                            // Peak label for distinct networks
                            let apLabel = Text("\(ap.ssid) (\(Int(sig)))")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundColor(isHovered ? Theme.solarAmber : Color.primary.opacity(0.8))
                            context.draw(apLabel, at: CGPoint(x: xC, y: max(12, yPeak - 10)))
                        }
                    }
                }

                // 5. Floating Interactive Hover Tooltip Card
                if let ap = hoveredAP, isHovering {
                    let cardW: CGFloat = 220
                    let cardH: CGFloat = 85
                    let posX = min(max(cardW / 2 + 10, hoverLocation.x), size.width - cardW / 2 - 10)
                    let posY = hoverLocation.y > 105 ? (hoverLocation.y - cardH / 2 - 20) : (hoverLocation.y + cardH / 2 + 25)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(ap.isCurrentAssociation ? Theme.signalEmerald : Color(hex: ap.band.badgeColor))
                                .frame(width: 8, height: 8)
                            Text(ap.ssid)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if ap.isCurrentAssociation {
                                Text("CONNECTED")
                                    .font(.system(size: 7.5, weight: .black))
                                    .foregroundColor(Theme.neonCyan)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Theme.neonCyan.opacity(0.18))
                                    .cornerRadius(3)
                            }
                            Spacer(minLength: 0)
                        }

                        HStack(spacing: 8) {
                            Label("\(ap.rssi ?? -85) dBm", systemImage: "antenna.radiowaves.left.and.right")
                            Label("Ch \(ap.channel) • \(ap.channelWidth.rawValue)", systemImage: "waveform.path")
                        }
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            Text(ap.vendorName ?? "Unknown Vendor")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.9))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text("Click to Inspect ↗")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Theme.neonCyan)
                        }
                    }
                    .padding(10)
                    .frame(width: cardW)
                    .background(.ultraThinMaterial)
                    .background(Theme.cardBackground.opacity(0.92))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ap.isCurrentAssociation ? Theme.neonCyan.opacity(0.6) : Theme.solarAmber.opacity(0.5), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 5)
                    .position(x: posX, y: posY)
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    hoverLocation = loc
                    isHovering = true
                    hoveredAP = findAP(at: loc, in: aps, size: size)
                case .ended:
                    isHovering = false
                    hoveredAP = nil
                }
            }
            .onTapGesture {
                if let ap = hoveredAP {
                    selectedAP = ap
                }
            }
        }
    }
}

// MARK: - Calibrated Dual-Trace Signal & Noise Graph

struct RFDualTraceGraphView: View {
    let samples: [(timestamp: Date, rssi: Int, noise: Int)]
    let currentRSSI: Int
    let currentNoise: Int

    private var stats: (minRssi: Int, maxRssi: Int, avgRssi: Double, jitter: Double) {
        guard !samples.isEmpty else { return (currentRSSI, currentRSSI, Double(currentRSSI), 0.0) }
        let rssiList = samples.map(\.rssi)
        let minR = rssiList.min() ?? currentRSSI
        let maxR = rssiList.max() ?? currentRSSI
        let avg = Double(rssiList.reduce(0, +)) / Double(rssiList.count)
        let variance = rssiList.reduce(0.0) { $0 + pow(Double($1) - avg, 2) } / Double(rssiList.count)
        let stdDev = sqrt(variance)
        return (minR, maxR, avg, stdDev)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Stats Header Strip
            HStack {
                Text("LIVE RF TELEMETRY TRACE (120s WINDOW)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 14) {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.signalEmerald).frame(width: 6, height: 6)
                        Text("RSSI: \(currentRSSI) dBm")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(Theme.signalEmerald)
                    }

                    HStack(spacing: 4) {
                        Circle().fill(Theme.pulseCrimson).frame(width: 6, height: 6)
                        Text("Noise: \(currentNoise) dBm")
                            .font(Theme.monoText(10))
                            .foregroundStyle(.secondary)
                    }

                    Text("Range: [\(stats.minRssi) ... \(stats.maxRssi)]")
                        .font(Theme.monoText(10))
                        .foregroundStyle(.secondary)

                    Text("Jitter: ±\(String(format: "%.1f", stats.jitter)) dB")
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(Theme.azurePro)
                }
            }

            // Canvas Dual-Trace
            Canvas { context, size in
                let leftMargin: CGFloat = 45.0
                let rightMargin: CGFloat = 15.0
                let topMargin: CGFloat = 8.0
                let bottomMargin: CGFloat = 16.0

                let drawableW = size.width - leftMargin - rightMargin
                let drawableH = size.height - topMargin - bottomMargin
                let baseLineY = size.height - bottomMargin

                func yFor(dBm: Double) -> CGFloat {
                    let clamped = max(-100.0, min(-20.0, dBm))
                    let ratio = (clamped - (-100.0)) / (-20.0 - (-100.0))
                    return baseLineY - CGFloat(ratio) * drawableH
                }

                // Grid Lines
                for gridDbm in [-30.0, -50.0, -70.0, -90.0] {
                    let y = yFor(dBm: gridDbm)
                    var line = Path()
                    line.move(to: CGPoint(x: leftMargin, y: y))
                    line.addLine(to: CGPoint(x: size.width - rightMargin, y: y))
                    context.stroke(line, with: .color(Color.primary.opacity(0.06)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    let t = Text("\(Int(gridDbm))")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.secondary.opacity(0.5))
                    context.draw(t, at: CGPoint(x: 24, y: y))
                }

                guard samples.count > 1 else { return }

                // Trace Points
                var rssiPoints: [CGPoint] = []
                var noisePoints: [CGPoint] = []

                for i in 0..<samples.count {
                    let ratio = CGFloat(i) / CGFloat(samples.count - 1)
                    let x = leftMargin + ratio * drawableW
                    let yR = yFor(dBm: Double(samples[i].rssi))
                    let yN = yFor(dBm: Double(samples[i].noise))
                    rssiPoints.append(CGPoint(x: x, y: yR))
                    noisePoints.append(CGPoint(x: x, y: yN))
                }

                // Shaded SNR margin between RSSI and Noise
                var snrArea = Path()
                snrArea.move(to: rssiPoints[0])
                for pt in rssiPoints.dropFirst() { snrArea.addLine(to: pt) }
                for pt in noisePoints.reversed() { snrArea.addLine(to: pt) }
                snrArea.closeSubpath()
                context.fill(snrArea, with: .linearGradient(
                    Gradient(colors: [Theme.signalEmerald.opacity(0.25), Theme.cyanPulse.opacity(0.08)]),
                    startPoint: CGPoint(x: leftMargin, y: topMargin),
                    endPoint: CGPoint(x: leftMargin, y: baseLineY)
                ))

                // Noise Trace Line
                var noiseLine = Path()
                noiseLine.move(to: noisePoints[0])
                for pt in noisePoints.dropFirst() { noiseLine.addLine(to: pt) }
                context.stroke(noiseLine, with: .color(Theme.pulseCrimson.opacity(0.6)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))

                // RSSI Trace Line
                var rssiLine = Path()
                rssiLine.move(to: rssiPoints[0])
                for pt in rssiPoints.dropFirst() { rssiLine.addLine(to: pt) }
                context.stroke(rssiLine, with: .linearGradient(
                    Gradient(colors: [Theme.signalEmerald, Theme.neonCyan]),
                    startPoint: CGPoint(x: leftMargin, y: baseLineY),
                    endPoint: CGPoint(x: size.width - rightMargin, y: topMargin)
                ), lineWidth: 2)

                // Current endpoint glowing dot
                if let lastPt = rssiPoints.last {
                    context.fill(Circle().path(in: CGRect(x: lastPt.x - 4, y: lastPt.y - 4, width: 8, height: 8)), with: .color(Theme.neonCyan))
                }
            }
            .frame(height: 90)
            .padding(10)
            .background(Theme.secondaryBackground.opacity(0.5))
            .cornerRadius(8)
        }
    }
}
