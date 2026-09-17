import Foundation
import os

/// Fast, comprehensive Organizationally Unique Identifier (OUI) MAC prefix resolver.
/// Contains the complete official IEEE Standards Association OUI Registry (53,940+ official allocations
/// across MA-L 24-bit, MA-M 28-bit, and MA-S 36-bit), plus IEEE 802 Locally Administered (Private Wi-Fi) detection,
/// thread-safe dynamic in-memory caching, and asynchronous live online fallback lookup.
public enum OUIResolver {

    private static let dynamicCache = OSAllocatedUnfairLock(initialState: [String: String]())

    // MARK: - MAC Normalization & Sanitization

    /// Normalizes any raw MAC address representation into canonical 2-digit uppercase hex octets separated by colons (e.g. `00:1C:C2:79:17:7B`).
    /// Corrects Darwin ARP and NDP single-digit hex octets (e.g. `0:1c:c2:79:17:7b` -> `00:1C:C2:79:17:7B`).
    /// Also supports Cisco 3-group format (`001c.73a1.b2c3`) and hyphen-delimited formats (`00-1C-C2-79-17-7B`).
    public static func normalizeMAC(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if trimmed.contains(":") || trimmed.contains("-") {
            let delimiter: Character = trimmed.contains(":") ? ":" : "-"
            let tokens = trimmed.split(separator: delimiter)
            let padded = tokens.map { token -> String in
                let s = String(token).trimmingCharacters(in: .whitespaces)
                return s.count == 1 ? "0" + s : s
            }
            return padded.joined(separator: ":").lowercased()
        } else if trimmed.contains(".") {
            let groups = trimmed.split(separator: ".")
            var octets: [String] = []
            for group in groups {
                let s = String(group).trimmingCharacters(in: .whitespaces)
                let padded = String(repeating: "0", count: max(0, 4 - s.count)) + s
                if padded.count == 4 {
                    let first = String(padded.prefix(2))
                    let second = String(padded.suffix(2))
                    octets.append(first)
                    octets.append(second)
                }
            }
            if octets.count == 6 {
                return octets.joined(separator: ":").lowercased()
            }
        }

        // Fallback: contiguous hex string
        let cleaned = trimmed.filter { $0.isHexDigit }.lowercased()
        if cleaned.count == 12 {
            var octets: [String] = []
            for i in stride(from: 0, to: 12, by: 2) {
                let start = cleaned.index(cleaned.startIndex, offsetBy: i)
                let end = cleaned.index(start, offsetBy: 2)
                octets.append(String(cleaned[start..<end]))
            }
            return octets.joined(separator: ":")
        }
        return trimmed.lowercased()
    }

    /// Strips all punctuation and returns a clean, contiguous uppercase hex string (e.g. `001CC279177B`).
    public static func cleanHexMAC(_ raw: String) -> String {
        let normalized = normalizeMAC(raw)
        return normalized.replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .uppercased()
    }

    // MARK: - IEEE 802 Locally Administered / Private Wi-Fi Detection

    /// Checks if a MAC address is an IEEE 802 Locally Administered Address (Private / Randomized MAC).
    /// In IEEE 802 MACs, if bit 1 of the first octet is set (0b00000010) and bit 0 is cleared (unicast),
    /// the address is locally assigned (used by Apple Private Wi-Fi, Android MAC randomization, Windows 10/11 random MAC).
    public static func isLocallyAdministered(mac: String) -> Bool {
        let clean = cleanHexMAC(mac)
        guard clean.count >= 2, let firstByte = UInt8(clean.prefix(2), radix: 16) else {
            return false
        }
        return (firstByte & 0x02) != 0 && (firstByte & 0x01) == 0
    }

    // MARK: - Synchronous Resolution

    /// Resolves a MAC address to its hardware vendor name using the local 53,940+ IEEE registry and dynamic cache.
    public static func lookup(mac: String) -> String? {
        resolve(mac: mac)
    }

