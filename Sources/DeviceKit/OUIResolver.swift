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

    // MARK: - Comprehensive IEEE OUI Prefix Database (Hundreds of Top Vendors)
    private static let ouiTable: [String: String] = [
        // Cisco Systems & Meraki
        "00000C": "Cisco Systems", "000142": "Cisco Systems", "000143": "Cisco Systems",
        "000163": "Cisco Systems", "000164": "Cisco Systems", "0001C7": "Cisco Systems",
        "0001C9": "Cisco Systems", "000216": "Cisco Systems", "000217": "Cisco Systems",
        "00024A": "Cisco Systems", "00027D": "Cisco Systems", "0002B9": "Cisco Systems",
        "0003E3": "Cisco Systems", "00044D": "Cisco Systems", "00059A": "Cisco Systems",
        "001007": "Cisco Systems", "001120": "Cisco Systems", "0014A8": "Cisco Systems",
        "001759": "Cisco Systems", "001D45": "Cisco Systems", "002414": "Cisco Systems",
        "002698": "Cisco Systems", "382056": "Cisco Systems", "F44F82": "Cisco Systems",
        "00180A": "Cisco Meraki", "3456FE": "Cisco Meraki", "0C8DDB": "Cisco Meraki",
        "E0553D": "Cisco Meraki", "AC17C8": "Cisco Systems", "BC1665": "Cisco Systems",
        "CC46D6": "Cisco Systems", "DC7B94": "Cisco Systems", "E80462": "Cisco Systems",
        "F0F755": "Cisco Systems", "00500F": "Cisco Systems", "006009": "Cisco Systems",
        "0008E3": "Cisco Systems", "000A41": "Cisco Systems", "000BBE": "Cisco Systems",

        // Arista Networks
        "001C73": "Arista Networks", "28993A": "Arista Networks", "444C0C": "Arista Networks",
        "7483C2": "Arista Networks", "882A5E": "Arista Networks", "985D82": "Arista Networks",
        "A82B15": "Arista Networks", "BC9FE4": "Arista Networks", "C0D682": "Arista Networks",

        // Juniper Networks & Mist
        "0019E2": "Juniper Networks", "002688": "Juniper Networks", "5C5EAB": "Juniper Networks",
        "84B59C": "Juniper Networks", "F01C2D": "Juniper Networks", "5C5B35": "Mist Systems (Juniper)",
        "3C6104": "Juniper Networks", "544B8C": "Juniper Networks", "5C4527": "Juniper Networks",

        // Apple Inc.
        "0017F2": "Apple", "0019E3": "Apple", "001B63": "Apple", "001C42": "Apple",
        "001D4F": "Apple", "001E52": "Apple", "001F5B": "Apple", "0021E9": "Apple",
        "002241": "Apple", "002312": "Apple", "002332": "Apple", "00236C": "Apple",
        "002436": "Apple", "002500": "Apple", "00254B": "Apple", "002608": "Apple",
        "00264A": "Apple", "0026B0": "Apple", "3C0754": "Apple", "3C15C2": "Apple",
        "40A6D9": "Apple", "4860BC": "Apple", "600308": "Apple", "701124": "Apple",
        "784F43": "Apple", "A483E7": "Apple", "ACDE48": "Apple", "F8FFC2": "Apple",
        "1094BB": "Apple", "14109F": "Apple", "147DDA": "Apple", "1499E2": "Apple",
        "18AF61": "Apple", "18E728": "Apple", "1C1AC0": "Apple", "20768F": "Apple",
        "286A80": "Apple", "28CFE9": "Apple", "28ED6A": "Apple", "2CBE08": "Apple",
        "3035AD": "Apple", "341298": "Apple", "38F9D3": "Apple", "406C8F": "Apple",
        "442A60": "Apple", "48746E": "Apple", "4C3275": "Apple", "50BC96": "Apple",
        "54724F": "Apple", "5C969D": "Apple", "64200C": "Apple", "68AE20": "Apple",
        "6C4008": "Apple", "703A0E": "Apple", "748D08": "Apple", "787E61": "Apple",
        "7C6D62": "Apple", "804A14": "Apple", "843835": "Apple", "88665A": "Apple",
        "8C8590": "Apple", "907240": "Apple", "941625": "Apple", "9801A7": "Apple",
        "9C04EB": "Apple", "A0999B": "Apple", "A4C361": "Apple", "A85B78": "Apple",
        "AC87A3": "Apple", "B019C6": "Apple", "B418D1": "Apple", "B8098A": "Apple",
        "BC5436": "Apple", "C0847A": "Apple", "C4B301": "Apple", "C81EE7": "Apple",
        "CC29F5": "Apple", "D0817A": "Apple", "D49A20": "Apple", "D89695": "Apple",
        "DC2B61": "Apple", "E0ACCB": "Apple", "E498D6": "Apple", "E8802E": "Apple",
        "ECAD25": "Apple", "F01898": "Apple", "F40F24": "Apple", "F83880": "Apple",
        "FC253F": "Apple", "BC7E8B": "Apple", "74CC40": "Apple", "AC007A": "Apple",
        "681DEF": "Apple", "FC3497": "Apple", "CC115A": "Apple", "D0C24E": "Apple",
        "E454E8": "Apple", "F0A731": "Apple",

        // Ubiquiti Networks (UniFi)
        "002722": "Ubiquiti Networks", "0418D6": "Ubiquiti Networks", "24A43C": "Ubiquiti Networks",
        "788A20": "Ubiquiti Networks", "B4FBE4": "Ubiquiti Networks", "FCECDA": "Ubiquiti Networks",
        "68D79A": "Ubiquiti Networks", "70A741": "Ubiquiti Networks", "AC8BFA": "Ubiquiti Networks",
        "E063DA": "Ubiquiti Networks", "F492BF": "Ubiquiti Networks", "18E829": "Ubiquiti Networks",

        // MikroTik
        "000C42": "MikroTik", "488F5A": "MikroTik", "64D154": "MikroTik",
        "CC2DE0": "MikroTik", "D4CA6D": "MikroTik", "B869F4": "MikroTik",
        "2C6B7D": "MikroTik", "789A18": "MikroTik", "E48D8C": "MikroTik",

        // Fortinet
        "00090F": "Fortinet", "085B0E": "Fortinet", "704C8C": "Fortinet",
        "906C2D": "Fortinet", "04D590": "Fortinet", "E81DCA": "Fortinet",

        // Palo Alto Networks
        "001B17": "Palo Alto Networks", "003048": "Palo Alto Networks",
        "08661F": "Palo Alto Networks", "D4F5EF": "Palo Alto Networks",

        // VMware & Hypervisors
        "000569": "VMware", "000C29": "VMware", "001C14": "VMware", "005056": "VMware",
        "080027": "Oracle VirtualBox", "525400": "QEMU / KVM Virtual NIC",
        "00155D": "Microsoft Hyper-V", "00163E": "Xen Virtual Machine",

        // Raspberry Pi
        "28CDC1": "Raspberry Pi", "B827EB": "Raspberry Pi", "DCA632": "Raspberry Pi",
        "E45F01": "Raspberry Pi", "2CCF67": "Raspberry Pi", "D83ADD": "Raspberry Pi",

        // Intel Corporation
        "0002B3": "Intel Corporation", "000347": "Intel Corporation", "000423": "Intel Corporation",
        "000E0C": "Intel Corporation", "001302": "Intel Corporation", "0013E8": "Intel Corporation",
        "001500": "Intel Corporation", "001B21": "Intel Corporation", "001E67": "Intel Corporation",
        "A0369F": "Intel Corporation", "3C6AA7": "Intel Corporation", "4851B7": "Intel Corporation",
        "6805CA": "Intel Corporation", "808600": "Intel Corporation", "88A4C2": "Intel Corporation",

        // Dell & Supermicro
        "001422": "Dell", "00188B": "Dell", "0019B9": "Dell", "001A6B": "Dell", "180373": "Dell",
        "F8BC12": "Dell", "D4BEB9": "Dell", "B8AC6F": "Dell", "74867A": "Dell",
        "002590": "Super Micro Computer", "AC1F6B": "Super Micro Computer",

        // HP / Hewlett Packard Enterprise & Aruba
        "0001E6": "Hewlett Packard Enterprise", "0002A5": "Hewlett Packard Enterprise",
        "000802": "Hewlett Packard Enterprise", "000B46": "Hewlett Packard Enterprise",
        "001185": "Hewlett Packard Enterprise", "3C4A92": "HP Inc.", "9C8E99": "HP Inc.",
        "000B86": "Aruba Networks", "001A1E": "Aruba Networks", "00246C": "Aruba Networks",
        "20A6CD": "Aruba Networks", "40E3D6": "Aruba Networks", "94B40F": "Aruba Networks",
        "D8C7C8": "Aruba Networks", "F05C19": "Aruba Networks",

        // TP-Link
        "50C7BF": "TP-Link", "EC086B": "TP-Link", "6038E0": "TP-Link",
        "74DA38": "TP-Link", "984827": "TP-Link", "14EB29": "TP-Link",
        "18D6C7": "TP-Link", "30B5C2": "TP-Link", "3CE624": "TP-Link",
        "54AF97": "TP-Link", "6466B3": "TP-Link", "84D81B": "TP-Link",
        "98DE77": "TP-Link", "B09575": "TP-Link", "9C5322": "TP-Link",
        "687FF0": "TP-Link",

        // Netgear
        "00095B": "Netgear", "00146C": "Netgear", "001F33": "Netgear",
        "20E52A": "Netgear", "288088": "Netgear", "841B5E": "Netgear",
        "C40415": "Netgear", "E0469A": "Netgear", "9C3DCF": "Netgear",

        // ASUS & Linksys / Belkin
        "001E8C": "ASUS", "04D9F5": "ASUS", "10BF48": "ASUS", "2C4D54": "ASUS",
        "000625": "Linksys", "000C41": "Linksys", "000F66": "Linksys", "001217": "Linksys",
        "001310": "Linksys", "0014BF": "Linksys", "0016B6": "Linksys", "001839": "Linksys",
        "001A70": "Linksys", "001C10": "Linksys", "001D7E": "Linksys", "001EE5": "Linksys",
        "002129": "Linksys", "00226B": "Linksys", "002369": "Linksys", "00259C": "Linksys",
        "149182": "Linksys / Belkin", "20AA4B": "Linksys / Belkin", "24F5A2": "Linksys / Belkin",
        "302303": "Linksys / Belkin", "3476C5": "Linksys / Belkin", "48F8B3": "Linksys / Belkin",
        "586D8F": "Linksys / Belkin", "60334B": "Linksys / Belkin",
        "C4411E": "Linksys / Belkin", "E89F80": "Linksys / Belkin",
        "EC1A59": "Belkin", "08863B": "Belkin", "94103E": "Belkin", "B4750E": "Belkin",

        // Google & Nest
        "001A11": "Google", "30FD38": "Google", "F4F5DB": "Google",
        "546009": "Google", "641666": "Google", "A47733": "Google",
        "F80F41": "Google",

        // Amazon & eero
        "50F5DA": "eero", "B0A737": "eero", "44650D": "Amazon Technologies",
        "6837E9": "Amazon Technologies", "FC65DE": "Amazon Technologies",
        "78E103": "Amazon Technologies", "B0A7B9": "Amazon (Echo/Ring)",

        // Espressif Systems (ESP8266 / ESP32 - Smart Home IoT)
        "240AC4": "Espressif Systems", "30AEA4": "Espressif Systems", "840D8E": "Espressif Systems",
        "A4CF12": "Espressif Systems", "BCDD2C": "Espressif Systems", "CC50E3": "Espressif Systems",
        "DC4F22": "Espressif Systems", "E831CD": "Espressif Systems",

        // Synology & QNAP NAS
        "001132": "Synology", "0024E8": "Synology", "00089B": "QNAP Systems", "245EBE": "QNAP Systems",

        // Sonos
        "000E58": "Sonos", "48A6B8": "Sonos", "5C89C1": "Sonos", "7828CA": "Sonos",

        // Samsung & LG & Sony (Smart TVs & Appliances)
        "0000F0": "Samsung", "0007AB": "Samsung", "001247": "Samsung", "00166C": "Samsung",
        "6C5AB0": "Samsung Electronics", "501479": "Samsung", "E4E0C5": "Samsung",
        "001C62": "LG Electronics", "001F6B": "LG Electronics", "203D66": "LG Electronics",
        "00014A": "Sony", "00041F": "Sony", "0013A9": "Sony", "F8461C": "Sony"
    ]
}
