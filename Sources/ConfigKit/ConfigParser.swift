import Foundation
import NetworkCore

public struct ConfigParser: Sendable {
    public init() {}

    public func detectVendor(from text: String) -> VendorOS {
        let lower = text.lowercased()
        if lower.contains("set system") || lower.contains("set interfaces") || lower.contains("apply-groups") ||
           lower.contains("interfaces {") || lower.contains("protocols {") || lower.contains("system {") {
            return .juniperJunos
        }
        if lower.contains("config system ") || lower.contains("config firewall ") || lower.contains("config router ") ||
           (lower.contains("end\n") && lower.contains("edit ")) {
            return .fortinetFortiOS
        }
        if lower.contains("set rulebase") || lower.contains("set deviceconfig") || lower.contains("set shared") ||
           lower.contains("pan-os") || lower.contains("set zone") {
            return .paloAltoPANOS
        }
        if lower.contains("/ip address") || lower.contains("/ip firewall") || lower.contains("/interface bridge") ||
           lower.contains("/ip route") {
            return .mikrotikRouterOS
        }
        if lower.contains("sysname ") || lower.contains("display current-configuration") || lower.contains("system-view") {
            return .huaweiVRP
        }
        if lower.contains("frr version") || lower.contains("vtysh") || lower.contains("frr defaults") {
            return .linuxFRR
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
            let isComment = trimmed.hasPrefix("!") || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") || trimmed.isEmpty

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

            // Multi-Vendor Hostname & Domain Extraction
            let lowerTrimmed = trimmed.lowercased()
            if lowerTrimmed.hasPrefix("hostname ") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2 { hostname = String(parts[1]) }
            } else if lowerTrimmed.hasPrefix("sysname ") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2 { hostname = String(parts[1]) }
            } else if lowerTrimmed.contains("host-name ") {
                let parts = trimmed.replacingOccurrences(of: ";", with: "").split(separator: " ")
                if let idx = parts.firstIndex(where: { $0.lowercased() == "host-name" }), idx + 1 < parts.count {
                    hostname = String(parts[idx + 1])
                }
            } else if lowerTrimmed.hasPrefix("set hostname ") {
                let parts = trimmed.replacingOccurrences(of: "\"", with: "").split(separator: " ")
                if parts.count >= 3 { hostname = String(parts[2]) }
            } else if lowerTrimmed.contains("system identity set name=") {
                if let range = trimmed.range(of: "name=") {
                    hostname = String(trimmed[range.upperBound...]).replacingOccurrences(of: "\"", with: "")
                }
            } else if lowerTrimmed.hasPrefix("ip domain-name ") || lowerTrimmed.hasPrefix("ip domain name ") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 3 {
                    domainName = String(parts[2])
                } else if parts.count == 2 {
                    domainName = String(parts[1])
                }
            } else if lowerTrimmed.contains("domain-name ") {
                let parts = trimmed.replacingOccurrences(of: ";", with: "").split(separator: " ")
                if let idx = parts.firstIndex(where: { $0.lowercased() == "domain-name" }), idx + 1 < parts.count {
                    domainName = String(parts[idx + 1])
                }
            }
        }

        // Build Hierarchical Blocks
        let blocks = buildBlocks(lines: configLines, vendor: vendor)

        // Build Object Groups
        let objectGroups = extractObjectGroups(from: blocks, vendor: vendor)

        return ConfigAST(
            vendor: vendor,
            hostname: hostname,
            domainName: domainName,
            rawContent: text,
            blocks: blocks,
            allLines: configLines,
            objectGroups: objectGroups
        )
    }

    private func buildBlocks(lines: [ConfigLine], vendor: VendorOS) -> [ConfigBlock] {
        switch vendor {
        case .juniperJunos:
            return buildBraceBlocks(lines: lines)
        case .fortinetFortiOS:
            return buildFortinetBlocks(lines: lines)
        case .mikrotikRouterOS:
            return buildMikroTikBlocks(lines: lines)
        default:
            return buildIndentationBlocks(lines: lines)
        }
    }

    // MARK: - Indentation-based Block Builder (Cisco, Arista, Huawei, FRR)

    private func buildIndentationBlocks(lines: [ConfigLine]) -> [ConfigBlock] {
        var blocks: [ConfigBlock] = []
        var currentBlockHeader: ConfigLine?
        var currentBlockLines: [ConfigLine] = []

        for line in lines {
            let trimmed = line.rawText.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if line.indentation == 0 && !line.isComment {
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
                } else if !line.isComment {
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

    // MARK: - Juniper Curly-Brace { ... } Block Builder

    private func buildBraceBlocks(lines: [ConfigLine]) -> [ConfigBlock] {
        var blocks: [ConfigBlock] = []
        var currentHeader: ConfigLine?
        var currentLines: [ConfigLine] = []
        var braceDepth = 0

        for line in lines {
            let trimmed = line.rawText.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || line.isComment { continue }

            let openCount = trimmed.filter { $0 == "{" }.count
            let closeCount = trimmed.filter { $0 == "}" }.count

            if braceDepth == 0 && currentHeader == nil {
                currentHeader = line
                currentLines.append(line)
                braceDepth += (openCount - closeCount)
            } else {
                currentLines.append(line)
                braceDepth += (openCount - closeCount)

                if braceDepth <= 0 {
                    if let header = currentHeader {
                        let block = createBlock(header: header, blockLines: currentLines)
                        blocks.append(block)
                    }
                    currentHeader = nil
                    currentLines = []
                    braceDepth = 0
                }
            }
        }

        if let header = currentHeader {
            blocks.append(createBlock(header: header, blockLines: currentLines))
        }

        if blocks.isEmpty {
            return buildIndentationBlocks(lines: lines)
        }

        return blocks
    }

    // MARK: - Fortinet config ... end Block Builder

    private func buildFortinetBlocks(lines: [ConfigLine]) -> [ConfigBlock] {
        var blocks: [ConfigBlock] = []
        var currentHeader: ConfigLine?
        var currentLines: [ConfigLine] = []
        var inConfigBlock = false

        for line in lines {
            let trimmed = line.rawText.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            if trimmed.isEmpty || line.isComment { continue }

            if lower.hasPrefix("config ") {
                if let header = currentHeader {
                    blocks.append(createBlock(header: header, blockLines: currentLines))
                    currentLines = []
                }
                currentHeader = line
                currentLines.append(line)
                inConfigBlock = true
            } else if lower == "end" && inConfigBlock {
                currentLines.append(line)
                if let header = currentHeader {
                    blocks.append(createBlock(header: header, blockLines: currentLines))
                }
                currentHeader = nil
                currentLines = []
                inConfigBlock = false
            } else {
                if inConfigBlock {
                    currentLines.append(line)
                } else {
                    blocks.append(createBlock(header: line, blockLines: [line]))
                }
            }
        }

        if let header = currentHeader {
            blocks.append(createBlock(header: header, blockLines: currentLines))
        }

        return blocks
    }

    // MARK: - MikroTik / Section Block Builder

    private func buildMikroTikBlocks(lines: [ConfigLine]) -> [ConfigBlock] {
        var blocks: [ConfigBlock] = []
        var currentHeader: ConfigLine?
        var currentLines: [ConfigLine] = []

        for line in lines {
            let trimmed = line.rawText.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || line.isComment { continue }

            if trimmed.hasPrefix("/") {
                if let header = currentHeader {
                    blocks.append(createBlock(header: header, blockLines: currentLines))
                    currentLines = []
                }
                currentHeader = line
                currentLines.append(line)
            } else {
                if currentHeader != nil {
                    currentLines.append(line)
                } else {
                    blocks.append(createBlock(header: line, blockLines: [line]))
                }
            }
        }

        if let header = currentHeader {
            blocks.append(createBlock(header: header, blockLines: currentLines))
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
        if lower.hasPrefix("interface ") || lower.contains("config system interface") || lower.contains("set interfaces") ||
           lower.contains("interfaces {") || lower.hasPrefix("/ip address") || lower.hasPrefix("/interface") {
            return .interface
        }
        if lower.hasPrefix("vlan ") || lower.contains("vlans {") || lower.contains("set vlans") || lower.contains("/interface vlan") {
            return .vlan
        }
        if lower.hasPrefix("router ") || lower.contains("config router ") || lower.contains("protocols {") ||
           lower.contains("set protocols") || lower.hasPrefix("/routing") || lower.hasPrefix("ospf ") || lower.hasPrefix("bgp ") {
            return .router
        }
        if lower.hasPrefix("ip access-list") || lower.hasPrefix("access-list") || lower.hasPrefix("ipv6 access-list") ||
           lower.contains("config firewall policy") || lower.contains("set rulebase security") || lower.contains("firewall {") ||
           lower.contains("set firewall") || lower.hasPrefix("acl number") || lower.hasPrefix("acl name") ||
           lower.hasPrefix("/ip firewall") {
            return .acl
        }
        if lower.hasPrefix("line ") || lower.contains("user-interface ") {
            return .line
        }
        if lower.hasPrefix("aaa ") || lower.hasPrefix("username ") || lower.hasPrefix("crypto ") ||
           lower.hasPrefix("tacacs") || lower.hasPrefix("radius") || lower.hasPrefix("snmp-server") ||
           lower.contains("config system admin") || lower.contains("set system login") || lower.contains("/user") {
            return .management
        }
        if lower.hasPrefix("hostname") || lower.hasPrefix("sysname") || lower.hasPrefix("ip domain") || lower.hasPrefix("service ") ||
           lower.hasPrefix("banner ") || lower.hasPrefix("ntp ") || lower.hasPrefix("spanning-tree") || lower.contains("/system") {
            return .global
        }
        return .other
    }

    // MARK: - Object Groups Extraction

    public func extractObjectGroups(from blocks: [ConfigBlock], vendor: VendorOS) -> [ObjectGroup] {
        var groups: [ObjectGroup] = []

        for block in blocks {
            let lowerTitle = block.title.lowercased()

            // Cisco / Arista Object Groups
            if lowerTitle.hasPrefix("object-group ") {
                let parts = block.title.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard parts.count >= 3 else { continue }
                let typeStr = parts[1].lowercased()
                let name = parts[2]
                let type: ObjectGroupType = typeStr.contains("service") || typeStr.contains("port") ? .service : .network

                var members: [String] = []
                for line in block.lines.dropFirst() {
                    let trimmed = line.rawText.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || line.isComment { continue }
                    let clean = trimmed.replacingOccurrences(of: "host ", with: "").trimmingCharacters(in: .whitespaces)
                    members.append(clean)
                    if clean != trimmed {
                        members.append(trimmed)
                    }
                }
                groups.append(ObjectGroup(name: name, type: type, members: members))
            }

            // Fortinet Address Groups
            if lowerTitle.contains("config firewall addrgrp") {
                for line in block.lines {
                    let trimmed = line.rawText.trimmingCharacters(in: .whitespaces)
                    if trimmed.lowercased().hasPrefix("set member ") {
                        let raw = String(trimmed.dropFirst("set member ".count))
                        let names = raw.replacingOccurrences(of: "\"", with: "").components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                        groups.append(ObjectGroup(name: "FortiAddrGrp", type: .network, members: names))
                    }
                }
            }

            // Palo Alto Address Groups
            if lowerTitle.contains("set address-group") {
                let parts = block.title.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 3 {
                    let name = parts[2]
                    groups.append(ObjectGroup(name: name, type: .network, members: [block.title]))
                }
            }
        }

        return groups
    }

    // MARK: - Semantic Extractions: Interfaces

    public func extractInterfaces(from ast: ConfigAST) -> [InterfaceConfig] {
        var interfaces: [InterfaceConfig] = []

        if ast.vendor == .juniperJunos {
            var curIntf: String?
            var curDesc: String?
            var curIP: String?
            var curMask: String?

            for line in ast.allLines {
                let trimmed = line.rawText.trimmingCharacters(in: .whitespaces)
                let lower = trimmed.lowercased()

                if lower.starts(with: "set interfaces ") {
                    let parts = trimmed.components(separatedBy: .whitespaces)
                    if parts.count >= 3 {
                        let name = parts[2]
                        var ip: String?
                        var mask: String?
                        if let addrIdx = parts.firstIndex(of: "address"), addrIdx + 1 < parts.count {
                            let raw = parts[addrIdx + 1].replacingOccurrences(of: ";", with: "")
                            let sub = raw.split(separator: "/")
                            ip = String(sub[0])
                            if sub.count > 1, let cidr = Int(sub[1]) {
                                mask = cidrToMask(cidr)
                            }
                        }
                        interfaces.append(InterfaceConfig(name: name, ipAddress: ip, subnetMask: mask))
                    }
                } else if (lower.hasPrefix("ge-") || lower.hasPrefix("xe-") || lower.hasPrefix("et-") || lower.hasPrefix("fe-")) && trimmed.contains("{") {
                    if let name = curIntf {
                        interfaces.append(InterfaceConfig(name: name, description: curDesc, ipAddress: curIP, subnetMask: curMask))
                    }
                    curIntf = trimmed.replacingOccurrences(of: "{", with: "").trimmingCharacters(in: .whitespaces)
                    curDesc = nil
                    curIP = nil
                    curMask = nil
                } else if lower.hasPrefix("description ") {
                    curDesc = String(trimmed.dropFirst("description ".count)).replacingOccurrences(of: ";", with: "").replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                } else if lower.hasPrefix("address ") {
                    let raw = String(trimmed.dropFirst("address ".count)).replacingOccurrences(of: ";", with: "").trimmingCharacters(in: .whitespaces)
                    let sub = raw.split(separator: "/")
                    curIP = String(sub[0])
                    if sub.count > 1, let cidr = Int(sub[1]) {
                        curMask = cidrToMask(cidr)
                    }
                }
            }

            if let name = curIntf {
                interfaces.append(InterfaceConfig(name: name, description: curDesc, ipAddress: curIP, subnetMask: curMask))
            }

            if !interfaces.isEmpty {
                return interfaces
            }
        }

        for block in ast.blocks where block.sectionType == .interface {
            let title = block.title
            var intfName = title.replacingOccurrences(of: "interface ", with: "", options: [.caseInsensitive])
                                .replacingOccurrences(of: "edit \"", with: "")
                                .replacingOccurrences(of: "\"", with: "")
                                .trimmingCharacters(in: .whitespaces)

            if intfName.hasPrefix("/ip address") {
                intfName = "MikroTik-Interfaces"
            }

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
                } else if lower.hasPrefix("set description ") {
                    description = String(trimmed.dropFirst("set description ".count)).replacingOccurrences(of: "\"", with: "")
                } else if lower.hasPrefix("ip address ") {
                    let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if parts.count >= 3 {
                        let ipCandidate = parts[2]
                        if ipCandidate.contains("/") {
                            let subParts = ipCandidate.split(separator: "/")
                            ipAddress = String(subParts[0])
                            if subParts.count > 1, let cidr = Int(subParts[1]) {
                                subnetMask = cidrToMask(cidr)
                            }
                        } else if parts.count >= 4 {
                            ipAddress = ipCandidate
                            subnetMask = parts[3]
                        }
                    }
                } else if lower.hasPrefix("set ip ") {
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
                } else if lower == "shutdown" || lower == "set status down" || lower.contains("disable") {
                    isShutdown = true
                } else if lower.hasPrefix("mtu ") {
                    let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if parts.count >= 2, let m = Int(parts[1]) { mtu = m }
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

    // MARK: - Semantic Extractions: Routing

    public func extractRouting(from ast: ConfigAST) -> [RoutingConfig] {
        var configs: [RoutingConfig] = []

        for block in ast.blocks where block.sectionType == .router {
            let lower = block.title.lowercased()
            let proto: RoutingProtocol
            var asNum: Int?

            if lower.contains("bgp") {
                proto = .bgp
                let parts = block.title.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                for (idx, p) in parts.enumerated() where p.lowercased() == "bgp" && idx + 1 < parts.count {
                    asNum = Int(parts[idx + 1])
                }
            } else if lower.contains("ospf") {
                proto = .ospf
                let parts = block.title.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                for (idx, p) in parts.enumerated() where p.lowercased() == "ospf" && idx + 1 < parts.count {
                    asNum = Int(parts[idx + 1])
                }
            } else if lower.contains("isis") {
                proto = .isis
            } else if lower.contains("eigrp") {
                proto = .eigrp
                let parts = block.title.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                for (idx, p) in parts.enumerated() where p.lowercased() == "eigrp" && idx + 1 < parts.count {
                    asNum = Int(parts[idx + 1])
                }
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

                if l.hasPrefix("router-id ") || l.hasPrefix("bgp router-id ") || l.hasPrefix("set router-id ") {
                    let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if parts.count >= 2 { routerId = parts.last?.replacingOccurrences(of: "\"", with: "") }
                } else if l.hasPrefix("network ") || l.hasPrefix("set network ") {
                    networks.append(trimmed)
                } else if l.hasPrefix("neighbor ") || l.hasPrefix("config neighbor") {
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

    // MARK: - Semantic Extractions: ACLs & Firewalls

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

            for line in block.lines {
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

            if !rules.isEmpty {
                acls.append(ACLConfig(name: name, isExtended: isExtended, rules: rules))
            }
        }

        return acls
    }

    public func parseACLRuleLine(_ text: String, defaultSeq: Int, remark: String?) -> ACLRule? {
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
        guard actionStr == "PERMIT" || actionStr == "DENY" || actionStr == "ACCEPT" || actionStr == "DROP" || actionStr == "DISCARD" else {
            return nil
        }
        let action: ACLAction = (actionStr == "PERMIT" || actionStr == "ACCEPT") ? .permit : .deny
        idx += 1

        guard idx < parts.count else { return nil }
        let protoStr = parts[idx].lowercased()
        let proto: ACLProtocol
        switch protoStr {
        case "tcp": proto = .tcp
        case "udp": proto = .udp
        case "icmp", "icmpv6": proto = .icmp
        case "ip", "all": proto = .ip
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

        if token == "any" || token == "all" {
            return (.any, idx + 1)
        } else if (token == "object-group" || token == "addrgrp") && idx + 1 < parts.count {
            return (.objectGroup(parts[idx + 1]), idx + 2)
        } else if token == "host" && idx + 1 < parts.count {
            return (.host(parts[idx + 1]), idx + 2)
        } else if idx + 1 < parts.count && isIPAddress(parts[idx]) && isIPAddress(parts[idx + 1]) {
            return (.subnet(network: parts[idx], wildcard: parts[idx + 1]), idx + 2)
        } else if token.contains("/") {
            let subParts = token.split(separator: "/")
            if subParts.count == 2, let cidr = Int(subParts[1]) {
                let mask = cidrToMask(cidr)
                let wild = maskToWildcard(mask)
                return (.subnet(network: String(subParts[0]), wildcard: wild), idx + 1)
            }
            return (.host(token), idx + 1)
        } else if isIPAddress(token) {
            return (.host(token), idx + 1)
        } else {
            return (.any, idx + 1)
        }
    }

    private func isIPAddress(_ str: String) -> Bool {
        IPAddress(str) != nil
    }

    private func cidrToMask(_ cidr: Int) -> String {
        guard cidr >= 0 && cidr <= 32 else { return "255.255.255.255" }
        let mask: UInt32 = cidr == 0 ? 0 : (~0 << (32 - cidr))
        return "\((mask >> 24) & 0xFF).\((mask >> 16) & 0xFF).\((mask >> 8) & 0xFF).\(mask & 0xFF)"
    }

    private func maskToWildcard(_ mask: String) -> String {
        let parts = mask.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return "0.0.0.0" }
        return "\(255 - parts[0]).\(255 - parts[1]).\(255 - parts[2]).\(255 - parts[3])"
    }

    public func resolveNamedPort(_ str: String) -> UInt16? {
        switch str.lowercased() {
        case "http", "www": return 80
        case "https": return 443
        case "ssh": return 22
        case "telnet": return 23
        case "dns", "domain": return 53
        case "ntp": return 123
        case "snmp": return 161
        case "snmptrap", "snmp-trap": return 162
        case "bgp": return 179
        case "radius": return 1812
        case "tacacs": return 49
        case "ldap": return 389
        case "ldaps": return 636
        case "rdp": return 3389
        case "sip": return 5060
        case "vxlan": return 4789
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
