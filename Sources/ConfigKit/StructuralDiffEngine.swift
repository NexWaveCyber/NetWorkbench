import Foundation

public enum DiffLineKind: String, Sendable, Codable {
    case unchanged = "UNCHANGED"
    case added = "ADDED"
    case removed = "REMOVED"
    case modified = "MODIFIED"
}

public struct DiffLine: Identifiable, Sendable {
    public let id: Int
    public let kind: DiffLineKind
    public let oldLineNumber: Int?
    public let newLineNumber: Int?
    public let text: String

    public init(id: Int, kind: DiffLineKind, oldLineNumber: Int?, newLineNumber: Int?, text: String) {
        self.id = id
        self.kind = kind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.text = text
    }
}

public enum SemanticCategory: String, Sendable, CaseIterable, Codable {
    case interface = "Interface"
    case vlan = "VLAN"
    case routing = "Routing"
    case acl = "Access List"
    case security = "Security & AAA"
    case global = "Global / Hostname"
}

public struct SemanticChange: Identifiable, Sendable {
    public let id: String
    public let category: SemanticCategory
    public let changeType: DiffLineKind
    public let title: String
    public let detail: String

    public init(
        id: String = UUID().uuidString,
        category: SemanticCategory,
        changeType: DiffLineKind,
        title: String,
        detail: String
    ) {
        self.id = id
        self.category = category
        self.changeType = changeType
        self.title = title
        self.detail = detail
    }
}

public struct StructuralDiffReport: Sendable {
    public let semanticChanges: [SemanticChange]
    public let diffLines: [DiffLine]
    public let addedCount: Int
    public let removedCount: Int
    public let modifiedCount: Int

    public init(
        semanticChanges: [SemanticChange],
        diffLines: [DiffLine],
        addedCount: Int,
        removedCount: Int,
        modifiedCount: Int
    ) {
        self.semanticChanges = semanticChanges
        self.diffLines = diffLines
        self.addedCount = addedCount
        self.removedCount = removedCount
        self.modifiedCount = modifiedCount
    }
}

public struct StructuralDiffEngine: Sendable {
    private let parser = ConfigParser()

    public init() {}

    public func compare(baseline: String, target: String) -> StructuralDiffReport {
        let astA = parser.parse(text: baseline)
        let astB = parser.parse(text: target)

        var semanticChanges: [SemanticChange] = []

        // 1. Hostname / Global
        if astA.hostname != astB.hostname {
            semanticChanges.append(SemanticChange(
                category: .global,
                changeType: .modified,
                title: "Hostname Changed",
                detail: "\(astA.hostname ?? "none") ➔ \(astB.hostname ?? "none")"
            ))
        }

        // 2. Interfaces
        let intfsA = parser.extractInterfaces(from: astA)
        let intfsB = parser.extractInterfaces(from: astB)
        let mapA = Dictionary(uniqueKeysWithValues: intfsA.map { ($0.name.lowercased(), $0) })
        let mapB = Dictionary(uniqueKeysWithValues: intfsB.map { ($0.name.lowercased(), $0) })

        for intfB in intfsB {
            let key = intfB.name.lowercased()
            if let intfA = mapA[key] {
                // Check modifications
                var diffs: [String] = []
                if intfA.accessVlan != intfB.accessVlan {
                    diffs.append("Access VLAN: \(intfA.accessVlan.map(String.init) ?? "none") ➔ \(intfB.accessVlan.map(String.init) ?? "none")")
                }
                if intfA.trunkAllowedVlans != intfB.trunkAllowedVlans {
                    diffs.append("Trunk VLANs changed (\(intfA.trunkAllowedVlans.count) ➔ \(intfB.trunkAllowedVlans.count) VLANs)")
                }
                if intfA.ipAddress != intfB.ipAddress {
                    diffs.append("IP: \(intfA.ipAddress ?? "unassigned") ➔ \(intfB.ipAddress ?? "unassigned")")
                }
                if intfA.isShutdown != intfB.isShutdown {
                    diffs.append(intfB.isShutdown ? "Administratively shutdown" : "Enabled (no shutdown)")
                }
                if intfA.mtu != intfB.mtu {
                    diffs.append("MTU: \(intfA.mtu.map(String.init) ?? "default") ➔ \(intfB.mtu.map(String.init) ?? "default")")
                }

                if !diffs.isEmpty {
                    semanticChanges.append(SemanticChange(
                        category: .interface,
                        changeType: .modified,
                        title: "Interface \(intfB.name) Modified",
                        detail: diffs.joined(separator: ", ")
                    ))
                }
            } else {
                semanticChanges.append(SemanticChange(
                    category: .interface,
                    changeType: .added,
                    title: "Interface \(intfB.name) Added",
                    detail: "IP: \(intfB.ipAddress ?? "unassigned"), Shutdown: \(intfB.isShutdown)"
                ))
            }
        }

        for intfA in intfsA where mapB[intfA.name.lowercased()] == nil {
            semanticChanges.append(SemanticChange(
                category: .interface,
                changeType: .removed,
                title: "Interface \(intfA.name) Removed",
                detail: "Interface absent in target configuration"
            ))
        }

        // 3. Routing
        let routesA = parser.extractRouting(from: astA)
        let routesB = parser.extractRouting(from: astB)
        let rMapA = Dictionary(uniqueKeysWithValues: routesA.map { ($0.routingProtocol.rawValue, $0) })
        let rMapB = Dictionary(uniqueKeysWithValues: routesB.map { ($0.routingProtocol.rawValue, $0) })

        for rB in routesB {
            if let rA = rMapA[rB.routingProtocol.rawValue] {
                let addedNeighbors = Set(rB.neighbors).subtracting(rA.neighbors)
                let removedNeighbors = Set(rA.neighbors).subtracting(rB.neighbors)
                for n in addedNeighbors {
                    semanticChanges.append(SemanticChange(
                        category: .routing,
                        changeType: .added,
                        title: "\(rB.routingProtocol.rawValue) Neighbor Added",
                        detail: n
                    ))
                }
                for n in removedNeighbors {
                    semanticChanges.append(SemanticChange(
                        category: .routing,
                        changeType: .removed,
                        title: "\(rB.routingProtocol.rawValue) Neighbor Removed",
                        detail: n
                    ))
                }
            } else {
                semanticChanges.append(SemanticChange(
                    category: .routing,
                    changeType: .added,
                    title: "\(rB.routingProtocol.rawValue) Process Configured",
                    detail: "AS/Process: \(rB.autonomousSystem.map(String.init) ?? "none")"
                ))
            }
        }

        for rA in routesA where rMapB[rA.routingProtocol.rawValue] == nil {
            semanticChanges.append(SemanticChange(
                category: .routing,
                changeType: .removed,
                title: "\(rA.routingProtocol.rawValue) Process Removed",
                detail: "Routing process absent in target configuration"
            ))
        }

        // 4. ACLs
        let aclsA = parser.extractACLs(from: astA)
        let aclsB = parser.extractACLs(from: astB)
        let aclMapA = Dictionary(uniqueKeysWithValues: aclsA.map { ($0.name.lowercased(), $0) })
        let aclMapB = Dictionary(uniqueKeysWithValues: aclsB.map { ($0.name.lowercased(), $0) })

        for aB in aclsB {
            if let aA = aclMapA[aB.name.lowercased()] {
                if aA.rules.count != aB.rules.count {
                    semanticChanges.append(SemanticChange(
                        category: .acl,
                        changeType: .modified,
                        title: "ACL '\(aB.name)' Rule Count Changed",
                        detail: "\(aA.rules.count) rules ➔ \(aB.rules.count) rules"
                    ))
                }
            } else {
                semanticChanges.append(SemanticChange(
                    category: .acl,
                    changeType: .added,
                    title: "ACL '\(aB.name)' Added",
                    detail: "\(aB.rules.count) rules defined"
                ))
            }
        }

        for aA in aclsA where aclMapB[aA.name.lowercased()] == nil {
            semanticChanges.append(SemanticChange(
                category: .acl,
                changeType: .removed,
                title: "ACL '\(aA.name)' Removed",
                detail: "ACL absent in target configuration"
            ))
        }

        // 5. Line-by-Line Diff Calculation
        let (lines, added, removed, modified) = computeLineDiff(oldText: baseline, newText: target)

        return StructuralDiffReport(
            semanticChanges: semanticChanges,
            diffLines: lines,
            addedCount: added,
            removedCount: removed,
            modifiedCount: modified
        )
    }

