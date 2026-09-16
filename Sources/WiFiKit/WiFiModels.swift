import Foundation

public enum WiFiBand: String, Sendable, Codable, CaseIterable {
    case ghz2_4 = "2.4 GHz"
    case ghz5 = "5 GHz"
    case ghz6 = "6 GHz (Wi-Fi 6E/7)"
    case unknown = "Unknown"

    public var badgeColor: String {
        switch self {
        case .ghz2_4: return "#F59E0B" // Amber
        case .ghz5:   return "#3B82F6" // Blue
        case .ghz6:   return "#8B5CF6" // Purple
        case .unknown: return "#6B7280" // Gray
        }
    }
}

public enum WiFiChannelWidth: String, Sendable, Codable {
    case mhz20 = "20 MHz"
    case mhz40 = "40 MHz"
    case mhz80 = "80 MHz"
    case mhz160 = "160 MHz"
    case mhz320 = "320 MHz"
    case unknown = "Unknown"
}

public enum WiFiPHYMode: String, Sendable, Codable {
    case b = "802.11b"
    case g = "802.11g"
    case a = "802.11a"
    case n = "802.11n (Wi-Fi 4)"
    case ac = "802.11ac (Wi-Fi 5)"
    case ax = "802.11ax (Wi-Fi 6)"
    case be = "802.11be (Wi-Fi 7)"
    case unknown = "Unknown PHY"

    public var displayName: String {
        return rawValue
    }
}

public enum WiFiSignalQuality: String, Sendable, Codable {
    case pristine = "Pristine"
    case good = "Good"
    case fair = "Fair"
    case degraded = "Degraded"
    case critical = "Critical"

    public static func evaluate(rssi: Int, noise: Int) -> WiFiSignalQuality {
        let snr = rssi - noise
        if snr >= 40 || rssi >= -50 {
            return .pristine
        } else if snr >= 25 || rssi >= -65 {
            return .good
        } else if snr >= 15 || rssi >= -75 {
            return .fair
        } else if snr >= 10 || rssi >= -82 {
            return .degraded
        } else {
            return .critical
        }
    }

    public var scorePercentage: Int {
        switch self {
        case .pristine: return 100
        case .good:     return 80
        case .fair:     return 60
        case .degraded: return 40
        case .critical: return 15
        }
    }

    public var colorHex: String {
        switch self {
        case .pristine: return "#10B981" // Emerald
        case .good:     return "#34D399" // Light Emerald
        case .fair:     return "#FBBF24" // Amber
        case .degraded: return "#F97316" // Orange
        case .critical: return "#EF4444" // Crimson
        }
    }

    public var advice: String {
        switch self {
        case .pristine:
            return "RF environment is optimal for line-rate throughput and ultra-low jitter."
        case .good:
            return "Solid RF link. Ideal for enterprise conferencing and high-speed data transfer."
        case .fair:
            return "Moderate link margin. Occasional MCS downshifting may occur during high traffic."
        case .degraded:
            return "High packet loss risk. Client is near cell edge; consider moving closer to the AP."
        case .critical:
            return "Severe attenuation or high noise floor. Link disconnects are imminent."
        }
    }
}

public struct WiFiCurrentLink: Sendable, Codable, Equatable {
    public let interfaceName: String
    public let macAddress: String
    public let ssid: String
    public let bssid: String
    public let vendorName: String?
    public let rssi: Int
    public let noise: Int
    public let snr: Int
    public let transmitRate: Double
    public let mcsIndex: Int?
    public let channel: Int
    public let band: WiFiBand
    public let channelWidth: WiFiChannelWidth
    public let phyMode: WiFiPHYMode
    public let security: String
    public let countryCode: String
    public let signalQuality: WiFiSignalQuality
    public let dhcpServer: String?
    public let timestamp: Date

    public init(
        interfaceName: String,
        macAddress: String,
        ssid: String,
        bssid: String,
        vendorName: String? = nil,
        rssi: Int,
        noise: Int,
        transmitRate: Double,
        mcsIndex: Int? = nil,
        channel: Int,
        band: WiFiBand,
        channelWidth: WiFiChannelWidth,
        phyMode: WiFiPHYMode,
        security: String,
        countryCode: String,
        dhcpServer: String? = nil,
        timestamp: Date = Date()
    ) {
        self.interfaceName = interfaceName
        self.macAddress = macAddress
        self.ssid = ssid
        self.bssid = bssid
        self.vendorName = vendorName
        self.rssi = rssi
        self.noise = noise
        self.snr = rssi - noise
        self.transmitRate = transmitRate
        self.mcsIndex = mcsIndex
        self.channel = channel
        self.band = band
        self.channelWidth = channelWidth
        self.phyMode = phyMode
        self.security = security
        self.countryCode = countryCode
        self.signalQuality = WiFiSignalQuality.evaluate(rssi: rssi, noise: noise)
        self.dhcpServer = dhcpServer
        self.timestamp = timestamp
    }
}

