import Foundation
import NetworkCore
import DeviceKit

// MARK: - Show IP Interface Brief Parser

public struct ShowIPInterfaceBriefParser: VendorOutputParser {
    public let vendor: Vendor = .cisco
    public let operatingSystem: OperatingSystem = .iosXE
    public let commandFamily: CommandFamily = .showIPInterfaceBrief
    public let parserVersion: String = "1.0.0"

    public init() {}

    public func canParse(rawOutput: String) -> Double {
        let lower = rawOutput.lowercased()
        if lower.contains("interface") && lower.contains("ip-address") && (lower.contains("ok?") || lower.contains("status")) {
            return 0.98
        }
        if lower.contains("show ip int") || lower.contains("show ip interface brief") {
            return 0.95
        }
        return 0.0
    }

    public func parse(rawOutput: String) throws -> StructuredResult {
        let lines = rawOutput.components(separatedBy: .newlines)
        var entries: [IPInterfaceEntry] = []

        var headerFound = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let lower = trimmed.lowercased()
            if lower.contains("interface") && lower.contains("ip-address") {
                headerFound = true
                continue
            }

            if !headerFound { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 6 else { continue }

            let intf = parts[0]
            let ip = parts[1]
            let ok = parts[2].uppercased() == "YES"
            let method = parts[3]

            // Status and Protocol might be "administratively down" which is 2 tokens
            var status: String
            var proto: String

            if parts.count >= 7 && parts[4].lowercased() == "administratively" && parts[5].lowercased() == "down" {
                status = "administratively down"
                proto = parts[6]
            } else {
                status = parts[4]
                proto = parts[5]
            }

            entries.append(IPInterfaceEntry(
                interface: intf,
                ipAddress: ip,
                isOK: ok,
                method: method,
                status: status,
                lineProtocol: proto
            ))
        }

        return .ipInterfaceBrief(entries)
    }
}

// MARK: - Show Interfaces Parser

public struct ShowInterfacesParser: VendorOutputParser {
    public let vendor: Vendor = .cisco
    public let operatingSystem: OperatingSystem = .iosXE
    public let commandFamily: CommandFamily = .showInterfaces
    public let parserVersion: String = "1.0.0"

    public init() {}

    public func canParse(rawOutput: String) -> Double {
        let lower = rawOutput.lowercased()
        if (lower.contains("is up, line protocol is") || lower.contains("is administratively down")) &&
           (lower.contains("hardware is") || lower.contains("packets input") || lower.contains("crc")) {
            return 0.96
        }
        return 0.0
    }

