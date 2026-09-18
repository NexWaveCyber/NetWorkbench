import Foundation

/// Dissected metadata from a Cisco Discovery Protocol (CDP) frame
public struct CDPInfo: Sendable, Hashable, Identifiable {
    public var id: String { "\(deviceID):\(portID)" }
    public let deviceID: String
    public let portID: String
    public let platform: String
    public let softwareVersion: String
    public let managementAddress: String?
    public let nativeVLAN: Int?
    public let duplex: String
    public let ttlSeconds: Int

    public init(
        deviceID: String = "",
        portID: String = "",
        platform: String = "",
        softwareVersion: String = "",
        managementAddress: String? = nil,
        nativeVLAN: Int? = nil,
        duplex: String = "Full",
        ttlSeconds: Int = 180
    ) {
        self.deviceID = deviceID
        self.portID = portID
        self.platform = platform
        self.softwareVersion = softwareVersion
        self.managementAddress = managementAddress
        self.nativeVLAN = nativeVLAN
        self.duplex = duplex
        self.ttlSeconds = ttlSeconds
    }
}

public enum CDPDissector {

    /// Dissects a Cisco Discovery Protocol frame payload (starting at CDP Version header)
    public static func dissect(data: Data, offset: Int = 0) -> (info: CDPInfo, summary: String, layers: [DissectedLayer]) {
        let rawData = Data(data)
        var cursor = offset
        var fields: [LayerField] = []

        guard cursor + 4 <= rawData.count else {
            let layer = DissectedLayer(name: "Cisco Discovery Protocol", summary: "Malformed / truncated CDP header", fields: [])
            return (CDPInfo(), "Malformed CDP Frame", [layer])
        }

        let version = rawData[cursor]
        let ttl = Int(rawData[cursor + 1])
        let checksum = UInt16(rawData[cursor + 2]) << 8 | UInt16(rawData[cursor + 3])
        cursor += 4

        fields.append(LayerField(name: "CDP Version", value: "\(version)"))
        fields.append(LayerField(name: "Time To Live", value: "\(ttl) seconds"))
        fields.append(LayerField(name: "Checksum", value: String(format: "0x%04X", checksum)))

        var deviceID = ""
        var portID = ""
        var platform = ""
        var softwareVersion = ""
        var mgmtAddress: String? = nil
        var nativeVLAN: Int? = nil
        var duplex = "Full"

        while cursor + 4 <= rawData.count {
            let type = UInt16(rawData[cursor]) << 8 | UInt16(rawData[cursor + 1])
            let length = Int(UInt16(rawData[cursor + 2]) << 8 | UInt16(rawData[cursor + 3]))
            cursor += 4

            let valueLength = length - 4
            guard valueLength >= 0, cursor + valueLength <= rawData.count else { break }
            let valData = rawData.subdata(in: cursor..<(cursor + valueLength))
            cursor += valueLength

            switch type {
            case 0x0001: // Device ID
                deviceID = String(data: valData, encoding: .utf8) ?? ""
                fields.append(LayerField(name: "Device ID", value: deviceID))

            case 0x0002: // Address
                if valData.count >= 9 {
                    // Skip num addresses (4 bytes), proto type (1), proto length (1), proto (1)
                    // IPv4 is 4 bytes at end of standard address block
                    let ipSlice = valData.suffix(4)
                    if ipSlice.count == 4 {
                        let ip = ipSlice.map(String.init).joined(separator: ".")
                        mgmtAddress = ip
                        fields.append(LayerField(name: "IPv4 Address", value: ip))
                    }
                }

            case 0x0003: // Port ID
                portID = String(data: valData, encoding: .utf8) ?? ""
                fields.append(LayerField(name: "Port ID", value: portID))

            case 0x0005: // Software Version
                softwareVersion = String(data: valData, encoding: .utf8) ?? ""
                let firstLine = softwareVersion.components(separatedBy: "\n").first ?? softwareVersion
                fields.append(LayerField(name: "Software Version", value: firstLine))

            case 0x0006: // Platform
                platform = String(data: valData, encoding: .utf8) ?? ""
                fields.append(LayerField(name: "Platform", value: platform))

            case 0x000A: // Native VLAN
                if valData.count >= 2 {
                    let vlan = Int(UInt16(valData[0]) << 8 | UInt16(valData[1]))
                    nativeVLAN = vlan
                    fields.append(LayerField(name: "Native VLAN", value: "\(vlan)"))
                }

            case 0x000B: // Duplex
                if let b = valData.first {
                    duplex = (b == 1) ? "Full" : "Half"
                    fields.append(LayerField(name: "Duplex", value: duplex))
                }

            default:
                break
            }
        }

        let info = CDPInfo(
            deviceID: deviceID,
            portID: portID,
            platform: platform,
            softwareVersion: softwareVersion,
            managementAddress: mgmtAddress,
            nativeVLAN: nativeVLAN,
            duplex: duplex,
            ttlSeconds: ttl
        )

        var summary = "CDP: \(deviceID.isEmpty ? "Cisco Device" : deviceID) [Port: \(portID.isEmpty ? "N/A" : portID)]"
        if !platform.isEmpty {
            summary += " (\(platform))"
        }
        if let vlan = nativeVLAN {
            summary += " VLAN \(vlan)"
        }

        let layer = DissectedLayer(name: "Cisco Discovery Protocol", summary: summary, fields: fields)
        return (info, summary, [layer])
    }
}