public struct NearbyAP: Identifiable, Sendable, Codable, Equatable {
    public var id: String { "\(bssid)_\(channel)" }
    public let ssid: String
    public let bssid: String
    public let vendorName: String?
    public let channel: Int
    public let band: WiFiBand
    public let channelWidth: WiFiChannelWidth
    public let rssi: Int?
    public let noise: Int?
    public let security: String
    public let phyMode: String
    public let isCurrentAssociation: Bool

    public init(
        ssid: String,
        bssid: String,
        vendorName: String? = nil,
        channel: Int,
        band: WiFiBand,
        channelWidth: WiFiChannelWidth,
        rssi: Int?,
        noise: Int?,
        security: String,
        phyMode: String,
        isCurrentAssociation: Bool
    ) {
        self.ssid = ssid
        self.bssid = bssid
        self.vendorName = vendorName
        self.channel = channel
        self.band = band
        self.channelWidth = channelWidth
        self.rssi = rssi
        self.noise = noise
        self.security = security
        self.phyMode = phyMode
        self.isCurrentAssociation = isCurrentAssociation
    }
}

public struct WiFiRoamingEvent: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let ssid: String
    public let previousBSSID: String
    public let previousVendor: String?
    public let newBSSID: String
    public let newVendor: String?
    public let previousRSSI: Int
    public let newRSSI: Int
    public let rssiDelta: Int
    public let previousChannel: Int
    public let newChannel: Int

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        ssid: String,
        previousBSSID: String,
        previousVendor: String? = nil,
        newBSSID: String,
        newVendor: String? = nil,
        previousRSSI: Int,
        newRSSI: Int,
        previousChannel: Int,
        newChannel: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.ssid = ssid
        self.previousBSSID = previousBSSID
        self.previousVendor = previousVendor
        self.newBSSID = newBSSID
        self.newVendor = newVendor
        self.previousRSSI = previousRSSI
        self.newRSSI = newRSSI
        self.rssiDelta = newRSSI - previousRSSI
        self.previousChannel = previousChannel
        self.newChannel = newChannel
    }
}

public struct ChannelCongestion: Identifiable, Sendable, Codable {
    public var id: String { "\(band.rawValue)_\(channel)" }
    public let band: WiFiBand
    public let channel: Int
    public let apCount: Int
    public let isCurrentChannel: Bool

    public init(band: WiFiBand, channel: Int, apCount: Int, isCurrentChannel: Bool) {
        self.band = band
        self.channel = channel
        self.apCount = apCount
        self.isCurrentChannel = isCurrentChannel
    }
}

public struct WiFiChannelRecommendation: Identifiable, Sendable, Codable, Equatable {
    public var id: String { "\(band.rawValue)_\(recommendedChannel)" }
    public let band: WiFiBand
    public let recommendedChannel: Int
    public let channelWidth: String
    public let contendingAPCount: Int
    public let cleanlinessScore: Int // 0 to 100
    public let reason: String

    public init(
        band: WiFiBand,
        recommendedChannel: Int,
        channelWidth: String,
        contendingAPCount: Int,
        cleanlinessScore: Int,
        reason: String
    ) {
        self.band = band
        self.recommendedChannel = recommendedChannel
        self.channelWidth = channelWidth
        self.contendingAPCount = contendingAPCount
        self.cleanlinessScore = cleanlinessScore
        self.reason = reason
    }
}

public enum WiFiContentionSeverity: String, Sendable, Codable {
    case clean = "Clean"
    case low = "Low Contention"
    case moderate = "Moderate Contention"
    case severe = "Severe Contention"

    public var badgeColor: String {
        switch self {
        case .clean: return "#10B981"
        case .low: return "#3B82F6"
        case .moderate: return "#F59E0B"
        case .severe: return "#EF4444"
        }
    }
}

public struct WiFiCoChannelWarning: Sendable, Codable, Equatable {
    public let channel: Int
    public let band: WiFiBand
    public let contendingAPCount: Int
    public let severity: WiFiContentionSeverity
    public let advisory: String

    public init(
        channel: Int,
        band: WiFiBand,
        contendingAPCount: Int,
        severity: WiFiContentionSeverity,
        advisory: String
    ) {
        self.channel = channel
        self.band = band
        self.contendingAPCount = contendingAPCount
        self.severity = severity
        self.advisory = advisory
    }
}

public struct WiFiRFSurveyReport: Sendable, Codable {
    public let generatedAt: Date
    public let currentLink: WiFiCurrentLink?
    public let recommendations: [WiFiChannelRecommendation]
    public let coChannelWarning: WiFiCoChannelWarning?
    public let congestion: [ChannelCongestion]
    public let nearbyAPs: [NearbyAP]
    public let roamingEvents: [WiFiRoamingEvent]

