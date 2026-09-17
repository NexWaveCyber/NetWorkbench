import Foundation
import CoreWLAN
import DeviceKit

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

        // Enrich with CoreWLAN directly and fallback to ipconfig summary
        let systemSummary = await fetchIPConfigSummary(interface: ifName)
        let wlanSSID = wlan.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ssid = !wlanSSID.isEmpty ? wlanSSID : (!systemSummary.ssid.isEmpty ? systemSummary.ssid : "Wi-Fi Network")
        let wlanBSSID = wlan.bssid()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bssid = !wlanBSSID.isEmpty ? wlanBSSID : (!systemSummary.bssid.isEmpty ? systemSummary.bssid : "00:00:00:00:00:00")
        let security = systemSummary.security.isEmpty ? "WPA2/WPA3 Personal" : systemSummary.security
        let dhcpServer = systemSummary.dhcpServer
        let vendor = OUIResolver.resolve(mac: bssid)

        // Check for roaming event
        let now = Date()
        if let prevBSSID = previousBSSID, !bssid.isEmpty, bssid != "00:00:00:00:00:00", bssid != prevBSSID {
            let prevVendor = OUIResolver.resolve(mac: prevBSSID)
            let event = WiFiRoamingEvent(
                timestamp: now,
                ssid: ssid,
                previousBSSID: prevBSSID,
                previousVendor: prevVendor,
                newBSSID: bssid,
                newVendor: vendor,
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
            vendorName: vendor,
            rssi: rawRSSI,
            noise: rawNoise,
            transmitRate: rawTxRate,
            mcsIndex: extractMCSIndex(txRate: rawTxRate, channelWidth: width, phyMode: phyMode),
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

        // 1. CoreWLAN hardware scan for channels, live RSSI, and real SSIDs
        let client = CWWiFiClient.shared()
        let wlan = interfaceName != nil ? client.interface(withName: interfaceName) : client.interface()
        var scannedChannels: [Int: (rssi: Int, band: WiFiBand, width: WiFiChannelWidth)] = [:]

        if let iface = wlan, let cwNets = try? iface.scanForNetworks(withSSID: nil) {
            for net in cwNets {
                guard let ch = net.wlanChannel else { continue }
                let channelNum = ch.channelNumber
                guard channelNum > 0 else { continue }

                let band: WiFiBand
                switch ch.channelBand {
                case .band2GHz: band = .ghz2_4
                case .band5GHz: band = .ghz5
                case .band6GHz: band = .ghz6
                default: band = channelNum <= 14 ? .ghz2_4 : .ghz5
                }

                let width: WiFiChannelWidth
                switch ch.channelWidth {
                case .width20MHz: width = .mhz20
                case .width40MHz: width = .mhz40
                case .width80MHz: width = .mhz80
                case .width160MHz: width = .mhz160
                default: width = .mhz20
                }

                scannedChannels[channelNum] = (rssi: net.rssiValue, band: band, width: width)

                let rawBSSID = net.bssid ?? ""
                let effectiveBSSID = rawBSSID.isEmpty ? String(format: "02:00:00:00:%02X:%02X", channelNum, abs(net.rssiValue)) : rawBSSID
                let isAssoc = !currentBSSID.isEmpty && (effectiveBSSID.lowercased() == currentBSSID.lowercased())

                let rawSSID = net.ssid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let ssidName: String
                if !rawSSID.isEmpty {
                    ssidName = rawSSID
                } else if isAssoc && iface.ssid() != nil && !iface.ssid()!.isEmpty {
                    ssidName = iface.ssid()!
                } else if rawBSSID.isEmpty {
                    ssidName = "Local AP (Ch \(channelNum))"
                } else {
                    ssidName = "Wi-Fi Network (Ch \(channelNum))"
                }

                let vendor = OUIResolver.resolve(mac: effectiveBSSID)

                let ap = NearbyAP(
                    ssid: ssidName,
                    bssid: effectiveBSSID,
                    vendorName: vendor,
                    channel: channelNum,
                    band: band,
                    channelWidth: width,
                    rssi: net.rssiValue,
                    noise: net.noiseMeasurement,
                    security: "WPA2/WPA3",
                    phyMode: band == .ghz6 ? "802.11ax (6GHz)" : (band == .ghz5 ? "802.11ax" : "802.11n"),
                    isCurrentAssociation: isAssoc
                )
                networks.append(ap)
            }
        }

        // 2. Enrich or fallback to system_profiler
        let profilerNets = await fetchSystemProfilerNetworks()
        if networks.isEmpty {
            for pNet in profilerNets {
                let chInfo = scannedChannels[pNet.channel]
                let effectiveRSSI = pNet.rssi ?? chInfo?.rssi ?? -65
                let effectiveBand = chInfo?.band ?? pNet.band
                let effectiveWidth = chInfo?.width ?? pNet.channelWidth

                let isAssoc = !currentBSSID.isEmpty && (pNet.bssid.lowercased() == currentBSSID.lowercased() || pNet.isCurrentAssociation)
                let effectiveBSSID = isAssoc && !currentBSSID.isEmpty ? currentBSSID : pNet.bssid
                let vendor = OUIResolver.resolve(mac: effectiveBSSID)

                let ap = NearbyAP(
                    ssid: pNet.ssid,
                    bssid: effectiveBSSID,
                    vendorName: vendor,
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
        } else if !profilerNets.isEmpty {
            for i in 0..<networks.count {
                if let match = profilerNets.first(where: { $0.channel == networks[i].channel || $0.bssid.lowercased() == networks[i].bssid.lowercased() }) {
                    if networks[i].ssid.starts(with: "Wi-Fi Network") && !match.ssid.isEmpty {
                        networks[i] = NearbyAP(
                            ssid: match.ssid,
                            bssid: networks[i].bssid,
                            vendorName: networks[i].vendorName,
                            channel: networks[i].channel,
                            band: networks[i].band,
                            channelWidth: networks[i].channelWidth,
                            rssi: networks[i].rssi,
                            noise: networks[i].noise,
                            security: match.security,
                            phyMode: match.phyMode,
                            isCurrentAssociation: networks[i].isCurrentAssociation
                        )
                    }
                }
            }
        }

        // 3. Fallback: If both returned empty, generate synthetic entries from CoreWLAN scanned channels
        if networks.isEmpty && !scannedChannels.isEmpty {
            for (ch, data) in scannedChannels {
                let genBSSID = String(format: "02:00:00:00:%02X:%02X", ch, abs(data.rssi))
                let ap = NearbyAP(
                    ssid: "Local AP (Ch \(ch))",
                    bssid: genBSSID,
                    vendorName: OUIResolver.resolve(mac: genBSSID),
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

    /// Algorithmic RF Channel Recommendation Engine
    public func recommendOptimalChannels(from networks: [NearbyAP], currentChannel: Int = 0) -> [WiFiChannelRecommendation] {
        var recommendations: [WiFiChannelRecommendation] = []

        // 1. 2.4 GHz Optimization (Non-overlapping standard channels: 1, 6, 11)
        let candidates24 = [1, 6, 11]
        var best24Ch = 1
        var best24Score = -1
        var best24Count = 0
        var best24Reason = ""

        let aps24 = networks.filter { $0.band == .ghz2_4 }

        for ch in candidates24 {
            let directCount = aps24.filter { $0.channel == ch }.count
            let adjacentCount = aps24.filter { abs($0.channel - ch) <= 2 && $0.channel != ch }.count

            var penalty = directCount * 25 + adjacentCount * 12
            for ap in aps24 where abs(ap.channel - ch) <= 2 {
                let sig = ap.rssi ?? -85
                if sig > -60 { penalty += 15 }
                else if sig > -75 { penalty += 8 }
            }

            let score = max(10, 100 - penalty)
            if score > best24Score {
                best24Score = score
                best24Ch = ch
                best24Count = directCount
                if directCount == 0 && adjacentCount == 0 {
                    best24Reason = "Cleanest 2.4 GHz channel; zero competing or adjacent BSSIDs."
                } else if directCount == 0 {
                    best24Reason = "No co-channel APs on Ch \(ch); minimal adjacent channel bleed."
                } else {
                    best24Reason = "\(directCount) co-channel AP(s); lowest overall interference floor."
                }
            }
        }

        recommendations.append(
            WiFiChannelRecommendation(
                band: .ghz2_4,
                recommendedChannel: best24Ch,
                channelWidth: "20 MHz",
                contendingAPCount: best24Count,
                cleanlinessScore: best24Score,
                reason: best24Reason
            )
        )

        // 2. 5 GHz Optimization
        // 80 MHz bonded channel candidate primary anchors
        let candidates5 = [
            (anchor: 36, block: [36, 40, 44, 48], isDFS: false, label: "UNII-1"),
            (anchor: 52, block: [52, 56, 60, 64], isDFS: true, label: "UNII-2 DFS"),
            (anchor: 100, block: [100, 104, 108, 112], isDFS: true, label: "UNII-2e DFS"),
            (anchor: 149, block: [149, 153, 157, 161], isDFS: false, label: "UNII-3")
        ]

        let aps5 = networks.filter { $0.band == .ghz5 }
        var best5Ch = 149
        var best5Score = -1
        var best5Count = 0
        var best5Reason = ""

        for block in candidates5 {
            let contending = aps5.filter { block.block.contains($0.channel) }
            var penalty = contending.count * 20
            for ap in contending {
                let sig = ap.rssi ?? -85
                if sig > -60 { penalty += 18 }
                else if sig > -75 { penalty += 10 }
            }

            let score = max(10, 100 - penalty)
            if score > best5Score {
                best5Score = score
                best5Ch = block.anchor
                best5Count = contending.count
                if contending.isEmpty {
                    best5Reason = "Zero co-channel contention on \(block.label) 80 MHz bonded spectrum."
                } else {
                    best5Reason = "\(contending.count) competing AP(s) in \(block.label); optimal SNR margin."
                }
            }
        }

        recommendations.append(
            WiFiChannelRecommendation(
                band: .ghz5,
                recommendedChannel: best5Ch,
                channelWidth: "80 MHz",
                contendingAPCount: best5Count,
                cleanlinessScore: best5Score,
                reason: best5Reason
            )
        )

        // 3. 6 GHz Optimization (Wi-Fi 6E / Wi-Fi 7)
        // Preferred Scanning Channels (PSC)
        let candidate6 = [37, 69, 101, 133]
        let aps6 = networks.filter { $0.band == .ghz6 }
        var best6Ch = 37
        var best6Count = 0
        var best6Score = 100
        var best6Reason = "Uncontested Preferred Scanning Channel (PSC) for 6 GHz Wi-Fi 6E/7."

        for ch in candidate6 {
            let count = aps6.filter { abs($0.channel - ch) <= 8 }.count
            if count == 0 {
                best6Ch = ch
                best6Count = 0
                best6Score = 100
                best6Reason = "Pristine 160 MHz PSC spectrum block with zero competing BSSIDs."
                break
            } else if count < best6Count || best6Score == 100 {
                best6Ch = ch
                best6Count = count
                best6Score = max(20, 100 - count * 20)
                best6Reason = "\(count) active Wi-Fi 6E/7 AP(s) detected."
            }
        }

        recommendations.append(
            WiFiChannelRecommendation(
                band: .ghz6,
                recommendedChannel: best6Ch,
                channelWidth: "160 MHz",
                contendingAPCount: best6Count,
                cleanlinessScore: best6Score,
                reason: best6Reason
            )
        )

        return recommendations
    }

    /// Evaluates co-channel (CCI) and overlapping BSS (OBSS) interference on the active link
    public func evaluateCoChannelContention(currentLink: WiFiCurrentLink, networks: [NearbyAP]) -> WiFiCoChannelWarning {
        let currentSpan = currentLink.frequencySpanMHz

        // 1. Direct Co-Channel Contenders (Exact primary channel)
        let directCompeting = networks.filter { ap in
            ap.channel == currentLink.channel &&
            !ap.isCurrentAssociation &&
            ap.bssid.lowercased() != currentLink.bssid.lowercased()
        }

        // 2. Overlapping BSS (OBSS) Contenders (Different primary channel, but overlapping bonded frequency span)
        var obssOverlaps: [WiFiOBSSOverlap] = []
        for ap in networks where !ap.isCurrentAssociation && ap.bssid.lowercased() != currentLink.bssid.lowercased() {
            if ap.channel != currentLink.channel {
                let apSpan = ap.frequencySpanMHz
                if currentSpan.overlaps(apSpan) {
                    let overlapWidth = max(0.0, min(currentSpan.upperBound, apSpan.upperBound) - max(currentSpan.lowerBound, apSpan.lowerBound))
                    if overlapWidth > 0 {
                        obssOverlaps.append(
                            WiFiOBSSOverlap(
                                ssid: ap.ssid,
                                bssid: ap.bssid,
                                vendor: ap.vendorName,
                                primaryChannel: ap.channel,
                                channelWidth: ap.channelWidth,
                                overlappingBandwidthMHz: overlapWidth,
                                rssi: ap.rssi
                            )
                        )
                    }
                }
            }
        }

        let directCount = directCompeting.count
        let obssCount = obssOverlaps.count
        let totalContenders = directCount + obssCount

        let severity: WiFiContentionSeverity
        if directCount == 0 && obssCount == 0 {
            severity = .clean
        } else if directCount <= 1 && obssCount <= 1 {
            severity = .low
        } else if directCount <= 3 && totalContenders <= 5 {
            severity = .moderate
        } else {
            severity = .severe
        }

        var advisory = ""
        if severity == .clean {
            advisory = "Zero co-channel contention detected on Channel \(currentLink.channel). Client has uncontested airtime."
        } else if directCount == 1 && obssCount == 0 {
            let ap = directCompeting[0]
            let sig = ap.rssi != nil ? "(\(ap.rssi!) dBm)" : ""
            advisory = "1 competing AP '\(ap.ssid)' \(sig) sharing Channel \(currentLink.channel). Negligible impact on line-rate throughput."
        } else if directCount == 0 && obssCount > 0 {
            advisory = "\(obssCount) bonded overlapping BSS (OBSS) AP(s) detected sharing spectrum with Ch \(currentLink.channel) (\(currentLink.channelWidth.rawValue)). Occasional Clear Channel Assessment (CCA) deferrals may occur."
        } else if severity == .moderate {
            advisory = "\(directCount) direct co-channel and \(obssCount) bonded OBSS AP(s) contending on Ch \(currentLink.channel). Clear Channel Assessment (CCA) deferrals may induce minor jitter."
        } else {
            advisory = "Heavy spectrum contention (\(directCount) direct co-channel, \(obssCount) bonded OBSS) on Channel \(currentLink.channel). Significant airtime contention and throughput backoff are likely."
        }

        return WiFiCoChannelWarning(
            channel: currentLink.channel,
            band: currentLink.band,
            contendingAPCount: directCount,
            obssOverlappingAPCount: obssCount,
            obssOverlaps: obssOverlaps,
            severity: severity,
            advisory: advisory
        )
    }

    /// Evaluates whether the client is experiencing a sticky client anomaly (clinging to weak AP when a stronger BSSID exists)
    public func evaluateStickyClientAnomaly(currentLink: WiFiCurrentLink, networks: [NearbyAP]) -> WiFiStickyClientAnomaly? {
        guard !currentLink.ssid.isEmpty, currentLink.ssid != "Wi-Fi Network" else { return nil }

        // Find candidate APs with the exact same SSID, different BSSID, and valid RSSI
        let candidates = networks.filter { ap in
            ap.ssid.lowercased() == currentLink.ssid.lowercased() &&
            ap.bssid.lowercased() != currentLink.bssid.lowercased() &&
            (ap.rssi ?? -100) > currentLink.rssi + 12 // At least 12 dB stronger
        }

        guard let bestCandidate = candidates.max(by: { ($0.rssi ?? -100) < ($1.rssi ?? -100) }) else {
            return nil
        }

        // Only trigger if active link is sub-optimal (e.g. RSSI < -68 dBm)
        if currentLink.rssi < -68 {
            return WiFiStickyClientAnomaly(
                currentBSSID: currentLink.bssid,
                currentRSSI: currentLink.rssi,
                candidateBSSID: bestCandidate.bssid,
                candidateVendor: bestCandidate.vendorName,
                candidateRSSI: bestCandidate.rssi ?? -50,
                candidateChannel: bestCandidate.channel,
                candidateBand: bestCandidate.band,
                recommendation: "Mac is attached to edge BSSID (\(currentLink.rssi) dBm) despite stronger candidate \(bestCandidate.bssid) on Ch \(bestCandidate.channel) (\(bestCandidate.rssi ?? 0) dBm, +\( (bestCandidate.rssi ?? 0) - currentLink.rssi ) dB gain). Consider triggering 802.11k/v/r roaming by toggling Wi-Fi or moving."
            )
        }

        return nil
    }

    /// Generates a comprehensive RF Site Survey Report
    public func generateSurveyReport(
        currentLink: WiFiCurrentLink?,
        networks: [NearbyAP]
    ) -> WiFiRFSurveyReport {
        let currentCh = currentLink?.channel ?? 0
        let recs = recommendOptimalChannels(from: networks, currentChannel: currentCh)
        let warning = currentLink != nil ? evaluateCoChannelContention(currentLink: currentLink!, networks: networks) : nil
        let anomaly = currentLink != nil ? evaluateStickyClientAnomaly(currentLink: currentLink!, networks: networks) : nil
        let cong = calculateChannelCongestion(from: networks, currentChannel: currentCh)

        return WiFiRFSurveyReport(
            currentLink: currentLink,
            recommendations: recs,
            coChannelWarning: warning,
            stickyClientAnomaly: anomaly,
            congestion: cong,
            nearbyAPs: networks,
            roamingEvents: roamingHistory
        )
    }

    // MARK: - Private Telemetry Helpers

    public func extractMCSIndex(txRate: Double, channelWidth: WiFiChannelWidth = .mhz80, phyMode: WiFiPHYMode = .ax) -> Int? {
        guard txRate > 0 else { return nil }

        switch channelWidth {
        case .mhz160, .mhz320:
            if txRate >= 2160 { return 11 }
            if txRate >= 1920 { return 10 }
            if txRate >= 1720 { return 9 }
            if txRate >= 1530 { return 8 }
            if txRate >= 1290 { return 7 }
            if txRate >= 1150 { return 6 }
            if txRate >= 960  { return 5 }
            if txRate >= 770  { return 4 }
            if txRate >= 570  { return 3 }
            if txRate >= 380  { return 2 }
            if txRate >= 280  { return 1 }
            return 0
        case .mhz80:
            if txRate >= 1140 { return 11 }
            if txRate >= 1020 { return 10 }
            if txRate >= 910  { return 9 }
            if txRate >= 810  { return 8 }
            if txRate >= 680  { return 7 }
            if txRate >= 600  { return 6 }
            if txRate >= 500  { return 5 }
            if txRate >= 400  { return 4 }
            if txRate >= 270  { return 3 }
            if txRate >= 200  { return 2 }
            if txRate >= 130  { return 1 }
            return 0
        case .mhz40:
            if txRate >= 540 { return 11 }
            if txRate >= 480 { return 10 }
            if txRate >= 430 { return 9 }
            if txRate >= 380 { return 8 }
            if txRate >= 320 { return 7 }
            if txRate >= 280 { return 6 }
            if txRate >= 240 { return 5 }
            if txRate >= 190 { return 4 }
            if txRate >= 130 { return 3 }
            if txRate >= 90  { return 2 }
            if txRate >= 60  { return 1 }
            return 0
        case .mhz20, .unknown:
            if txRate >= 270 { return 11 }
            if txRate >= 240 { return 10 }
            if txRate >= 210 { return 9 }
            if txRate >= 190 { return 8 }
            if txRate >= 160 { return 7 }
            if txRate >= 140 { return 6 }
            if txRate >= 120 { return 5 }
            if txRate >= 90  { return 4 }
            if txRate >= 65  { return 3 }
            if txRate >= 45  { return 2 }
            if txRate >= 30  { return 1 }
            return 0
        }
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
                    let bssid = previousBSSID ?? "Associated AP"
                    networks.append(
                        NearbyAP(
                            ssid: currentSSID,
                            bssid: bssid,
                            vendorName: OUIResolver.resolve(mac: bssid),
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
                    let bssid = String(format: "00:AP:%02X:%02X", currentChannel, networks.count + 1)
                    networks.append(
                        NearbyAP(
                            ssid: currentSSID,
                            bssid: bssid,
                            vendorName: OUIResolver.resolve(mac: bssid),
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
            let bssid = isAssoc ? (previousBSSID ?? "Associated AP") : String(format: "00:AP:%02X:%02X", currentChannel, networks.count + 1)
            networks.append(
                NearbyAP(
                    ssid: currentSSID,
                    bssid: bssid,
                    vendorName: OUIResolver.resolve(mac: bssid),
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