    public func parse(rawOutput: String) throws -> StructuredResult {
        let lines = rawOutput.components(separatedBy: .newlines)
        var entries: [InterfaceDetailEntry] = []

        var currentName: String?
        var currentAdminState = "unknown"
        var currentLineState = "unknown"
        var currentHardware: String?
        var currentMac: String?
        var currentIP: String?
        var currentMtu: Int?
        var currentBw: String?
        var currentDuplex: String?
        var currentSpeed: String?
        var currentInPkts: UInt64 = 0
        var currentOutPkts: UInt64 = 0
        var currentCrc: UInt64 = 0
        var currentDiscards: UInt64 = 0
        var currentAnomalies: [String] = []

        func flushEntry() {
            guard let name = currentName else { return }
            entries.append(InterfaceDetailEntry(
                name: name,
                adminState: currentAdminState,
                lineState: currentLineState,
                hardwareType: currentHardware,
                macAddress: currentMac,
                ipAddress: currentIP,
                mtu: currentMtu,
                bandwidth: currentBw,
                duplex: currentDuplex,
                speed: currentSpeed,
                inputPackets: currentInPkts,
                outputPackets: currentOutPkts,
                crcErrors: currentCrc,
                inputDiscards: currentDiscards,
                anomalies: currentAnomalies
            ))
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            if (lower.contains("is up") || lower.contains("is down") || lower.contains("is administratively down")) && lower.contains("line protocol is") {
                flushEntry()
                currentName = nil
                currentAdminState = "unknown"
                currentLineState = "unknown"
                currentHardware = nil
                currentMac = nil
                currentIP = nil
                currentMtu = nil
                currentBw = nil
                currentDuplex = nil
                currentSpeed = nil
                currentInPkts = 0
                currentOutPkts = 0
                currentCrc = 0
                currentDiscards = 0
                currentAnomalies = []

                let parts = trimmed.components(separatedBy: " is ")
                if parts.count >= 2 {
                    currentName = parts[0]
                    let rest = parts[1]
                    if rest.contains(",") {
                        let sub = rest.components(separatedBy: ",")
                        currentAdminState = sub[0].trimmingCharacters(in: .whitespaces)
                        if sub.count >= 2 && sub[1].contains("line protocol is ") {
                            currentLineState = sub[1].replacingOccurrences(of: "line protocol is ", with: "").trimmingCharacters(in: .whitespaces)
                        }
                    }
                }
            }

            if let r = trimmed.range(of: "hardware is ", options: .caseInsensitive) {
                let sub = String(trimmed[r.upperBound...]).components(separatedBy: ",")
                currentHardware = sub[0].trimmingCharacters(in: .whitespaces)
            }
            if let r = trimmed.range(of: "address is ", options: .caseInsensitive) {
                let rest = String(trimmed[r.upperBound...])
                let m = rest.components(separatedBy: " ")[0]
                currentMac = m.trimmingCharacters(in: .punctuationCharacters)
            }
            if let r = trimmed.range(of: "internet address is ", options: .caseInsensitive) {
                currentIP = String(trimmed[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }

            if lower.contains("mtu ") {
                let words = trimmed.components(separatedBy: .whitespaces)
                if let idx = words.firstIndex(where: { $0.lowercased() == "mtu" }), idx + 1 < words.count {
                    currentMtu = Int(words[idx + 1])
                }
                if let idx = words.firstIndex(where: { $0.lowercased() == "bw" }), idx + 1 < words.count {
                    currentBw = words[idx + 1] + " " + (idx + 2 < words.count ? words[idx + 2] : "")
                }
            }

            if lower.contains("-duplex") {
                if lower.contains("half-duplex") {
                    currentDuplex = "Half"
                    currentAnomalies.append("Half-Duplex Link Degradation")
                } else if lower.contains("full-duplex") {
                    currentDuplex = "Full"
                }
                if lower.contains("1000mb/s") || lower.contains("1gb/s") {
                    currentSpeed = "1 Gbps"
                } else if lower.contains("100mb/s") {
                    currentSpeed = "100 Mbps"
                } else if lower.contains("10gb/s") {
                    currentSpeed = "10 Gbps"
                }
            }

            if lower.contains("packets input") {
                let words = trimmed.components(separatedBy: .whitespaces)
                if let pkts = UInt64(words[0]) {
                    currentInPkts = pkts
                }
            }

            if lower.contains("packets output") {
                let words = trimmed.components(separatedBy: .whitespaces)
                if let pkts = UInt64(words[0]) {
                    currentOutPkts = pkts
                }
            }

            if lower.contains("crc") {
                let words = trimmed.components(separatedBy: .whitespaces)
                if let idx = words.firstIndex(where: { $0.lowercased().contains("crc") }), idx > 0 {
                    let cleanWord = words[idx - 1].trimmingCharacters(in: .punctuationCharacters)
                    if let crc = UInt64(cleanWord), crc > 0 {
                        currentCrc = crc
                        currentAnomalies.append("Non-zero CRC Errors (\(crc))")
                    }
                }
            }

            if lower.contains("input errors") && lower.contains("ignored") {
                // discards
            }
        }

        flushEntry()
        return .interfaceDetails(entries)
    }
}

// MARK: - Show IP Route Parser

public struct ShowIPRouteParser: VendorOutputParser {
    public let vendor: Vendor = .cisco
    public let operatingSystem: OperatingSystem = .iosXE
    public let commandFamily: CommandFamily = .showIPRoute
    public let parserVersion: String = "1.0.0"

    public init() {}

    public func canParse(rawOutput: String) -> Double {
        let lower = rawOutput.lowercased()
        if (lower.contains("gateway of last resort") || lower.contains("directly connected")) &&
           (lower.contains("codes: c - connected") || lower.contains("via ")) {
            return 0.95
        }
        return 0.0
    }

    public func parse(rawOutput: String) throws -> StructuredResult {
        let lines = rawOutput.components(separatedBy: .newlines)
        var entries: [RouteEntry] = []

        var inRoutingTable = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.lowercased().contains("gateway of last resort") {
                inRoutingTable = true
                continue
            }

            if !inRoutingTable {
                if trimmed.hasPrefix("C ") || trimmed.hasPrefix("S ") || trimmed.hasPrefix("O ") || trimmed.hasPrefix("B ") || trimmed.hasPrefix("D ") {
                    inRoutingTable = true
                } else {
                    continue
                }
            }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }

            let code = parts[0]
            let prefix = parts[1]
            guard prefix.contains(".") || prefix.contains(":") || prefix == "default" else { continue }

            var ad: Int?
            var metric: Int?
            var nextHop: String?
            var outIntf: String?
            var age: String?

            // Check metric bracket e.g. [110/20]
            for part in parts {
                if part.hasPrefix("[") && part.hasSuffix("]") {
                    let clean = part.dropFirst().dropLast()
                    let bracketParts = clean.split(separator: "/")
                    if bracketParts.count == 2 {
                        ad = Int(bracketParts[0])
                        metric = Int(bracketParts[1])
                    }
                } else if part.split(separator: ":").count == 3 {
                    age = part.trimmingCharacters(in: .punctuationCharacters)
                }
            }

            if let viaIdx = parts.firstIndex(of: "via"), viaIdx + 1 < parts.count {
                nextHop = parts[viaIdx + 1].trimmingCharacters(in: .punctuationCharacters)
            }

            if let intfIdx = parts.firstIndex(of: "connected,"), intfIdx + 1 < parts.count {
                outIntf = parts[intfIdx + 1].trimmingCharacters(in: .punctuationCharacters)
            } else if let last = parts.last, last.contains("Ethernet") || last.contains("Vlan") || last.contains("Port-channel") {
                outIntf = last.trimmingCharacters(in: .punctuationCharacters)
            }

            entries.append(RouteEntry(
                protocolCode: code,
                prefix: prefix,
                adminDistance: ad,
                metric: metric,
                nextHop: nextHop,
                outgoingInterface: outIntf,
                age: age
            ))
        }

        return .routes(entries)
    }
}