    public init(
        generatedAt: Date = Date(),
        currentLink: WiFiCurrentLink?,
        recommendations: [WiFiChannelRecommendation],
        coChannelWarning: WiFiCoChannelWarning?,
        congestion: [ChannelCongestion],
        nearbyAPs: [NearbyAP],
        roamingEvents: [WiFiRoamingEvent]
    ) {
        self.generatedAt = generatedAt
        self.currentLink = currentLink
        self.recommendations = recommendations
        self.coChannelWarning = coChannelWarning
        self.congestion = congestion
        self.nearbyAPs = nearbyAPs
        self.roamingEvents = roamingEvents
    }

    public func toMarkdown() -> String {
        var md = "# NexWave Wi-Fi Studio RF Survey Report\n\n"
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withSpaceBetweenDateAndTime]
        md += "**Generated:** \(df.string(from: generatedAt))\n\n"

        if let link = currentLink {
            md += "## Active Association & RF Telemetry\n\n"
            md += "| Metric | Value |\n| :--- | :--- |\n"
            md += "| **SSID** | `\(link.ssid)` |\n"
            md += "| **BSSID** | `\(link.bssid)` (\(link.vendorName ?? "Unknown Vendor")) |\n"
            md += "| **Signal (RSSI)** | `\(link.rssi) dBm` |\n"
            md += "| **Noise Floor** | `\(link.noise) dBm` |\n"
            md += "| **SNR Margin** | `\(link.snr) dB` (\(link.signalQuality.rawValue)) |\n"
            md += "| **Operating Channel** | Ch \(link.channel) (\(link.band.rawValue), \(link.channelWidth.rawValue)) |\n"
            md += "| **PHY Mode** | \(link.phyMode.displayName) |\n"
            md += "| **TX Rate** | \(link.transmitRate > 0 ? "\(Int(link.transmitRate)) Mbps" : "Auto") \(link.mcsIndex != nil ? "(MCS \(link.mcsIndex!))" : "") |\n"
            md += "| **Client MAC** | `\(link.macAddress)` |\n"
            if let dhcp = link.dhcpServer {
                md += "| **DHCP Gateway** | `\(dhcp)` |\n"
            }
            md += "| **Security** | \(link.security) |\n\n"
        }

        if let warning = coChannelWarning {
            md += "## Co-Channel Contention Assessment\n\n"
            md += "> [!NOTE]\n"
            md += "> **Status:** \(warning.severity.rawValue) on Channel \(warning.channel) (\(warning.band.rawValue))\n"
            md += "> **Contending BSSIDs:** \(warning.contendingAPCount) APs detected\n"
            md += "> **Advisory:** \(warning.advisory)\n\n"
        }

        if !recommendations.isEmpty {
            md += "## Algorithmic Channel Recommendations\n\n"
            md += "| Band | Recommended Channel | Cleanliness Score | Contending APs | Optimization Reason |\n"
            md += "| :--- | :--- | :---: | :---: | :--- |\n"
            for rec in recommendations {
                md += "| \(rec.band.rawValue) | **Channel \(rec.recommendedChannel)** (\(rec.channelWidth)) | \(rec.cleanlinessScore)/100 | \(rec.contendingAPCount) | \(rec.reason) |\n"
            }
            md += "\n"
        }

        if !nearbyAPs.isEmpty {
            md += "## Visible Surrounding Access Points (\(nearbyAPs.count))\n\n"
            md += "| SSID | BSSID | Vendor | Ch / Band | Signal | Width | Security | PHY |\n"
            md += "| :--- | :--- | :--- | :--- | :---: | :--- | :--- | :--- |\n"
            for ap in nearbyAPs {
                let vendor = ap.vendorName ?? "Unknown"
                let sig = ap.rssi != nil ? "\(ap.rssi!) dBm" : "N/A"
                md += "| `\(ap.ssid)` | `\(ap.bssid)` | \(vendor) | Ch \(ap.channel) (\(ap.band.rawValue)) | \(sig) | \(ap.channelWidth.rawValue) | \(ap.security) | \(ap.phyMode) |\n"
            }
            md += "\n"
        }

        if !roamingEvents.isEmpty {
            md += "## AP Roaming Audit Log\n\n"
            md += "| Timestamp | SSID | Previous BSSID (Vendor) | New BSSID (Vendor) | Channel Shift | RSSI Delta |\n"
            md += "| :--- | :--- | :--- | :--- | :--- | :---: |\n"
            for ev in roamingEvents {
                let prevV = ev.previousVendor ?? "Unknown"
                let newV = ev.newVendor ?? "Unknown"
                let deltaStr = ev.rssiDelta >= 0 ? "+\(ev.rssiDelta) dBm" : "\(ev.rssiDelta) dBm"
                md += "| \(df.string(from: ev.timestamp)) | `\(ev.ssid)` | `\(ev.previousBSSID)` (\(prevV)) | `\(ev.newBSSID)` (\(newV)) | Ch \(ev.previousChannel) ➔ \(ev.newChannel) | \(deltaStr) |\n"
            }
            md += "\n"
        }

        return md
    }

    public func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(self), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}
