import Foundation

public final class MIBNode: @unchecked Sendable {
    public let segment: UInt32
    public var name: String?
    public var syntax: String?
    public var description: String?
    public var children: [UInt32: MIBNode] = [:]

    public init(segment: UInt32, name: String? = nil, syntax: String? = nil, description: String? = nil) {
        self.segment = segment
        self.name = name
        self.syntax = syntax
        self.description = description
    }
}

/// High-performance Prefix Trie for MIB OID hierarchy and nearest parent resolution.
public final class OIDTrie: @unchecked Sendable {
    private let root = MIBNode(segment: 0)
    private let lock = NSLock()

    public init() {}

    public func insert(oid: String, name: String, syntax: String? = nil, description: String? = nil) {
        lock.lock()
        defer { lock.unlock() }

        let clean = oid.hasPrefix(".") ? String(oid.dropFirst()) : oid
        let segments = clean.split(separator: ".").compactMap { UInt32($0) }
        guard !segments.isEmpty else { return }

        var current = root
        for seg in segments {
            if let next = current.children[seg] {
                current = next
            } else {
                let newNode = MIBNode(segment: seg)
                current.children[seg] = newNode
                current = newNode
            }
        }
        current.name = name
        current.syntax = syntax
        current.description = description
    }

    public func lookup(oid: String) -> MIBNode? {
        lock.lock()
        defer { lock.unlock() }

        let clean = oid.hasPrefix(".") ? String(oid.dropFirst()) : oid
        let segments = clean.split(separator: ".").compactMap { UInt32($0) }

        var current = root
        for seg in segments {
            guard let next = current.children[seg] else { return nil }
            current = next
        }
        return current
    }

    /// Resolves an OID (e.g. `1.3.6.1.2.1.1.1.0`) to a human-readable symbolic string (e.g. `sysDescr.0`).
    public func resolveName(oid: String) -> String {
        lock.lock()
        defer { lock.unlock() }

        let clean = oid.hasPrefix(".") ? String(oid.dropFirst()) : oid
        let segments = clean.split(separator: ".").compactMap { UInt32($0) }

        var current = root
        var lastNamedNode: MIBNode? = nil
        var lastNamedIndex = -1

        for (idx, seg) in segments.enumerated() {
            guard let next = current.children[seg] else { break }
            current = next
            if current.name != nil {
                lastNamedNode = current
                lastNamedIndex = idx
            }
        }

        if let named = lastNamedNode, let name = named.name {
            if lastNamedIndex == segments.count - 1 {
                return name
            } else {
                let remainder = segments[(lastNamedIndex + 1)...].map(String.init).joined(separator: ".")
                return "\(name).\(remainder)"
            }
        }

        return oid
    }

    /// Recursively collects all named child nodes underneath a prefix.
    public func allChildren(prefix: String) -> [(oid: String, name: String, syntax: String?)] {
        lock.lock()
        defer { lock.unlock() }

        let clean = prefix.hasPrefix(".") ? String(prefix.dropFirst()) : prefix
        let segments = clean.split(separator: ".").compactMap { UInt32($0) }

        var current = root
        for seg in segments {
            guard let next = current.children[seg] else { return [] }
            current = next
        }

        var results: [(oid: String, name: String, syntax: String?)] = []
        collect(node: current, currentOID: clean, results: &results)
        return results
    }

    private func collect(node: MIBNode, currentOID: String, results: inout [(oid: String, name: String, syntax: String?)]) {
        if let name = node.name {
            results.append((oid: currentOID, name: name, syntax: node.syntax))
        }
        for (seg, child) in node.children.sorted(by: { $0.key < $1.key }) {
            let nextOID = "\(currentOID).\(seg)"
            collect(node: child, currentOID: nextOID, results: &results)
        }
    }
}