    public static func resolve(mac: String) -> String? {
        let clean = cleanHexMAC(mac)
        guard clean.count >= 6 else { return nil }

        // 1. Multicast & Broadcast Addresses
        if clean == "FFFFFFFFFFFF" { return "Broadcast" }
        if clean.hasPrefix("01005E") { return "IPv4 Multicast" }
        if clean.hasPrefix("3333") { return "IPv6 Multicast" }
        if clean.hasPrefix("0180C2") { return "Spanning Tree / LLDP Multicast" }

        // 2. Exact OUI Lookup across MA-S (36-bit), MA-M (28-bit), and MA-L (24-bit)
        if clean.count >= 9 {
            let prefix9 = String(clean.prefix(9))
            if let vendor = ouiTable[prefix9] {
                return vendor
            }
        }
        if clean.count >= 7 {
            let prefix7 = String(clean.prefix(7))
            if let vendor = ouiTable[prefix7] {
                return vendor
            }
        }
        let prefix6 = String(clean.prefix(6))
        if let vendor = ouiTable[prefix6] {
            return vendor
        }

        // 3. Check Dynamic In-Memory / Online Cache
        if let cached = dynamicCache.withLock({ $0[prefix6] }) {
            return cached.isEmpty ? nil : cached
        }

        // 4. Check for IEEE Locally Administered / Randomized Private MAC (iOS / macOS / Android Private Wi-Fi)
        if isLocallyAdministered(mac: mac) {
            return "Private MAC (Locally Administered)"
        }

        return nil
    }

    // MARK: - Asynchronous Live Online Fallback Lookup

    /// Resolves a MAC address asynchronously with live online fallback to public IEEE/vendor databases if not found locally.
    public static func resolveAsync(mac: String) async -> String? {
        // First attempt immediate local resolution
        if let immediate = resolve(mac: mac) {
            return immediate
        }

        // Do not query internet for private randomized addresses
        if isLocallyAdministered(mac: mac) {
            return "Private MAC (Locally Administered)"
        }

        let clean = cleanHexMAC(mac)
        guard clean.count >= 6 else { return nil }
        let prefix = String(clean.prefix(6))

        // Check if already queried
        if let cached = dynamicCache.withLock({ $0[prefix] }) {
            return cached.isEmpty ? nil : cached
        }

        // Asynchronously query public vendor API
        guard let url = URL(string: "https://api.maclookup.app/v2/macs/\(prefix)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.5
        request.setValue("NexWave-Workbench/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                dynamicCache.withLock { $0[prefix] = "" }
                return nil
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let company = json["company"] as? String, !company.isEmpty {
                dynamicCache.withLock { $0[prefix] = company }
                return company
            }
        } catch {
            dynamicCache.withLock { $0[prefix] = "" }
        }

        return nil
    }

    // MARK: - Vendor Inference

    /// Infers a `DeviceVendor` enum from a MAC address.
    public static func inferVendor(mac: String) -> DeviceVendor {
        if isLocallyAdministered(mac: mac) {
            return .apple
        }
        guard let name = resolve(mac: mac) else {
            return .generic
        }
        return inferVendor(fromName: name)
    }

    /// Infers a `DeviceVendor` enum from a raw vendor name string.
    public static func inferVendor(fromName name: String) -> DeviceVendor {
        let lower = name.lowercased()
        if lower.contains("linksys") { return .linksys }
        if lower.contains("belkin") { return .belkin }
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
        if lower.contains("samsung") { return .samsung }
        if lower.contains("sony") || lower.contains("playstation") { return .sony }
        if lower.contains("espressif") || lower.contains("esp32") || lower.contains("esp8266") { return .espressif }
        if lower.contains("realtek") { return .realtek }
        if lower.contains("lenovo") || lower.contains("thinkpad") { return .lenovo }
        if lower.contains("xiaomi") { return .xiaomi }
        if lower.contains("microsoft") || lower.contains("surface") || lower.contains("xbox") { return .microsoft }
        if lower.contains("brother") { return .brother }
        if lower.contains("canon") { return .canon }
        if lower.contains("roku") { return .roku }
        if lower.contains("sonos") { return .sonos }
        if lower.contains("lg electronics") || lower.contains("lg display") || lower.hasPrefix("lg ") { return .lg }
        if lower.contains("tuya") { return .tuya }
        if lower.contains("philips") || lower.contains("signify") { return .philips }
        if lower.contains("qnap") { return .qnap }
        if lower.contains("linux") { return .linux }

        return DeviceVendor(rawValue: name) ?? .generic
    }

    // MARK: - Comprehensive IEEE OUI Prefix Database (53,940+ Official Allocations)
    public static var ouiTable: [String: String] {
        OUIDatabase.table
    }
}

