import Foundation

public enum FilterValidationStatus: Equatable, Sendable {
    case empty
    case valid(summary: String)
    case invalid(error: String)
}

public enum FilterOp: String, Sendable {
    case equal = "=="
    case notEqual = "!="
    case greaterThan = ">"
    case greaterThanOrEqual = ">="
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case contains = "contains"
}

public indirect enum FilterExpression: Sendable {
    case protocolMatch(PacketProtocol)
    case fieldMatch(field: String, op: FilterOp, value: String)
    case anomalyOnly
    case and(FilterExpression, FilterExpression)
    case or(FilterExpression, FilterExpression)
    case not(FilterExpression)
}

public struct PacketDisplayFilter: Sendable {
    public let rawQuery: String
    private let rootExpression: FilterExpression?

    public init(query: String) {
        self.rawQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.rawQuery.isEmpty {
            self.rootExpression = nil
        } else {
            self.rootExpression = try? PacketDisplayFilter.compile(rawQuery: self.rawQuery)
        }
    }

    public static func validate(query: String) -> FilterValidationStatus {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }

        do {
            let expr = try compile(rawQuery: trimmed)
            return .valid(summary: "Valid filter syntax: \(summarize(expr))")
        } catch {
            return .invalid(error: error.localizedDescription)
        }
    }

    public func matches(packet: PacketRecord) -> Bool {
        guard let expr = rootExpression else { return true }
        return evaluate(expr: expr, packet: packet)
    }

    private func evaluate(expr: FilterExpression, packet: PacketRecord) -> Bool {
        switch expr {
        case .protocolMatch(let targetProto):
            return packet.protocolType == targetProto

        case .anomalyOnly:
            return !packet.anomalies.isEmpty

        case .and(let left, let right):
            return evaluate(expr: left, packet: packet) && evaluate(expr: right, packet: packet)

        case .or(let left, let right):
            return evaluate(expr: left, packet: packet) || evaluate(expr: right, packet: packet)

        case .not(let child):
            return !evaluate(expr: child, packet: packet)

        case .fieldMatch(let field, let op, let value):
            return matchField(field: field.lowercased(), op: op, value: value, packet: packet)
        }
    }

    private func matchField(field: String, op: FilterOp, value: String, packet: PacketRecord) -> Bool {
        switch field {
        case "ip.src", "ip.source":
            return compareString(packet.sourceAddress, op: op, target: value)

        case "ip.dst", "ip.destination":
            return compareString(packet.destinationAddress, op: op, target: value)

        case "ip.addr":
            if op == .equal || op == .contains {
                return packet.sourceAddress == value || packet.destinationAddress == value
            } else if op == .notEqual {
                return packet.sourceAddress != value && packet.destinationAddress != value
            }
            return false

        case "tcp.port", "udp.port", "port":
            guard let intVal = Int(value) else { return false }
            let sp = packet.sourcePort ?? -1
            let dp = packet.destinationPort ?? -1
            if op == .equal {
                return sp == intVal || dp == intVal
            } else if op == .notEqual {
                return sp != intVal && dp != intVal
            }
            return false

        case "tcp.srcport", "udp.srcport":
            guard let intVal = Int(value), let sp = packet.sourcePort else { return false }
            return compareInt(sp, op: op, target: intVal)

        case "tcp.dstport", "udp.dstport":
            guard let intVal = Int(value), let dp = packet.destinationPort else { return false }
            return compareInt(dp, op: op, target: intVal)

        case "frame.len", "length", "len":
            guard let intVal = Int(value) else { return false }
            return compareInt(packet.wireLength, op: op, target: intVal)

        case "tcp.flags.syn":
            let hasSyn = packet.tcpFlags?.contains(.syn) == true
            return value == "1" ? hasSyn : !hasSyn

        case "tcp.flags.reset", "tcp.flags.rst":
            let hasRst = packet.tcpFlags?.contains(.rst) == true
            return value == "1" ? hasRst : !hasRst

        case "tcp.flags.ack":
            let hasAck = packet.tcpFlags?.contains(.ack) == true
            return value == "1" ? hasAck : !hasAck

        case "tcp.flags.fin":
            let hasFin = packet.tcpFlags?.contains(.fin) == true
            return value == "1" ? hasFin : !hasFin

        case "frame", "info", "summary":
            return packet.summary.localizedCaseInsensitiveContains(value)

        default:
            // Generic check against packet summary or addresses
            return packet.summary.localizedCaseInsensitiveContains(value) ||
                   packet.sourceAddress.contains(value) ||
                   packet.destinationAddress.contains(value)
        }
    }

    private func compareString(_ actual: String, op: FilterOp, target: String) -> Bool {
        switch op {
        case .equal: return actual.lowercased() == target.lowercased()
        case .notEqual: return actual.lowercased() != target.lowercased()
        case .contains: return actual.localizedCaseInsensitiveContains(target)
        default: return false
        }
    }

    private func compareInt(_ actual: Int, op: FilterOp, target: Int) -> Bool {
        switch op {
        case .equal: return actual == target
        case .notEqual: return actual != target
        case .greaterThan: return actual > target
        case .greaterThanOrEqual: return actual >= target
        case .lessThan: return actual < target
        case .lessThanOrEqual: return actual <= target
        case .contains: return false
        }
    }

    // MARK: - Compiler / Lexer
    private static func compile(rawQuery: String) throws -> FilterExpression {
        // Tokenize
        let tokens = tokenize(rawQuery)
        guard !tokens.isEmpty else {
            throw NSError(domain: "FilterCompiler", code: 400, userInfo: [NSLocalizedDescriptionKey: "Empty expression"])
        }

        var index = 0
        let expr = try parseOrExpression(tokens: tokens, index: &index)
        if index < tokens.count {
            throw NSError(domain: "FilterCompiler", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unexpected token '\(tokens[index])' after expression"])
        }
        return expr
    }

    private static func tokenize(_ str: String) -> [String] {
        var tokens: [String] = []
        var cur = ""

        func flush() {
            let t = cur.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { tokens.append(t) }
            cur = ""
        }

        var i = str.startIndex
        while i < str.endIndex {
            let c = str[i]
            if c == "(" || c == ")" {
                flush()
                tokens.append(String(c))
                i = str.index(after: i)
            } else if c == " " || c == "\t" {
                flush()
                i = str.index(after: i)
            } else if c == "=" || c == "!" || c == ">" || c == "<" {
                flush()
                var op = String(c)
                let next = str.index(after: i)
                if next < str.endIndex && str[next] == "=" {
                    op.append("=")
                    i = next
                }
                tokens.append(op)
                i = str.index(after: i)
            } else if c == "&" || c == "|" {
                let next = str.index(after: i)
                if next < str.endIndex && str[next] == c {
                    flush()
                    tokens.append(String(c) + String(c))
                    i = str.index(after: next)
                } else {
                    cur.append(c)
                    i = str.index(after: i)
                }
            } else {
                cur.append(c)
                i = str.index(after: i)
            }
        }
        flush()
        return tokens
    }

    private static func parseOrExpression(tokens: [String], index: inout Int) throws -> FilterExpression {
        var left = try parseAndExpression(tokens: tokens, index: &index)

        while index < tokens.count {
            let token = tokens[index].lowercased()
            if token == "or" || token == "||" {
                index += 1
                let right = try parseAndExpression(tokens: tokens, index: &index)
                left = .or(left, right)
            } else {
                break
            }
        }
        return left
    }

    private static func parseAndExpression(tokens: [String], index: inout Int) throws -> FilterExpression {
        var left = try parsePrimaryExpression(tokens: tokens, index: &index)

        while index < tokens.count {
            let token = tokens[index].lowercased()
            if token == "and" || token == "&&" {
                index += 1
                let right = try parsePrimaryExpression(tokens: tokens, index: &index)
                left = .and(left, right)
            } else if token != "or" && token != "||" && token != ")" {
                // Implicit AND if adjacent
                let right = try parsePrimaryExpression(tokens: tokens, index: &index)
                left = .and(left, right)
            } else {
                break
            }
        }
        return left
    }

    private static func parsePrimaryExpression(tokens: [String], index: inout Int) throws -> FilterExpression {
        guard index < tokens.count else {
            throw NSError(domain: "FilterCompiler", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unexpected end of filter expression"])
        }

        let token = tokens[index]

        // Parentheses
        if token == "(" {
            index += 1
            let inside = try parseOrExpression(tokens: tokens, index: &index)
            guard index < tokens.count && tokens[index] == ")" else {
                throw NSError(domain: "FilterCompiler", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing closing parenthesis ')'"])
            }
            index += 1
            return inside
        }

        // NOT operator
        if token.lowercased() == "not" || token == "!" {
            index += 1
            let inner = try parsePrimaryExpression(tokens: tokens, index: &index)
            return .not(inner)
        }

        // Check if standalone protocol token
        let lower = token.lowercased()
        if let proto = parseProtocolName(lower) {
            index += 1
            return .protocolMatch(proto)
        }

        if lower == "anomaly" || lower == "anomalies" || lower == "tcp.anomaly" || lower == "tcp.anomalies" || lower == "tcp.analysis.flags" {
            index += 1
            return .anomalyOnly
        }

        // Otherwise field comparison: <field> <op> <value>
        let field = token
        index += 1

        guard index < tokens.count else {
            // Free-standing keyword match
            return .fieldMatch(field: "summary", op: .contains, value: field)
        }

        let opToken = tokens[index]
        if let op = parseOperator(opToken) {
            index += 1
            guard index < tokens.count else {
                throw NSError(domain: "FilterCompiler", code: 400, userInfo: [NSLocalizedDescriptionKey: "Expected value after operator '\(opToken)'"])
            }
            let val = tokens[index].replacingOccurrences(of: "\"", with: "")
            index += 1
            return .fieldMatch(field: field, op: op, value: val)
        } else {
            // Treat as keyword match
            return .fieldMatch(field: "summary", op: .contains, value: field)
        }
    }

    private static func parseOperator(_ token: String) -> FilterOp? {
        switch token {
        case "==", "eq": return .equal
        case "!=", "ne": return .notEqual
        case ">", "gt": return .greaterThan
        case ">=", "ge": return .greaterThanOrEqual
        case "<", "lt": return .lessThan
        case "<=", "le": return .lessThanOrEqual
        case "contains", "~=": return .contains
        default: return nil
        }
    }

    private static func parseProtocolName(_ token: String) -> PacketProtocol? {
        switch token {
        case "tcp": return .tcp
        case "udp": return .udp
        case "icmp": return .icmp
        case "icmpv6": return .icmpv6
        case "dns": return .dns
        case "tls", "ssl": return .tls
        case "http": return .http
        case "arp": return .arp
        case "dhcp", "bootp": return .dhcp
        case "bgp": return .bgp
        case "ospf": return .ospf
        case "ntp": return .ntp
        case "snmp": return .snmp
        default: return nil
        }
    }

    private static func summarize(_ expr: FilterExpression) -> String {
        switch expr {
        case .protocolMatch(let p): return p.description
        case .anomalyOnly: return "TCP Anomalies"
        case .fieldMatch(let f, let op, let v): return "\(f) \(op.rawValue) \(v)"
        case .and(let a, let b): return "\(summarize(a)) AND \(summarize(b))"
        case .or(let a, let b): return "\(summarize(a)) OR \(summarize(b))"
        case .not(let a): return "NOT (\(summarize(a)))"
        }
    }
}
