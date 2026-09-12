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
    public let newBSSID: String
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
        newBSSID: String,
        previousRSSI: Int,
        newRSSI: Int,
        previousChannel: Int,
        newChannel: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.ssid = ssid
        self.previousBSSID = previousBSSID
        self.newBSSID = newBSSID
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
