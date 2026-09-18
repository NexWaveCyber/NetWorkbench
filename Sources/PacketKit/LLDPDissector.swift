import Foundation

/// Dissected metadata from an IEEE 802.1AB Link Layer Discovery Protocol (LLDP) frame
public struct LLDPInfo: Sendable, Hashable, Identifiable {
    public var id: String { "\(systemName):\(portID)" }
    public let chassisID: String
    public let portID: String
    public let systemName: String
    public let systemDescription: String
    public let portDescription: String
    public let managementAddress: String?
    public let vlanID: Int?
    public let ttlSeconds: Int

    public init(
        chassisID: String = "",
        portID: String = "",
        systemName: String = "",
        systemDescription: String = "",
        portDescription: String = "",
        managementAddress: String? = nil,
        vlanID: Int? = nil,
        ttlSeconds: Int = 120
    ) {
        self.chassisID = chassisID
        self.portID = portID
        self.systemName = systemName
        self.systemDescription = systemDescription
        self.portDescription = portDescription
        self.managementAddress = managementAddress
        self.vlanID = vlanID
        self.ttlSeconds = ttlSeconds
    }
}

public enum LLDPDissector {

    private static func parseID(_ data: Data) -> String {
        let raw = data.dropFirst()
        return String(data: raw, encoding: .utf8) ?? raw.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    /// Dissects an IEEE 802.1AB LLDP frame payload (starting after Ethernet header)
    public static func dissect(data: Data, offset: Int = 0) -> (info: LLDPInfo, summary: String, layers: [DissectedLayer]) {
        let rawData = Data(data)
        var cursor = offset
        var fields: [LayerField] = []

        var chassisID = ""
        var portID = ""
        var systemName = ""
        var systemDesc = ""
        var portDesc = ""
        var mgmtAddr: String? = nil
        var vlanID: Int? = nil
        var ttl = 120

        while cursor + 2 <= rawData.count {
            let tlvHeader = UInt16(rawData[cursor]) << 8 | UInt16(rawData[cursor + 1])
            let type = Int((tlvHeader >> 9) & 0x7F)
            let length = Int(tlvHeader & 0x01FF)
            cursor += 2

            guard cursor + length <= rawData.count else { break }
            let tlvData = rawData.subdata(in: cursor..<(cursor + length))
            cursor += length

            if type == 0 { // End of LLDPDU
                fields.append(LayerField(name: "End of LLDPDU", value: "Length 0"))
                break
            }

            switch type {
            case 1: // Chassis ID
                chassisID = parseID(tlvData)
                fields.append(LayerField(name: "Chassis ID", value: chassisID))

            case 2: // Port ID
                portID = parseID(tlvData)
                fields.append(LayerField(name: "Port ID", value: portID))

            case 3: // TTL
                if length >= 2 {
                    ttl = Int(UInt16(tlvData[0]) << 8 | UInt16(tlvData[1]))
                    fields.append(LayerField(name: "Time To Live", value: "\(ttl) seconds"))
                }

            case 4: // Port Description
                portDesc = String(data: tlvData, encoding: .utf8) ?? ""
                fields.append(LayerField(name: "Port Description", value: portDesc))

            case 5: // System Name
                systemName = String(data: tlvData, encoding: .utf8) ?? ""
                fields.append(LayerField(name: "System Name", value: systemName))

            case 6: // System Description
                systemDesc = String(data: tlvData, encoding: .utf8) ?? ""
                fields.append(LayerField(name: "System Description", value: systemDesc))

            case 8: // Management Address
                if length >= 5 {
                    let addrSubtype = tlvData[1]
                    if addrSubtype == 1 && length >= 6 { // IPv4
                        let ipBytes = tlvData[2...5]
                        let ip = ipBytes.map(String.init).joined(separator: ".")
                        mgmtAddr = ip
                        fields.append(LayerField(name: "Management Address", value: ip))
                    }
                }

            case 127: // Org Specific (e.g. 802.1 Port VLAN)
                if length >= 6 {
                    let oui = (UInt32(tlvData[0]) << 16) | (UInt32(tlvData[1]) << 8) | UInt32(tlvData[2])
                    let subtype = tlvData[3]
                    if oui == 0x0080C2 && subtype == 1 { // 802.1 Port VLAN ID
                        let vlan = Int(UInt16(tlvData[4]) << 8 | UInt16(tlvData[5]))
                        vlanID = vlan
                        fields.append(LayerField(name: "Port VLAN ID", value: "\(vlan)"))
                    }
                }

            default:
                break
            }
        }

        let info = LLDPInfo(
            chassisID: chassisID,
            portID: portID,
            systemName: systemName,
            systemDescription: systemDesc,
            portDescription: portDesc,
            managementAddress: mgmtAddr,
            vlanID: vlanID,
            ttlSeconds: ttl
        )

        var summary = "LLDP: \(systemName.isEmpty ? "Switch" : systemName) [Port: \(portID.isEmpty ? "N/A" : portID)]"
        if let vlan = vlanID {
            summary += " VLAN \(vlan)"
        }

        let layer = DissectedLayer(name: "Link Layer Discovery Protocol", summary: summary, fields: fields)
        return (info, summary, [layer])
    }
}