// MARK: - Show MAC Address Table Parser

public struct ShowMacAddressTableParser: VendorOutputParser {
    public let vendor: Vendor = .cisco
    public let operatingSystem: OperatingSystem = .iosXE
    public let commandFamily: CommandFamily = .showMacAddressTable
    public let parserVersion: String = "1.0.0"

    public init() {}

    public func canParse(rawOutput: String) -> Double {
        let lower = rawOutput.lowercased()
        if (lower.contains("mac address table") || lower.contains("mac-address-table")) &&
           (lower.contains("vlan") && lower.contains("ports")) {
            return 0.98
        }
        return 0.0
    }

    public func parse(rawOutput: String) throws -> StructuredResult {
        let lines = rawOutput.components(separatedBy: .newlines)
        var entries: [MacTableEntry] = []

        var headerPassed = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("---") || trimmed.hasPrefix("Total") { continue }

            let lower = trimmed.lowercased()
            if lower.contains("vlan") && lower.contains("mac address") {
                headerPassed = true
                continue
            }

            if !headerPassed { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 4, let vlan = Int(parts[0]) else { continue }

            let mac = parts[1]
            let type = parts[2]
            let port = parts[3]

            entries.append(MacTableEntry(vlan: vlan, macAddress: mac, type: type, port: port))
        }

        return .macTable(entries)
    }
}

// MARK: - Show ARP Parser

public struct ShowARPParser: VendorOutputParser {
    public let vendor: Vendor = .cisco
    public let operatingSystem: OperatingSystem = .iosXE
    public let commandFamily: CommandFamily = .showARP
    public let parserVersion: String = "1.0.0"

    public init() {}

    public func canParse(rawOutput: String) -> Double {
        let lower = rawOutput.lowercased()
        if lower.contains("protocol") && lower.contains("address") && lower.contains("age (min)") && lower.contains("hardware addr") {
            return 0.98
        }
        return 0.0
    }