    private func computeLineDiff(oldText: String, newText: String) -> ([DiffLine], Int, Int, Int) {
        let oldLines = oldText.components(separatedBy: .newlines)
        let newLines = newText.components(separatedBy: .newlines)

        var diffs: [DiffLine] = []
        var added = 0
        var removed = 0
        var modified = 0

        // Fast Longest Common Subsequence or Myers approximation for clean diff
        let oldSet = Set(oldLines)
        let newSet = Set(newLines)

        var oldIdx = 0
        var newIdx = 0
        var lineId = 1

        while oldIdx < oldLines.count || newIdx < newLines.count {
            if oldIdx < oldLines.count && newIdx < newLines.count {
                let o = oldLines[oldIdx]
                let n = newLines[newIdx]

                if o == n {
                    diffs.append(DiffLine(id: lineId, kind: .unchanged, oldLineNumber: oldIdx + 1, newLineNumber: newIdx + 1, text: o))
                    oldIdx += 1
                    newIdx += 1
                } else if !newSet.contains(o) && !oldSet.contains(n) {
                    diffs.append(DiffLine(id: lineId, kind: .modified, oldLineNumber: oldIdx + 1, newLineNumber: newIdx + 1, text: "- \(o)\n+ \(n)"))
                    modified += 1
                    oldIdx += 1
                    newIdx += 1
                } else if !newSet.contains(o) {
                    diffs.append(DiffLine(id: lineId, kind: .removed, oldLineNumber: oldIdx + 1, newLineNumber: nil, text: "- \(o)"))
                    removed += 1
                    oldIdx += 1
                } else {
                    diffs.append(DiffLine(id: lineId, kind: .added, oldLineNumber: nil, newLineNumber: newIdx + 1, text: "+ \(n)"))
                    added += 1
                    newIdx += 1
                }
            } else if oldIdx < oldLines.count {
                let o = oldLines[oldIdx]
                diffs.append(DiffLine(id: lineId, kind: .removed, oldLineNumber: oldIdx + 1, newLineNumber: nil, text: "- \(o)"))
                removed += 1
                oldIdx += 1
            } else {
                let n = newLines[newIdx]
                diffs.append(DiffLine(id: lineId, kind: .added, oldLineNumber: nil, newLineNumber: newIdx + 1, text: "+ \(n)"))
                added += 1
                newIdx += 1
            }
            lineId += 1
        }

        return (diffs, added, removed, modified)
    }
}
