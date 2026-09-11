import Foundation

/// Analyzes arbitrary raw user input and automatically classifies it into a typed `NetworkTarget`.
public struct TargetClassifier: Sendable {
    public init() {}

    public static func classify(_ input: String) -> NetworkTarget? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Check for URL schemes (http://, https://)
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            if let url = URL(string: trimmed), url.host != nil {
                return .url(url)
            }
        }

        // 2. Check for Subnet/CIDR (contains '/')
        if trimmed.contains("/") {
            if let net = IPNetwork(trimmed) {
                return .subnet(net)
            }
        }

        // 3. Check for IPv4 Address
        if let v4 = IPAddress.IPv4(trimmed) {
            return .ipv4(v4)
        }

        // 4. Check for IPv6 Address
        if let v6 = IPAddress.IPv6(trimmed) {
            return .ipv6(v6)
        }

        // 5. Check if it looks like a URL without scheme (e.g. "api.example.com/v1/health")
        if trimmed.contains("/") && !trimmed.contains(" ") {
            if let url = URL(string: "https://" + trimmed), url.host != nil {
                return .url(url)
            }
        }

        // 6. Check for Hostname / FQDN (contains dots, valid domain characters)
        let domainRegex = "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"
        if let _ = trimmed.range(of: domainRegex, options: .regularExpression), trimmed.contains(".") {
            return .hostname(trimmed)
        }

        // 7. Single word / local hostname or device name (e.g., "core-sw01", "gw01", "localhost")
        let deviceRegex = "^[a-zA-Z0-9-_]+$"
        if let _ = trimmed.range(of: deviceRegex, options: .regularExpression) {
            if trimmed.lowercased() == "localhost" {
                return .hostname(trimmed)
            }
            return .device(trimmed)
        }

        // Fallback to hostname if it contains no spaces
        if !trimmed.contains(" ") {
            return .hostname(trimmed)
        }

        return nil
    }
}
