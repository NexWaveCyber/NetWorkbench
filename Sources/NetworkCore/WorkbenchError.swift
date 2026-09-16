import Foundation

/// Standardized error hierarchy for NexWave Network Workbench.
/// Implements `LocalizedError` with user-facing recovery guidance.
public enum WorkbenchError: LocalizedError, Sendable, CustomStringConvertible {
    case deviceUnreachable(target: String, reason: String)
    case authenticationFailed(protocolName: String, detail: String)
    case packetCaptureDenied(interface: String, detail: String)
    case invalidConfiguration(syntaxError: String, line: Int?)
    case persistenceFailure(detail: String)
    case bundleCorrupted(reason: String)
    case timeout(operation: String, timeoutSeconds: Double)

    public var description: String {
        errorDescription ?? "Unknown Workbench Error"
    }

    public var errorDescription: String? {
        switch self {
        case .deviceUnreachable(let target, let reason):
            return "Target '\(target)' is unreachable: \(reason)"
        case .authenticationFailed(let proto, let detail):
            return "\(proto) Authentication Failed: \(detail)"
        case .packetCaptureDenied(let iface, let detail):
            return "Packet capture failed on '\(iface)': \(detail)"
        case .invalidConfiguration(let err, let line):
            if let line = line {
                return "Syntax error at line \(line): \(err)"
            }
            return "Configuration syntax error: \(err)"
        case .persistenceFailure(let detail):
            return "Database persistence failure: \(detail)"
        case .bundleCorrupted(let reason):
            return "Investigation bundle is invalid or corrupted: \(reason)"
        case .timeout(let op, let seconds):
            return "Operation '\(op)' timed out after \(seconds)s"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .deviceUnreachable:
            return "Check default gateway routing, firewall rules, and interface link status."
        case .authenticationFailed(let proto, _):
            if proto.contains("SNMP") {
                return "Verify SNMP community string or v3 engineID, security level, and auth/priv keys."
            }
            return "Check Keychain credentials, username, and private key permissions."
        case .packetCaptureDenied:
            return "Ensure network interface is up and /dev/bpf permissions allow read access."
        case .invalidConfiguration:
            return "Inspect highlighted syntax lines against standard Cisco/Arista grammar."
        case .persistenceFailure:
            return "Verify disk space and permissions in application data directory."
        case .bundleCorrupted:
            return "Ensure the .nwi file was fully downloaded and has not been truncated."
        case .timeout:
            return "Increase request timeout parameter or verify path latency."
        }
    }
}
