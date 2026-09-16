import Foundation

/// Fast offline Organizationally Unique Identifier (OUI) MAC prefix resolver.
public enum OUIResolver {
    private static let ouiTable: [String: String] = [
        // Cisco Systems
        "00000C": "Cisco Systems",
        "000142": "Cisco Systems",
        "000143": "Cisco Systems",
        "000163": "Cisco Systems",
        "000164": "Cisco Systems",
        "0001C7": "Cisco Systems",
        "0001C9": "Cisco Systems",
        "000216": "Cisco Systems",
        "000217": "Cisco Systems",
        "00024A": "Cisco Systems",
        "00027D": "Cisco Systems",
        "0002B9": "Cisco Systems",
        "0003E3": "Cisco Systems",
        "00044D": "Cisco Systems",
        "00059A": "Cisco Systems",
        "001007": "Cisco Systems",
        "001120": "Cisco Systems",
        "0014A8": "Cisco Systems",
        "001759": "Cisco Systems",
        "001D45": "Cisco Systems",
        "002414": "Cisco Systems",
        "002698": "Cisco Systems",
        "382056": "Cisco Systems",
        "F44F82": "Cisco Systems",

        // Arista Networks
        "001C73": "Arista Networks",
        "28993A": "Arista Networks",
        "444C0C": "Arista Networks",
        "7483C2": "Arista Networks",

        // Juniper Networks
        "0019E2": "Juniper Networks",
        "002688": "Juniper Networks",
        "5C5EAB": "Juniper Networks",
        "84B59C": "Juniper Networks",
        "F01C2D": "Juniper Networks",

        // Apple Inc.
        "0017F2": "Apple",
        "0019E3": "Apple",
        "001B63": "Apple",
        "001C42": "Apple",
        "001D4F": "Apple",
        "001E52": "Apple",
        "001F5B": "Apple",
        "0021E9": "Apple",
        "002241": "Apple",
        "002312": "Apple",
        "002332": "Apple",
        "00236C": "Apple",
        "002436": "Apple",
        "002500": "Apple",
        "00254B": "Apple",
        "002608": "Apple",
        "00264A": "Apple",
        "0026B0": "Apple",
        "3C0754": "Apple",
        "3C15C2": "Apple",
        "40A6D9": "Apple",
        "4860BC": "Apple",
        "600308": "Apple",
        "701124": "Apple",
        "784F43": "Apple",
        "A483E7": "Apple",
        "ACDE48": "Apple",
        "F8FFC2": "Apple",

        // Ubiquiti Networks
        "002722": "Ubiquiti Networks",
        "0418D6": "Ubiquiti Networks",
        "24A43C": "Ubiquiti Networks",
        "788A20": "Ubiquiti Networks",
        "B4FBE4": "Ubiquiti Networks",
        "FCECDA": "Ubiquiti Networks",

        // MikroTik
        "000C42": "MikroTik",
        "488F5A": "MikroTik",
        "64D154": "MikroTik",
        "CC2DE0": "MikroTik",
        "D4CA6D": "MikroTik",

        // Fortinet
        "00090F": "Fortinet",
        "085B0E": "Fortinet",
        "704C8C": "Fortinet",
        "906C2D": "Fortinet",

        // VMware
        "000569": "VMware",
        "000C29": "VMware",
        "001C14": "VMware",
        "005056": "VMware",

        // Raspberry Pi
        "28CDC1": "Raspberry Pi",
        "B827EB": "Raspberry Pi",
        "DCA632": "Raspberry Pi",
        "E45F01": "Raspberry Pi",

        // Intel Corporation
        "0002B3": "Intel Corporation",
        "000347": "Intel Corporation",
        "000423": "Intel Corporation",
        "000E0C": "Intel Corporation",
        "001302": "Intel Corporation",
        "0013E8": "Intel Corporation",
        "001500": "Intel Corporation",
        "001B21": "Intel Corporation",
        "001E67": "Intel Corporation",
        "A0369F": "Intel Corporation",

        // Dell
        "001422": "Dell",
        "00188B": "Dell",
        "0019B9": "Dell",
        "001A6B": "Dell",
        "180373": "Dell",

        // HP / Hewlett Packard Enterprise
        "0001E6": "Hewlett Packard Enterprise",
        "0002A5": "Hewlett Packard Enterprise",
        "000802": "Hewlett Packard Enterprise",
        "000B46": "Hewlett Packard Enterprise",
        "001185": "Hewlett Packard Enterprise",

        // VirtualBox / QEMU
        "080027": "Oracle VirtualBox",
        "525400": "QEMU / KVM Virtual NIC",

        // Aruba Networks / HPE
        "000B86": "Aruba Networks",
        "001A1E": "Aruba Networks",
        "00246C": "Aruba Networks",
        "20A6CD": "Aruba Networks",
        "40E3D6": "Aruba Networks",
        "94B40F": "Aruba Networks",
        "D8C7C8": "Aruba Networks",
        "F05C19": "Aruba Networks",

        // Cisco Meraki
        "00180A": "Cisco Meraki",
        "3456FE": "Cisco Meraki",
        "0C8DDB": "Cisco Meraki",
        "E0553D": "Cisco Meraki",

        // Ruckus Wireless (CommScope)
        "001D2D": "Ruckus Wireless",
        "002482": "Ruckus Wireless",
        "589396": "Ruckus Wireless",
        "8CEF80": "Ruckus Wireless",
        "C4108A": "Ruckus Wireless",

        // Amazon / eero
        "50F5DA": "eero",
        "B0A737": "eero",
        "44650D": "Amazon Technologies",
        "6837E9": "Amazon Technologies",

        // Netgear
        "00095B": "Netgear",
        "00146C": "Netgear",
        "001F33": "Netgear",
        "20E52A": "Netgear",
        "288088": "Netgear",
        "841B5E": "Netgear",

        // TP-Link
        "50C7BF": "TP-Link",
        "EC086B": "TP-Link",
        "6038E0": "TP-Link",
        "74DA38": "TP-Link",
        "984827": "TP-Link",

        // Google / Nest
        "001A11": "Google",
        "30FD38": "Google",
        "F4F5DB": "Google",
        "546009": "Google",

        // ASUS
        "001E8C": "ASUS",
        "04D9F5": "ASUS",
        "10BF48": "ASUS",
        "2C4D54": "ASUS",

        // Mist Systems (Juniper)
        "5C5B35": "Mist Systems"
    ]

    /// Resolves a MAC address (e.g. `00:1c:73:a1:b2:c3` or `0-1c-73-a1-b2-c3`) to its hardware vendor name.
    public static func resolve(mac: String) -> String? {
        let cleaned = mac
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .uppercased()

        guard cleaned.count >= 6 else { return nil }
        let prefix = String(cleaned.prefix(6))
        return ouiTable[prefix]
    }

    /// Infers a `DeviceVendor` enum from a MAC address.
    public static func inferVendor(mac: String) -> DeviceVendor {
        guard let name = resolve(mac: mac) else { return .generic }
        let lower = name.lowercased()
        if lower.contains("cisco") { return .cisco }
        if lower.contains("arista") { return .arista }
        if lower.contains("juniper") { return .juniper }
        if lower.contains("apple") { return .apple }
        if lower.contains("ubiquiti") { return .ubiquiti }
        if lower.contains("mikrotik") { return .mikrotik }
        if lower.contains("fortinet") { return .fortinet }
        return .generic
    }
}
