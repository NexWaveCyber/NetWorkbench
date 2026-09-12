import SwiftUI
import WiFiKit

public struct WiFiStudioView: View {
    @State private var currentLink: WiFiCurrentLink? = nil
    @State private var nearbyAPs: [NearbyAP] = []
    @State private var roamingEvents: [WiFiRoamingEvent] = []
    @State private var congestion: [ChannelCongestion] = []
    @State private var rssiSamples: [(timestamp: Date, rssi: Int, noise: Int)] = []

    @State private var isScanning = false
    @State private var isAutoRefresh = true
    @State private var selectedBandFilter: String = "All"
    @State private var searchText = ""
    @State private var timerTask: Task<Void, Never>? = nil

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerBar
                
                if let link = currentLink {
                    rfHealthHeroCard(link: link)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        apAssociationCard(link: link)
                        channelBandCard(link: link)
                    }
                } else {
                    disconnectedStateCard
                }

                spectrumCongestionSection

                if !roamingEvents.isEmpty {
                    roamingAuditSection
                }

                nearbyNetworksSection
            }
            .padding(20)
        }
        .background(Theme.surfaceBackground)
        .onAppear {
            startLiveMonitor()
        }
        .onDisappear {
            stopLiveMonitor()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "wifi")
                        .font(.system(size: 20, weight: .bold))
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
                    }
                }
                Text("Real-time CoreWLAN RF telemetry, 802.11 association, AP roaming audit, and channel congestion.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                // Auto refresh toggle
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

                // Scan Nearby Button
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
                    Text("RF LINK HEALTH: \(link.signalQuality.rawValue.uppercased())")
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

            // Primary 4 Telemetry Metrics
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                telemetryTile(
                    title: "SIGNAL (RSSI)",
                    value: "\(link.rssi) dBm",
                    subtext: link.rssi >= -50 ? "Excellent" : (link.rssi >= -65 ? "Strong" : "Weak"),
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
                    subtext: link.snr >= 35 ? "High Margin" : (link.snr >= 20 ? "Acceptable" : "Degraded"),
                    color: link.snr >= 25 ? Theme.signalEmerald : Theme.pulseCrimson,
                    icon: "chart.bar.xaxis"
                )

                telemetryTile(
                    title: "PHY TX RATE",
                    value: link.transmitRate > 0 ? "\(Int(link.transmitRate)) Mbps" : "N/A",
                    subtext: link.mcsIndex != nil ? "MCS Index: \(link.mcsIndex!)" : link.phyMode.displayName,
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
                        Text("Current: \(link.rssi) dBm | Noise: \(link.noise) dBm")
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
                detailRow(label: "BSSID (Hardware MAC)", value: link.bssid, isMono: true)
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
                detailRow(label: "Operating Channel", value: "Channel \(link.channel)", isMono: true)
                detailRow(label: "Channel Width", value: link.channelWidth.rawValue, isMono: true)
                detailRow(label: "PHY Standard", value: link.phyMode.displayName, isMono: false)
                detailRow(label: "Max Theoretical Speed", value: link.transmitRate > 0 ? "\(Int(link.transmitRate)) Mbps" : "Auto", isMono: true)
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
                                    .frame(width: 32, height: 60)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        item.isCurrentChannel ? Theme.cyanPulse :
                                        (item.apCount > 3 ? Theme.pulseCrimson : Theme.azurePro)
                                    )
                                    .frame(width: 32, height: min(60.0, max(8.0, CGFloat(item.apCount * 14))))
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

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("BSSID Roam: \(event.previousBSSID) -> \(event.newBSSID)")
                                    .font(Theme.monoText(12, weight: .bold))
                                Spacer()
                                Text(event.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 12) {
                                Text("Ch: \(event.previousChannel) -> Ch: \(event.newChannel)")
                                    .font(Theme.monoText(11))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 4) {
                                    Text("RSSI:")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(event.previousRSSI) dBm -> \(event.newRSSI) dBm")
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
                TextField("Filter by SSID, BSSID, or Channel...", text: $searchText)
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
                        Text("SSID / BSSID")
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
                            VStack(alignment: .leading, spacing: 2) {
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
                                Text(ap.bssid)
                                    .font(Theme.monoText(10))
                                    .foregroundStyle(.secondary)
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
                                            Text("Noise: \(noise)")
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
        }
        isScanning = false
    }
}