    public func parse(rawOutput: String) throws -> StructuredResult {
        let lines = rawOutput.components(separatedBy: .newlines)
        var entries: [ARPEntry] = []

        var headerFound = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let lower = trimmed.lowercased()
            if lower.contains("protocol") && lower.contains("hardware addr") {
                headerFound = true
                continue
            }

            if !headerFound { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 6 else { continue }

            let proto = parts[0]
            let ip = parts[1]
            let age = parts[2]
            let mac = parts[3]
            let type = parts[4]
            let intf = parts[5]

            // Lookup vendor OUI
            let vendor = OUIResolver.resolve(mac: mac)

            entries.append(ARPEntry(
                protocolType: proto,
                ipAddress: ip,
                ageMinutes: age,
                macAddress: mac,
                type: type,
                interface: intf,
                vendor: vendor
            ))
        }

        return .arp(entries)
    }
}

// MARK: - Show CDP / LLDP Neighbors Parser

public struct ShowNeighborsParser: VendorOutputParser {
    public let vendor: Vendor = .cisco
    public let operatingSystem: OperatingSystem = .iosXE
    public let commandFamily: CommandFamily = .showNeighbors
    public let parserVersion: String = "1.0.0"

    public init() {}

    public func canParse(rawOutput: String) -> Double {
        let lower = rawOutput.lowercased()
        if lower.contains("device id") && lower.contains("local intrfce") && (lower.contains("holdtme") || lower.contains("capability")) {
            return 0.98
        }
        if lower.contains("show cdp neigh") || lower.contains("show lldp neigh") {
            return 0.95
        }
        return 0.0
    }

    public func parse(rawOutput: String) throws -> StructuredResult {
        let lines = rawOutput.components(separatedBy: .newlines)
        var entries: [NeighborEntry] = []

        var headerFound = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let lower = trimmed.lowercased()
            if lower.contains("device id") && lower.contains("local intrfce") {
                headerFound = true
                continue
            }

            if !headerFound { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            let deviceId = parts[0]

            // Find index of holdtime (first integer after deviceId)
            var holdtimeIdx: Int?
            var holdtime: Int?
            for i in 1..<parts.count {
                if let ht = Int(parts[i]) {
                    holdtimeIdx = i
                    holdtime = ht
                    break
                }
            }

            guard let htIdx = holdtimeIdx, htIdx > 1 else { continue }
            let localIntf = parts[1..<htIdx].joined(separator: " ")

            let remaining = parts.suffix(from: htIdx + 1)
            guard remaining.count >= 2 else { continue }

            let portId: String
            let platform: String
            let cap: String

            let lastToken = parts[parts.count - 1]
            let secondLastToken = parts[parts.count - 2]

            if lastToken.contains("/") && !secondLastToken.contains("/") && parts.count >= htIdx + 4 {
                portId = secondLastToken + " " + lastToken
                platform = parts[parts.count - 3]
                cap = parts[(htIdx + 1)..<(parts.count - 3)].joined(separator: " ")
            } else if parts.count >= htIdx + 3 {
                portId = lastToken
                platform = secondLastToken
                cap = parts[(htIdx + 1)..<(parts.count - 2)].joined(separator: " ")
            } else {
                portId = lastToken
                platform = "Unknown"
                cap = remaining.first ?? ""
            }

            entries.append(NeighborEntry(
                deviceId: deviceId,
                localInterface: localIntf,
                holdtime: holdtime,
                capability: cap,
                platform: platform,
                portId: portId
            ))
        }

        return .neighbors(entries)
    }
}

// MARK: - Show BGP Summary Parser

public struct ShowBGPSummaryParser: VendorOutputParser {
    public let vendor: Vendor = .cisco
    public let operatingSystem: OperatingSystem = .iosXE
    public let commandFamily: CommandFamily = .showBGPSummary
    public let parserVersion: String = "1.0.0"

    public init() {}

    public func canParse(rawOutput: String) -> Double {
        let lower = rawOutput.lowercased()
        if (lower.contains("bgp router identifier") || lower.contains("show ip bgp summary")) &&
           (lower.contains("neighbor") && lower.contains("state/pfxrcd")) {
            return 0.98
        }
        return 0.0
    }

