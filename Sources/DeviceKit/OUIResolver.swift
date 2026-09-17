import Foundation

/// Fast offline Organizationally Unique Identifier (OUI) MAC prefix resolver.
/// Contains comprehensive enterprise network vendors, cloud hypervisors, server manufacturers,
/// consumer devices, IoT chips, and IEEE 802 Locally Administered (Private Wi-Fi) detection.
public enum OUIResolver {

    /// Checks if a MAC address is an IEEE 802 Locally Administered Address (Private / Randomized MAC).
    /// In IEEE 802 MACs, if bit 1 of the first octet is set (0b00000010), the address is locally assigned.
    public static func isLocallyAdministered(mac: String) -> Bool {
        let cleaned = mac
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
        guard cleaned.count >= 2, let firstByte = UInt8(cleaned.prefix(2), radix: 16) else {
            return false
        }
        return (firstByte & 0x02) != 0
    }

    /// Resolves a MAC address (e.g. `00:1c:73:a1:b2:c3` or `0-1c-73-a1-b2-c3`) to its hardware vendor name.
    public static func lookup(mac: String) -> String? {
        resolve(mac: mac)
    }

    public static func resolve(mac: String) -> String? {
        let cleaned = mac
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .uppercased()

        guard cleaned.count >= 6 else { return nil }

        // 1. Check for Multicast or Broadcast
        if cleaned.hasPrefix("01005E") { return "IPv4 Multicast" }
        if cleaned.hasPrefix("3333") { return "IPv6 Multicast" }
        if cleaned.hasPrefix("0180C2") { return "Spanning Tree / LLDP Multicast" }
        if cleaned == "FFFFFFFFFFFF" { return "Broadcast" }

        // 2. Exact OUI Lookup
        let prefix = String(cleaned.prefix(6))
        if let vendor = ouiTable[prefix] {
            return vendor
        }

        // 3. Check for IEEE Locally Administered / Randomized Private MAC (iOS / macOS / Android Private Wi-Fi)
        if isLocallyAdministered(mac: mac) {
            return "Private MAC (Locally Administered)"
        }

        return nil
    }

    /// Infers a `DeviceVendor` enum from a MAC address.
    public static func inferVendor(mac: String) -> DeviceVendor {
        guard let name = resolve(mac: mac) else {
            return isLocallyAdministered(mac: mac) ? .apple : .generic
        }
        return inferVendor(fromName: name)
    }

    /// Infers a `DeviceVendor` enum from a raw vendor name string.
    public static func inferVendor(fromName name: String) -> DeviceVendor {
        let lower = name.lowercased()
        if lower.contains("cisco") || lower.contains("meraki") { return .cisco }
        if lower.contains("arista") { return .arista }
        if lower.contains("juniper") || lower.contains("mist") { return .juniper }
        if lower.contains("apple") { return .apple }
        if lower.contains("ubiquiti") || lower.contains("unifi") { return .ubiquiti }
        if lower.contains("mikrotik") { return .mikrotik }
        if lower.contains("fortinet") || lower.contains("fortigate") { return .fortinet }
        if lower.contains("vmware") { return .vmware }
        if lower.contains("raspberry") { return .raspberryPi }
        if lower.contains("intel") { return .intel }
        if lower.contains("linksys") { return .linksys }
        if lower.contains("belkin") { return lower.contains("linksys") ? .linksys : .belkin }
        if lower.contains("netgear") { return .netgear }
        if lower.contains("tp-link") || lower.contains("tplink") { return .tpLink }
        if lower.contains("asus") || lower.contains("asustek") { return .asus }
        if lower.contains("synology") { return .synology }
        if lower.contains("d-link") || lower.contains("dlink") { return .dlink }
        if lower.contains("palo alto") || lower.contains("pan-os") { return .paloAlto }
        if lower.contains("huawei") { return .huawei }
        if lower.contains("dell") || lower.contains("super micro") { return .dell }
        if lower.contains("hewlett packard") || lower.contains("hp inc") || lower.contains("aruba") || lower.contains("hpe") { return .hpe }
        if lower.contains("amazon") || lower.contains("eero") || lower.contains("ring") { return .amazon }
        if lower.contains("google") || lower.contains("nest") { return .google }
        if lower.contains("arris") || lower.contains("motorola") { return .arris }
        if lower.contains("avm") || lower.contains("fritz") { return .avm }
        if lower.contains("zyxel") { return .zyxel }
        if lower.contains("linux") { return .linux }

        return DeviceVendor(rawValue: name) ?? .generic
    }

    // MARK: - Comprehensive IEEE OUI Prefix Database (2,500+ Official Allocations)
    public static var ouiTable: [String: String] {
        OUIDatabase.table
    }
}

