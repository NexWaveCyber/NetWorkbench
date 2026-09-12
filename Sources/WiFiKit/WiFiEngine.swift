import Foundation
import CoreWLAN

public actor WiFiEngine {
    public static let shared = WiFiEngine()

    private var previousBSSID: String?
    private var previousRSSI: Int = 0
    private var previousChannel: Int = 0
    private var roamingHistory: [WiFiRoamingEvent] = []
    private var rssiHistory: [(timestamp: Date, rssi: Int, noise: Int)] = []

    public init() {}

    /// Fetches the current active Wi-Fi link telemetry
    public func fetchCurrentLink(interfaceName: String? = nil) async -> WiFiCurrentLink? {
        let client = CWWiFiClient.shared()
        guard let wlan = interfaceName != nil ? client.interface(withName: interfaceName) : client.interface() else {
            return nil
        }

        let ifName = wlan.interfaceName ?? "en0"
        let macAddress = wlan.hardwareAddress() ?? "00:00:00:00:00:00"
        let rawRSSI = wlan.rssiValue()
        let rawNoise = wlan.noiseMeasurement()
        let rawTxRate = wlan.transmitRate()

        // Extract channel and band
        let cwChannel = wlan.wlanChannel()
        let channelNum = cwChannel?.channelNumber ?? 0
        let band: WiFiBand
        switch cwChannel?.channelBand {
        case .band2GHz:
            band = .ghz2_4
        case .band5GHz:
            band = .ghz5
        case .band6GHz:
            band = .ghz6
        default:
            if channelNum <= 14 {
                band = .ghz2_4
            } else if channelNum <= 177 {
                band = .ghz5
            } else if channelNum > 0 {
                band = .ghz6
            } else {
                band = .unknown
            }
        }

        let width: WiFiChannelWidth
        switch cwChannel?.channelWidth {
        case .width20MHz: width = .mhz20
        case .width40MHz: width = .mhz40
        case .width80MHz: width = .mhz80
        case .width160MHz: width = .mhz160
        default: width = .unknown
        }

        let phyMode: WiFiPHYMode
        switch wlan.activePHYMode() {
        case .mode11b:  phyMode = .b
        case .mode11g:  phyMode = .g
        case .mode11a:  phyMode = .a
        case .mode11n:  phyMode = .n
        case .mode11ac: phyMode = .ac
        case .mode11ax: phyMode = .ax
        default:        phyMode = .ax // Modern standard
        }

        let countryCode = wlan.countryCode() ?? "US"

        // Enrich with system ipconfig summary for exact SSID, BSSID, and DHCP details
        let systemSummary = await fetchIPConfigSummary(interface: ifName)
        let ssid = systemSummary.ssid.isEmpty ? (wlan.ssid() ?? "Wi-Fi Network") : systemSummary.ssid
        let bssid = systemSummary.bssid.isEmpty ? (wlan.bssid() ?? "00:00:00:00:00:00") : systemSummary.bssid
        let security = systemSummary.security.isEmpty ? "WPA2/WPA3 Personal" : systemSummary.security
        let dhcpServer = systemSummary.dhcpServer

        // Check for roaming event
        let now = Date()
        if let prevBSSID = previousBSSID, !bssid.isEmpty, bssid != "00:00:00:00:00:00", bssid != prevBSSID {
            let event = WiFiRoamingEvent(
                timestamp: now,
                ssid: ssid,
                previousBSSID: prevBSSID,
                newBSSID: bssid,
                previousRSSI: previousRSSI,
                newRSSI: rawRSSI,
                previousChannel: previousChannel,
                newChannel: channelNum
            )
            roamingHistory.insert(event, at: 0)
            if roamingHistory.count > 50 {
                roamingHistory.removeLast()
            }
        }

        previousBSSID = bssid
        previousRSSI = rawRSSI
        previousChannel = channelNum

        // Append to time-series history
        rssiHistory.append((timestamp: now, rssi: rawRSSI, noise: rawNoise))
        if rssiHistory.count > 120 {
            rssiHistory.removeFirst(rssiHistory.count - 120)
        }

        return WiFiCurrentLink(
            interfaceName: ifName,
            macAddress: macAddress,
            ssid: ssid,
            bssid: bssid,
            rssi: rawRSSI,
            noise: rawNoise,
            transmitRate: rawTxRate,
            mcsIndex: extractMCSIndex(txRate: rawTxRate),
            channel: channelNum,
            band: band,
            channelWidth: width,
            phyMode: phyMode,
            security: security,
            countryCode: countryCode,
            dhcpServer: dhcpServer,
            timestamp: now
        )
    }

    /// Fetches all recorded AP Roaming events
    public func getRoamingHistory() -> [WiFiRoamingEvent] {
        return roamingHistory
    }

    /// Fetches RSSI/Noise time-series samples
    public func getRSSIHistory() -> [(timestamp: Date, rssi: Int, noise: Int)] {
        return rssiHistory
    }

    /// Scans surrounding APs and combines CoreWLAN scan with system profiler data
    public func scanNearbyNetworks(interfaceName: String? = nil) async -> [NearbyAP] {
        var networks: [NearbyAP] = []
        let currentBSSID = previousBSSID ?? ""

        // 1. CoreWLAN hardware scan for channels and live RSSI
        let client = CWWiFiClient.shared()
        let wlan = interfaceName != nil ? client.interface(withName: interfaceName) : client.interface()
        var scannedChannels: [Int: (rssi: Int, band: WiFiBand, width: WiFiChannelWidth)] = [:]

        if let iface = wlan, let cwNets = try? iface.scanForNetworks(withSSID: nil) {
            for net in cwNets {
                if let ch = net.wlanChannel {
                    let band: WiFiBand
                    switch ch.channelBand {
                    case .band2GHz: band = .ghz2_4
                    case .band5GHz: band = .ghz5
                    case .band6GHz: band = .ghz6
                    default: band = ch.channelNumber <= 14 ? .ghz2_4 : .ghz5
                    }

                    let width: WiFiChannelWidth
                    switch ch.channelWidth {
                    case .width20MHz: width = .mhz20
                    case .width40MHz: width = .mhz40
                    case .width80MHz: width = .mhz80
                    case .width160MHz: width = .mhz160
                    default: width = .mhz20
                    }

                    scannedChannels[ch.channelNumber] = (rssi: net.rssiValue, band: band, width: width)
                }
            }
        }

        // 2. Parse system_profiler for rich names, PHY modes, and security
        let profilerNets = await fetchSystemProfilerNetworks()
        for pNet in profilerNets {
            let chInfo = scannedChannels[pNet.channel]
            let effectiveRSSI = pNet.rssi ?? chInfo?.rssi ?? -65
            let effectiveBand = chInfo?.band ?? pNet.band
            let effectiveWidth = chInfo?.width ?? pNet.channelWidth

            let isAssoc = !currentBSSID.isEmpty && (pNet.bssid.lowercased() == currentBSSID.lowercased() || pNet.isCurrentAssociation)

            let ap = NearbyAP(
                ssid: pNet.ssid,
                bssid: pNet.bssid,
                channel: pNet.channel,
                band: effectiveBand,
                channelWidth: effectiveWidth,
                rssi: effectiveRSSI,
                noise: pNet.noise ?? -85,
                security: pNet.security,
                phyMode: pNet.phyMode,
                isCurrentAssociation: isAssoc
            )
            networks.append(ap)
        }

        // Fallback: If system_profiler returned empty, generate synthetic entries from CoreWLAN scanned channels
        if networks.isEmpty && !scannedChannels.isEmpty {
            for (ch, data) in scannedChannels {
                let ap = NearbyAP(
                    ssid: "Local AP (Ch \(ch))",
                    bssid: String(format: "02:00:00:00:%02X:%02X", ch, abs(data.rssi)),
                    channel: ch,
                    band: data.band,
                    channelWidth: data.width,
                    rssi: data.rssi,
                    noise: -85,
                    security: "WPA2/WPA3",
                    phyMode: data.band == .ghz6 ? "802.11ax (6GHz)" : (data.band == .ghz5 ? "802.11ax" : "802.11n"),
                    isCurrentAssociation: false
                )
                networks.append(ap)
            }
        }

        return networks.sorted { ($0.rssi ?? -100) > ($1.rssi ?? -100) }
    }

    /// Calculates Channel Congestion across frequency bands
    public func calculateChannelCongestion(from networks: [NearbyAP], currentChannel: Int) -> [ChannelCongestion] {
        var counts: [Int: (band: WiFiBand, count: Int)] = [:]
        for net in networks {
            let existing = counts[net.channel]?.count ?? 0
            counts[net.channel] = (band: net.band, count: existing + 1)
        }

        var congestionList: [ChannelCongestion] = []
        for (channel, info) in counts {
            congestionList.append(
                ChannelCongestion(
                    band: info.band,
                    channel: channel,
                    apCount: info.count,
                    isCurrentChannel: channel == currentChannel
                )
            )
        }

        return congestionList.sorted {
            if $0.band.rawValue != $1.band.rawValue {
                return $0.band.rawValue < $1.band.rawValue
            }
            return $0.channel < $1.channel
        }
    }

    // MARK: - Private Telemetry Helpers

    private func extractMCSIndex(txRate: Double) -> Int? {
        if txRate >= 1200 { return 11 }
        if txRate >= 1080 { return 10 }
        if txRate >= 960  { return 9 }
        if txRate >= 864  { return 8 }
        if txRate >= 720  { return 7 }
        if txRate >= 576  { return 6 }
        if txRate >= 432  { return 5 }
        if txRate >= 288  { return 4 }
        if txRate >= 144  { return 2 }
        return nil
    }

    private func fetchIPConfigSummary(interface: String) async -> (ssid: String, bssid: String, security: String, dhcpServer: String?) {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
        process.arguments = ["getsummary", interface]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return ("", "", "", nil)
            }

            var ssid = ""
            var bssid = ""
            var security = ""
            var dhcpServer: String? = nil

            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.starts(with: "SSID : ") {
                    ssid = trimmed.replacingOccurrences(of: "SSID : ", with: "")
                } else if trimmed.starts(with: "BSSID : ") {
                    bssid = trimmed.replacingOccurrences(of: "BSSID : ", with: "")
                } else if trimmed.starts(with: "Security : ") {
                    security = trimmed.replacingOccurrences(of: "Security : ", with: "")
                } else if trimmed.starts(with: "server_identifier (ip): ") {
                    dhcpServer = trimmed.replacingOccurrences(of: "server_identifier (ip): ", with: "")
                }
            }

            return (ssid, bssid, security, dhcpServer)
        } catch {
            return ("", "", "", nil)
        }
    }

    private func fetchSystemProfilerNetworks() async -> [NearbyAP] {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPAirPortDataType"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }
            return parseSystemProfiler(output: output)
        } catch {
            return []
        }
    }

    public func parseSystemProfiler(output: String) -> [NearbyAP] {
        var networks: [NearbyAP] = []
        let lines = output.components(separatedBy: .newlines)

        var isOtherNetworks = false
        var isCurrentNetwork = false
        var currentSSID = ""
        var currentPHY = ""
        var currentChannel = 0
        var currentBand: WiFiBand = .ghz5
        var currentWidth: WiFiChannelWidth = .mhz80
        var currentSecurity = "WPA2 Personal"
        var currentSignal: Int? = nil
        var currentNoise: Int? = nil
        var isAssoc = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if line.contains("Current Network Information:") {
                isCurrentNetwork = true
                isOtherNetworks = false
                continue
            }

            if line.contains("Other Local Wi-Fi Networks:") {
                // Save current if any
                if isCurrentNetwork && !currentSSID.isEmpty {
                    networks.append(
                        NearbyAP(
                            ssid: currentSSID,
                            bssid: "Associated AP",
                            channel: currentChannel,
                            band: currentBand,
                            channelWidth: currentWidth,
                            rssi: currentSignal,
                            noise: currentNoise,
                            security: currentSecurity,
                            phyMode: currentPHY,
                            isCurrentAssociation: true
                        )
                    )
                    currentSSID = ""
                }
                isOtherNetworks = true
                isCurrentNetwork = false
                continue
            }

            let knownKeys = ["PHY Mode:", "Channel:", "Security:", "Signal / Noise:", "Transmit Rate:", "MCS Index:", "Country Code:", "Network Type:", "Software Versions:", "Interfaces:", "Status:"]
            let isKnownKey = knownKeys.contains { trimmed.starts(with: $0) }

            if (isOtherNetworks || isCurrentNetwork) && trimmed.hasSuffix(":") && !isKnownKey && trimmed != "Current Network Information:" && trimmed != "Other Local Wi-Fi Networks:" {
                // New network block
                if !currentSSID.isEmpty && currentChannel > 0 {
                    networks.append(
                        NearbyAP(
                            ssid: currentSSID,
                            bssid: String(format: "00:AP:%02X:%02X", currentChannel, networks.count + 1),
                            channel: currentChannel,
                            band: currentBand,
                            channelWidth: currentWidth,
                            rssi: currentSignal,
                            noise: currentNoise,
                            security: currentSecurity,
                            phyMode: currentPHY,
                            isCurrentAssociation: isAssoc
                        )
                    )
                }

                currentSSID = String(trimmed.dropLast())
                currentPHY = "802.11ax"
                currentChannel = 0
                currentBand = .ghz5
                currentWidth = .mhz80
                currentSecurity = "WPA2 Personal"
                currentSignal = nil
                currentNoise = nil
                isAssoc = isCurrentNetwork
                continue
            }

            if trimmed.starts(with: "PHY Mode: ") {
                currentPHY = trimmed.replacingOccurrences(of: "PHY Mode: ", with: "")
            } else if trimmed.starts(with: "Channel: ") {
                let chStr = trimmed.replacingOccurrences(of: "Channel: ", with: "")
                // e.g. "161 (5GHz, 80MHz)" or "1 (2GHz, 20MHz)" or "69 (6GHz, 160MHz)"
                let parts = chStr.components(separatedBy: " ")
                if let num = Int(parts[0]) {
                    currentChannel = num
                }
                if chStr.contains("2GHz") {
                    currentBand = .ghz2_4
                } else if chStr.contains("5GHz") {
                    currentBand = .ghz5
                } else if chStr.contains("6GHz") {
                    currentBand = .ghz6
                }

                if chStr.contains("160MHz") {
                    currentWidth = .mhz160
                } else if chStr.contains("80MHz") {
                    currentWidth = .mhz80
                } else if chStr.contains("40MHz") {
                    currentWidth = .mhz40
                } else {
                    currentWidth = .mhz20
                }
            } else if trimmed.starts(with: "Security: ") {
                currentSecurity = trimmed.replacingOccurrences(of: "Security: ", with: "")
            } else if trimmed.starts(with: "Signal / Noise: ") {
                let snStr = trimmed.replacingOccurrences(of: "Signal / Noise: ", with: "")
                let snParts = snStr.components(separatedBy: " / ")
                if snParts.count == 2 {
                    let sigStr = snParts[0].replacingOccurrences(of: " dBm", with: "")
                    let noiseStr = snParts[1].replacingOccurrences(of: " dBm", with: "")
                    currentSignal = Int(sigStr)
                    currentNoise = Int(noiseStr)
                }
            }
        }

        if !currentSSID.isEmpty {
            networks.append(
                NearbyAP(
                    ssid: currentSSID,
                    bssid: String(format: "00:AP:%02X:%02X", currentChannel, networks.count + 1),
                    channel: currentChannel,
                    band: currentBand,
                    channelWidth: currentWidth,
                    rssi: currentSignal,
                    noise: currentNoise,
                    security: currentSecurity,
                    phyMode: currentPHY,
                    isCurrentAssociation: isAssoc
                )
            )
        }

        return networks
    }
}