    public func parse(rawOutput: String) throws -> StructuredResult {
        let lines = rawOutput.components(separatedBy: .newlines)
        var entries: [BGPSummaryEntry] = []

        var headerFound = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let lower = trimmed.lowercased()
            if lower.contains("neighbor") && lower.contains("state/pfxrcd") {
                headerFound = true
                continue
            }

            if !headerFound { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 10 else { continue }

            let neighbor = parts[0]
            guard let ver = Int(parts[1]),
                  let asNum = Int(parts[2]),
                  let msgRcvd = UInt64(parts[3]),
                  let msgSent = UInt64(parts[4]),
                  let tblVer = UInt64(parts[5]),
                  let inQ = Int(parts[6]),
                  let outQ = Int(parts[7]) else {
                continue
            }

            let upDown = parts[8]
            let stateOrPfx = parts[9]

            entries.append(BGPSummaryEntry(
                neighborIP: neighbor,
                version: ver,
                remoteAS: asNum,
                msgRcvd: msgRcvd,
                msgSent: msgSent,
                tableVersion: tblVer,
                inQ: inQ,
                outQ: outQ,
                upDown: upDown,
                stateOrPfxRcd: stateOrPfx
            ))
        }

        return .bgpSummary(entries)
    }
}

// MARK: - Show Version Parser

public struct ShowVersionParser: VendorOutputParser {
    public let vendor: Vendor = .cisco
    public let operatingSystem: OperatingSystem = .iosXE
    public let commandFamily: CommandFamily = .showVersion
    public let parserVersion: String = "1.0.0"

    public init() {}

    public func canParse(rawOutput: String) -> Double {
        let lower = rawOutput.lowercased()
        if lower.contains("cisco ios software") || lower.contains("cisco ios xe software") || lower.contains("uptime is") && lower.contains("processor") {
            return 0.95
        }
        if lower.contains("show version") {
            return 0.90
        }
        return 0.0
    }

    public func parse(rawOutput: String) throws -> StructuredResult {
        let lines = rawOutput.components(separatedBy: .newlines)
        var hardware = "Generic Device"
        var osVer = "Unknown OS"
        var uptime = "Unknown"
        var serial: String?
        var image: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            if lower.contains("cisco ios software") || lower.contains("cisco ios-xe software") || lower.contains("version ") {
                if osVer == "Unknown OS" {
                    osVer = trimmed
                }
            }
            if lower.contains("uptime is") {
                if let range = trimmed.range(of: "uptime is ", options: .caseInsensitive) {
                    uptime = String(trimmed[range.upperBound...])
                }
            }
            if lower.contains("processor board id") {
                if let range = trimmed.range(of: "processor board id ", options: .caseInsensitive) {
                    serial = String(trimmed[range.upperBound...]).components(separatedBy: .whitespaces).first
                }
            }
            if lower.contains("system image file is") {
                if let range = trimmed.range(of: "system image file is ", options: .caseInsensitive) {
                    image = String(trimmed[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                }
            }
            if (lower.contains("cisco") || lower.contains("catalyst") || lower.contains("asr") || lower.contains("nexus")) && lower.contains("bytes of memory") {
                hardware = trimmed.components(separatedBy: .whitespaces).prefix(3).joined(separator: " ")
            }
        }

        return .version(VersionEntry(
            hardware: hardware,
            osVersion: osVer,
            uptime: uptime,
            serialNumber: serial,
            systemImage: image
        ))
    }
}

// MARK: - Show VLAN Brief Parser

public struct ShowVLANParser: VendorOutputParser {
    public let vendor: Vendor = .cisco
    public let operatingSystem: OperatingSystem = .iosXE
    public let commandFamily: CommandFamily = .showVLAN
    public let parserVersion: String = "1.0.0"

    public init() {}

    public func canParse(rawOutput: String) -> Double {
        let lower = rawOutput.lowercased()
        if lower.contains("vlan") && lower.contains("name") && lower.contains("status") && lower.contains("ports") {
            return 0.95
        }
        if lower.contains("show vlan brief") || lower.contains("show vlan") {
            return 0.90
        }
        return 0.0
    }

