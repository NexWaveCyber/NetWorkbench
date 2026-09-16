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

    /// Dissects an IEEE 802.1AB LLDP frame payload (starting after Ethernet header)
    public static func dissect(data: Data, offset: Int = 0) -> (info: LLDPInfo, summary: String, layers: [DissectedLayer]) {
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

        while cursor + 2 <= data.count {
            let tlvHeader = UInt16(data[cursor]) << 8 | UInt16(data[cursor + 1])
            let type = Int((tlvHeader >> 9) & 0x7F)
            let length = Int(tlvHeader & 0x01FF)
            cursor += 2

            guard cursor + length <= data.count else { break }
            let tlvData = data.subdata(in: cursor..<(cursor + length))
            cursor += length

            if type == 0 { // End of LLDPDU
                fields.append(LayerField(name: "End of LLDPDU", value: "Length 0"))
                break
            }

            switch type {
            case 1: // Chassis ID
                let subtype = tlvData.first ?? 0
                let rawId = tlvData.dropFirst()
                chassisID = String(data: rawId, encoding: .utf8) ?? rawId.map { String(format: "%02X", $0) }.joined(separator: ":")
                fields.append(LayerField(name: "Chassis ID (Subtype \(subtype))", value: chassisID))

            case 2: // Port ID
                let subtype = tlvData.first ?? 0
                let rawPort = tlvData.dropFirst()
                portID = String(data: rawPort, encoding: .utf8) ?? rawPort.map { String(format: "%02X", $0) }.joined(separator: ":")
                fields.append(LayerField(name: "Port ID (Subtype \(subtype))", value: portID))

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
                        mgmtAddr = ipBytes.map(String.init).joined(separator: ".")
                        fields.append(LayerField(name: "Management Address", value: mgmtAddr!))
                    }
                }

            case 127: // Org Specific (e.g. 802.1 Port VLAN)
                if length >= 6 {
                    let oui = (UInt32(tlvData[0]) << 16) | (UInt32(tlvData[1]) << 8) | UInt32(tlvData[2])
                    let subtype = tlvData[3]
                    if oui == 0x0080C2 && subtype == 1 { // 802.1 Port VLAN ID
                        vlanID = Int(UInt16(tlvData[4]) << 8 | UInt16(tlvData[5]))
                        fields.append(LayerField(name: "Port VLAN ID", value: "\(vlanID!)"))
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
