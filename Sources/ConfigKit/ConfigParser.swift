import Foundation
import NetworkCore

public struct ConfigParser: Sendable {
    public init() {}

    public func detectVendor(from text: String) -> VendorOS {
        let lower = text.lowercased()
        if lower.contains("set system") || lower.contains("set interfaces") || lower.contains("apply-groups") {
            return .juniperJunos
        }
        if lower.contains("feature ") || lower.contains("cisco-nxos") || lower.contains("vrf context") {
            return .ciscoNXOS
        }
        if lower.contains("arista") || lower.contains("management api http-commands") {
            return .aristaEOS
        }
        return .ciscoIOS
    }

    public func parse(text: String, forcedVendor: VendorOS? = nil) -> ConfigAST {
        let vendor = forcedVendor ?? detectVendor(from: text)
        let rawLines = text.components(separatedBy: .newlines)

        var configLines: [ConfigLine] = []
        var hostname: String?
        var domainName: String?

        for (index, rawLine) in rawLines.enumerated() {
            let lineNum = index + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let isComment = trimmed.hasPrefix("!") || trimmed.hasPrefix("#") || trimmed.isEmpty

            var indent = 0
            for char in rawLine {
                if char == " " { indent += 1 }
                else if char == "\t" { indent += 4 }
                else { break }
            }

            let line = ConfigLine(
                id: lineNum,
                lineNumber: lineNum,
                indentation: indent,
                rawText: rawLine,
                isComment: isComment
            )
            configLines.append(line)

            // Extract Hostname & Domain
            if trimmed.lowercased().hasPrefix("hostname ") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2 {
                    hostname = String(parts[1])
                }
            } else if trimmed.lowercased().hasPrefix("ip domain-name ") || trimmed.lowercased().hasPrefix("ip domain name ") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 3 {
                    domainName = String(parts[2])
                } else if parts.count == 2 {
                    domainName = String(parts[1])
                }
            }
        }

        // Build Hierarchical Blocks
        let blocks = buildBlocks(lines: configLines)

        return ConfigAST(
            vendor: vendor,
            hostname: hostname,
            domainName: domainName,
            rawContent: text,
            blocks: blocks,
            allLines: configLines
        )
    }

    private func buildBlocks(lines: [ConfigLine]) -> [ConfigBlock] {
        var blocks: [ConfigBlock] = []
        var currentBlockHeader: ConfigLine?
        var currentBlockLines: [ConfigLine] = []

        for line in lines {
            let trimmed = line.rawText.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if line.indentation == 0 && !line.isComment {
                // End previous block if exists
                if let header = currentBlockHeader {
                    let block = createBlock(header: header, blockLines: currentBlockLines)
                    blocks.append(block)
                    currentBlockLines = []
                }
                currentBlockHeader = line
                currentBlockLines.append(line)
            } else {
                if currentBlockHeader != nil {
                    currentBlockLines.append(line)
                } else {
                    // Pre-header line
                    let orphanedBlock = createBlock(header: line, blockLines: [line])
                    blocks.append(orphanedBlock)
                }
            }
        }

        if let header = currentBlockHeader {
            let block = createBlock(header: header, blockLines: currentBlockLines)
            blocks.append(block)
        }

        return blocks
    }

    private func createBlock(header: ConfigLine, blockLines: [ConfigLine]) -> ConfigBlock {
        let trimmed = header.rawText.trimmingCharacters(in: .whitespaces)
        let section = categorizeSection(title: trimmed)
        let startLine = blockLines.first?.lineNumber ?? header.lineNumber
        let endLine = blockLines.last?.lineNumber ?? header.lineNumber

        return ConfigBlock(
            title: trimmed,
            sectionType: section,
            startLine: startLine,
            endLine: endLine,
            lines: blockLines
        )
    }

    private func categorizeSection(title: String) -> ConfigSectionType {
        let lower = title.lowercased()
        if lower.hasPrefix("interface ") { return .interface }
        if lower.hasPrefix("vlan ") { return .vlan }
        if lower.hasPrefix("router ") { return .router }
        if lower.hasPrefix("ip access-list") || lower.hasPrefix("access-list") || lower.hasPrefix("ipv6 access-list") { return .acl }
        if lower.hasPrefix("line ") { return .line }
        if lower.hasPrefix("aaa ") || lower.hasPrefix("username ") || lower.hasPrefix("crypto ") ||
            lower.hasPrefix("tacacs") || lower.hasPrefix("radius") || lower.hasPrefix("snmp-server") {
            return .management
        }
        if lower.hasPrefix("hostname") || lower.hasPrefix("ip domain") || lower.hasPrefix("service ") ||
            lower.hasPrefix("banner ") || lower.hasPrefix("ntp ") || lower.hasPrefix("spanning-tree") {
            return .global
        }
        return .other
    }

    // MARK: - Semantic Extractions

    public func extractInterfaces(from ast: ConfigAST) -> [InterfaceConfig] {
        var interfaces: [InterfaceConfig] = []

        for block in ast.blocks where block.sectionType == .interface {
            let title = block.title
            let intfName = title.replacingOccurrences(of: "interface ", with: "", options: [.caseInsensitive])

            var description: String?
            var ipAddress: String?
            var subnetMask: String?
            var accessVlan: Int?
            var trunkAllowed: [Int] = []
            var isShutdown = false
            var mtu: Int?
            var speed: String?
            var duplex: String?

            for line in block.lines {
                let trimmed = line.rawText.trimmingCharacters(in: .whitespaces)
                let lower = trimmed.lowercased()

                if lower.hasPrefix("description ") {
                    description = String(trimmed.dropFirst("description ".count))
                } else if lower.hasPrefix("ip address ") {
                    let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if parts.count >= 4 {
                        ipAddress = parts[2]
                        subnetMask = parts[3]
                    }
                } else if lower.hasPrefix("switchport access vlan ") {
                    let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if parts.count >= 4, let v = Int(parts[3]) {
                        accessVlan = v
                    }
                } else if lower.hasPrefix("switchport trunk allowed vlan ") {
                    let rawVlans = String(trimmed.dropFirst("switchport trunk allowed vlan ".count))
                        .replacingOccurrences(of: "add ", with: "")
                    trunkAllowed = parseVlanList(rawVlans)
                } else if lower == "shutdown" {
                    isShutdown = true
                } else if lower.hasPrefix("mtu ") {
                    let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if parts.count >= 2, let m = Int(parts[1]) {
                        mtu = m
                    }
                } else if lower.hasPrefix("speed ") {
                    let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if parts.count >= 2 { speed = parts[1] }
                } else if lower.hasPrefix("duplex ") {
                    let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if parts.count >= 2 { duplex = parts[1] }
                }
            }

            interfaces.append(InterfaceConfig(
                name: intfName,
                description: description,
                ipAddress: ipAddress,
                subnetMask: subnetMask,
                accessVlan: accessVlan,
                trunkAllowedVlans: trunkAllowed,
                isShutdown: isShutdown,
                mtu: mtu,
                speed: speed,
                duplex: duplex
            ))
        }

        return interfaces
    }

    public func extractRouting(from ast: ConfigAST) -> [RoutingConfig] {
        var configs: [RoutingConfig] = []

        for block in ast.blocks where block.sectionType == .router {
            let lower = block.title.lowercased()
            let proto: RoutingProtocol
            var asNum: Int?

            if lower.hasPrefix("router bgp ") {
                proto = .bgp
                let parts = block.title.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 3 { asNum = Int(parts[2]) }
            } else if lower.hasPrefix("router ospf ") {
                proto = .ospf
                let parts = block.title.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 3 { asNum = Int(parts[2]) }
            } else if lower.hasPrefix("router isis") {
                proto = .isis
            } else if lower.hasPrefix("router eigrp ") {
                proto = .eigrp
                let parts = block.title.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 3 { asNum = Int(parts[2]) }
            } else {
                proto = .staticRoute
            }

            var routerId: String?
            var networks: [String] = []
            var neighbors: [String] = []
            var areas: [String] = []

            for line in block.lines {
                let trimmed = line.rawText.trimmingCharacters(in: .whitespaces)
                let l = trimmed.lowercased()

                if l.hasPrefix("router-id ") || l.hasPrefix("bgp router-id ") {
                    let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if parts.count >= 2 { routerId = parts.last }
                } else if l.hasPrefix("network ") {
                    networks.append(trimmed)
                } else if l.hasPrefix("neighbor ") {
                    neighbors.append(trimmed)
                } else if l.hasPrefix("area ") {
                    areas.append(trimmed)
                }
            }

            configs.append(RoutingConfig(
                routingProtocol: proto,
                autonomousSystem: asNum,
                routerId: routerId,
                networks: networks,
                neighbors: neighbors,
                areas: areas
            ))
        }

        return configs
    }

    public func extractACLs(from ast: ConfigAST) -> [ACLConfig] {
        var acls: [ACLConfig] = []

        for block in ast.blocks where block.sectionType == .acl {
            let title = block.title
            let isExtended = !title.lowercased().contains("standard")
            let nameParts = title.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            let name = nameParts.last ?? "ACL-\(block.startLine)"

            var rules: [ACLRule] = []
            var currentRemark: String?
            var autoSeq = 10

            for line in block.lines.dropFirst() {
                let trimmed = line.rawText.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || line.isComment { continue }

                if trimmed.lowercased().hasPrefix("remark ") {
                    currentRemark = String(trimmed.dropFirst("remark ".count))
                    continue
                }

                if let rule = parseACLRuleLine(trimmed, defaultSeq: autoSeq, remark: currentRemark) {
                    rules.append(rule)
                    autoSeq = rule.sequence + 10
                    currentRemark = nil
                }
            }

            acls.append(ACLConfig(name: name, isExtended: isExtended, rules: rules))
        }

        return acls
    }

    private func parseACLRuleLine(_ text: String, defaultSeq: Int, remark: String?) -> ACLRule? {
        let parts = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        var idx = 0
        var sequence = defaultSeq

        if let seqVal = Int(parts[0]) {
            sequence = seqVal
            idx += 1
        }

        guard idx < parts.count else { return nil }
        let actionStr = parts[idx].uppercased()
        let action: ACLAction = (actionStr == "PERMIT") ? .permit : .deny
        idx += 1

        guard idx < parts.count else { return nil }
        let protoStr = parts[idx].lowercased()
        let proto: ACLProtocol
        switch protoStr {
        case "tcp": proto = .tcp
        case "udp": proto = .udp
        case "icmp": proto = .icmp
        case "ip": proto = .ip
        default: proto = .any
        }
        idx += 1

        // Parse Source
        guard idx < parts.count else { return nil }
        let (srcMatch, nextIdx1) = parseNetworkMatch(parts: parts, startIndex: idx)
        idx = nextIdx1

        // Parse Destination
        guard idx < parts.count else {
            return ACLRule(
                id: sequence,
                sequence: sequence,
                action: action,
                protocolType: proto,
                source: srcMatch,
                destination: .any,
                portOperator: nil,
                remark: remark,
                rawText: text
            )
        }
        let (dstMatch, nextIdx2) = parseNetworkMatch(parts: parts, startIndex: idx)
        idx = nextIdx2

        // Parse Port Operator if any
        var portOp: PortOperator?
        if idx < parts.count {
            let opToken = parts[idx].lowercased()
            if opToken == "eq" && idx + 1 < parts.count {
                if let p = UInt16(parts[idx + 1]) {
                    portOp = .eq(p)
                } else if let p = resolveNamedPort(parts[idx + 1]) {
                    portOp = .eq(p)
                }
            } else if opToken == "range" && idx + 2 < parts.count {
                if let p1 = UInt16(parts[idx + 1]), let p2 = UInt16(parts[idx + 2]) {
                    portOp = .range(p1, p2)
                }
            } else if opToken == "gt" && idx + 1 < parts.count, let p = UInt16(parts[idx + 1]) {
                portOp = .gt(p)
            } else if opToken == "lt" && idx + 1 < parts.count, let p = UInt16(parts[idx + 1]) {
                portOp = .lt(p)
            }
        }

        let isEst = text.lowercased().contains("established")

        return ACLRule(
            id: sequence,
            sequence: sequence,
            action: action,
            protocolType: proto,
            source: srcMatch,
            destination: dstMatch,
            portOperator: portOp,
            isEstablished: isEst,
            remark: remark,
            rawText: text
        )
    }

    private func parseNetworkMatch(parts: [String], startIndex: Int) -> (NetworkMatch, Int) {
        let idx = startIndex
        let token = parts[idx].lowercased()

        if token == "any" {
            return (.any, idx + 1)
        } else if token == "host" && idx + 1 < parts.count {
            return (.host(parts[idx + 1]), idx + 2)
        } else if idx + 1 < parts.count && isIPAddress(parts[idx]) && isIPAddress(parts[idx + 1]) {
            return (.subnet(network: parts[idx], wildcard: parts[idx + 1]), idx + 2)
        } else if isIPAddress(token) {
            return (.host(token), idx + 1)
        } else {
            return (.any, idx + 1)
        }
    }

    private func isIPAddress(_ str: String) -> Bool {
        IPAddress(str) != nil
    }

    private func resolveNamedPort(_ str: String) -> UInt16? {
        switch str.lowercased() {
        case "http", "www": return 80
        case "https": return 443
        case "ssh": return 22
        case "telnet": return 23
        case "dns", "domain": return 53
        case "ntp": return 123
        case "snmp": return 161
        case "bgp": return 179
        default: return nil
        }
    }

    private func parseVlanList(_ str: String) -> [Int] {
        var result: [Int] = []
        let segments = str.split(separator: ",")
        for seg in segments {
            let s = seg.trimmingCharacters(in: .whitespaces)
            if s.contains("-") {
                let rangeParts = s.split(separator: "-")
                if rangeParts.count == 2,
                   let start = Int(rangeParts[0].trimmingCharacters(in: .whitespaces)),
                   let end = Int(rangeParts[1].trimmingCharacters(in: .whitespaces)),
                   start <= end {
                    result.append(contentsOf: start...end)
                }
            } else if let vlan = Int(s) {
                result.append(vlan)
            }
        }
        return result
    }
}