    public func parse(rawOutput: String) throws -> StructuredResult {
        let lines = rawOutput.components(separatedBy: .newlines)
        var entries: [VlanEntry] = []
        var headerFound = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.starts(with: "----") { continue }

            let lower = trimmed.lowercased()
            if lower.contains("vlan") && lower.contains("name") && lower.contains("status") {
                headerFound = true
                continue
            }
            if !headerFound { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 3, let vid = Int(parts[0]) else { continue }

            let vName = parts[1]
            let vStatus = parts[2]
            var ports: [String] = []
            if parts.count > 3 {
                let joined = parts[3...].joined(separator: " ")
                ports = joined.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }

            entries.append(VlanEntry(vlanId: vid, name: vName, status: vStatus, ports: ports))
        }

        return .vlans(entries)
    }
}

// MARK: - Show IP OSPF Neighbor Parser

public struct ShowOSPFNeighborParser: VendorOutputParser {
    public let vendor: Vendor = .cisco
    public let operatingSystem: OperatingSystem = .iosXE
    public let commandFamily: CommandFamily = .showOSPFNeighbors
    public let parserVersion: String = "1.0.0"

    public init() {}

    public func canParse(rawOutput: String) -> Double {
        let lower = rawOutput.lowercased()
        if lower.contains("neighbor id") && lower.contains("pri") && lower.contains("state") && lower.contains("dead time") {
            return 0.96
        }
        if lower.contains("show ip ospf neighbor") {
            return 0.92
        }
        return 0.0
    }

    public func parse(rawOutput: String) throws -> StructuredResult {
        let lines = rawOutput.components(separatedBy: .newlines)
        var entries: [OSPFNeighborEntry] = []
        var headerFound = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let lower = trimmed.lowercased()
            if lower.contains("neighbor id") && lower.contains("pri") && lower.contains("state") {
                headerFound = true
                continue
            }
            if !headerFound { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 6 else { continue }

            let nid = parts[0]
            let pri = Int(parts[1]) ?? 1
            let state = parts[2]
            let dead = parts[3]
            let addr = parts[4]
            let intf = parts[5]

            entries.append(OSPFNeighborEntry(
                neighborId: nid,
                priority: pri,
                state: state,
                deadTime: dead,
                address: addr,
                interface: intf
            ))
        }

        return .ospfNeighbors(entries)
    }
}

// MARK: - Parser Registry

public struct ParserRegistry: Sendable {
    public static let shared = ParserRegistry()

    public let parsers: [any VendorOutputParser] = [
        ShowIPInterfaceBriefParser(),
        ShowInterfacesParser(),
        ShowIPRouteParser(),
        ShowMacAddressTableParser(),
        ShowARPParser(),
        ShowNeighborsParser(),
        ShowBGPSummaryParser(),
        ShowVersionParser(),
        ShowVLANParser(),
        ShowOSPFNeighborParser()
    ]

    public init() {}

    public func detectParser(for text: String) -> (parser: any VendorOutputParser, score: Double)? {
        var bestParser: (any VendorOutputParser)?
        var bestScore: Double = 0.0

        for p in parsers {
            let score = p.canParse(rawOutput: text)
            if score > bestScore {
                bestScore = score
                bestParser = p
            }
        }

        if let parser = bestParser, bestScore >= 0.5 {
            return (parser, bestScore)
        }
        return nil
    }

    public func parse(text: String, forcedFamily: CommandFamily? = nil) throws -> (parser: any VendorOutputParser, result: StructuredResult) {
        if let family = forcedFamily {
            guard let matched = parsers.first(where: { $0.commandFamily == family }) else {
                throw NSError(domain: "ParserRegistry", code: 404, userInfo: [NSLocalizedDescriptionKey: "No parser found for family \(family.rawValue)"])
            }
            let res = try matched.parse(rawOutput: text)
            return (matched, res)
        }

        guard let detected = detectParser(for: text) else {
            throw NSError(domain: "ParserRegistry", code: 400, userInfo: [NSLocalizedDescriptionKey: "Could not identify command format in terminal output."])
        }

        let res = try detected.parser.parse(rawOutput: text)
        return (detected.parser, res)
    }
}
