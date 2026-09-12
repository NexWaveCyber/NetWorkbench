import Foundation
import NetworkCore

public struct PacketFlow: Sendable {
    public let srcIP: String
    public let dstIP: String
    public let protocolType: ACLProtocol
    public let srcPort: UInt16?
    public let dstPort: UInt16?
    public let isEstablished: Bool

    public init(
        srcIP: String,
        dstIP: String,
        protocolType: ACLProtocol = .tcp,
        srcPort: UInt16? = nil,
        dstPort: UInt16? = nil,
        isEstablished: Bool = false
    ) {
        self.srcIP = srcIP
        self.dstIP = dstIP
        self.protocolType = protocolType
        self.srcPort = srcPort
        self.dstPort = dstPort
        self.isEstablished = isEstablished
    }
}

public struct FlowEvaluationResult: Sendable {
    public let action: ACLAction
    public let matchedRule: ACLRule?
    public let reason: String
    public let evaluatedRuleCount: Int

    public init(
        action: ACLAction,
        matchedRule: ACLRule?,
        reason: String,
        evaluatedRuleCount: Int
    ) {
        self.action = action
        self.matchedRule = matchedRule
        self.reason = reason
        self.evaluatedRuleCount = evaluatedRuleCount
    }
}

public enum ShadowKind: String, Sendable, Codable {
    case shadowed = "Shadowed (Dead Rule)"
    case redundant = "Redundant (Duplicate Action)"
}

public struct ShadowedRuleFinding: Identifiable, Sendable {
    public var id: String { "\(flaggedRule.sequence)-\(shadowedByRule.sequence)" }
    public let flaggedRule: ACLRule
    public let shadowedByRule: ACLRule
    public let kind: ShadowKind
    public let explanation: String

    public init(
        flaggedRule: ACLRule,
        shadowedByRule: ACLRule,
        kind: ShadowKind,
        explanation: String
    ) {
        self.flaggedRule = flaggedRule
        self.shadowedByRule = shadowedByRule
        self.kind = kind
        self.explanation = explanation
    }
}

public struct ACLAnalyzer: Sendable {
    public init() {}

    // MARK: - Flow Simulation

    public func evaluate(flow: PacketFlow, against acl: ACLConfig) -> FlowEvaluationResult {
        var evaluatedCount = 0

        for rule in acl.rules {
            evaluatedCount += 1

            if matches(flow: flow, rule: rule) {
                return FlowEvaluationResult(
                    action: rule.action,
                    matchedRule: rule,
                    reason: "Matched sequence \(rule.sequence): '\(rule.rawText)'",
                    evaluatedRuleCount: evaluatedCount
                )
            }
        }

        // Implicit Deny
        return FlowEvaluationResult(
            action: .deny,
            matchedRule: nil,
            reason: "Packet hit implicit 'deny ip any any' at end of ACL",
            evaluatedRuleCount: evaluatedCount
        )
    }

    private func matches(flow: PacketFlow, rule: ACLRule) -> Bool {
        // 1. Protocol Match
        if rule.protocolType != .any && rule.protocolType != .ip {
            if rule.protocolType != flow.protocolType {
                return false
            }
        }

        // 1b. Established flag match
        if rule.isEstablished && !flow.isEstablished {
            return false
        }

        // 2. Source Match
        if !matchNetwork(ipString: flow.srcIP, match: rule.source) {
            return false
        }

        // 3. Destination Match
        if !matchNetwork(ipString: flow.dstIP, match: rule.destination) {
            return false
        }

        // 4. Port Match
        if let portOp = rule.portOperator {
            guard let dstPort = flow.dstPort else { return false }
            if !portOp.matches(port: dstPort) {
                return false
            }
        }

        return true
    }

    private func matchNetwork(ipString: String, match: NetworkMatch) -> Bool {
        switch match {
        case .any:
            return true
        case .host(let hostIP):
            return ipString == hostIP
        case .subnet(let net, let wildcard):
            guard let ipInt = ipv4ToUInt32(ipString),
                  let netInt = ipv4ToUInt32(net),
                  let wildInt = ipv4ToUInt32(wildcard) else {
                return false
            }
            let mask = ~wildInt
            return (ipInt & mask) == (netInt & mask)
        }
    }

    private func ipv4ToUInt32(_ str: String) -> UInt32? {
        let parts = str.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    // MARK: - Shadow & Redundancy Detection

    public func detectShadowedRules(in acl: ACLConfig) -> [ShadowedRuleFinding] {
        var findings: [ShadowedRuleFinding] = []

        let rules = acl.rules
        for i in 0..<rules.count {
            let earlierRule = rules[i]

            for j in (i + 1)..<rules.count {
                let laterRule = rules[j]

                if isSuperset(earlier: earlierRule, later: laterRule) {
                    if earlierRule.action == laterRule.action {
                        findings.append(ShadowedRuleFinding(
                            flaggedRule: laterRule,
                            shadowedByRule: earlierRule,
                            kind: .redundant,
                            explanation: "Rule \(laterRule.sequence) action '\(laterRule.action.rawValue)' is redundant. All matching traffic is already handled by rule \(earlierRule.sequence)."
                        ))
                    } else {
                        findings.append(ShadowedRuleFinding(
                            flaggedRule: laterRule,
                            shadowedByRule: earlierRule,
                            kind: .shadowed,
                            explanation: "Rule \(laterRule.sequence) will NEVER be reached! Broad earlier rule \(earlierRule.sequence) ('\(earlierRule.action.rawValue)') intercepts all traffic first."
                        ))
                    }
                }
            }
        }

        return findings
    }

    private func isSuperset(earlier: ACLRule, later: ACLRule) -> Bool {
        // Protocol superset
        if earlier.protocolType != .any && earlier.protocolType != .ip {
            if earlier.protocolType != later.protocolType {
                return false
            }
        }

        // Established superset
        if earlier.isEstablished && !later.isEstablished {
            return false
        }

        // Source superset
        if !isNetworkSuperset(earlier: earlier.source, later: later.source) {
            return false
        }

        // Destination superset
        if !isNetworkSuperset(earlier: earlier.destination, later: later.destination) {
            return false
        }

        // Port superset
        if let earlierPort = earlier.portOperator {
            guard let laterPort = later.portOperator else { return false }
            if earlierPort != laterPort { return false }
        }

        return true
    }

    private func isNetworkSuperset(earlier: NetworkMatch, later: NetworkMatch) -> Bool {
        switch earlier {
        case .any:
            return true
        case .host(let h1):
            switch later {
            case .any: return false
            case .host(let h2): return h1 == h2
            case .subnet: return false
            }
        case .subnet(let net1, let wild1):
            switch later {
            case .any:
                return false
            case .host(let h2):
                guard let h2Int = ipv4ToUInt32(h2),
                      let net1Int = ipv4ToUInt32(net1),
                      let wild1Int = ipv4ToUInt32(wild1) else { return false }
                let mask1 = ~wild1Int
                return (h2Int & mask1) == (net1Int & mask1)
            case .subnet(let net2, let wild2):
                guard let n1 = ipv4ToUInt32(net1), let w1 = ipv4ToUInt32(wild1),
                      let n2 = ipv4ToUInt32(net2), let w2 = ipv4ToUInt32(wild2) else { return false }
                let m1 = ~w1
                let m2 = ~w2
                // earlier mask must be less specific or equal (m1 <= m2 in terms of 1-bits)
                if (m1 & m2) == m1 && (n2 & m1) == (n1 & m1) {
                    return true
                }
                return false
            }
        }
    }
}
