import Foundation

/// Utilities for detecting and enumerating serial console cables on macOS
public struct SerialDiscovery: Sendable {
    public static let shared = SerialDiscovery()

    public init() {}

    /// Standard supported baud rates for network appliances
    public static let standardBaudRates: [Int] = [
        9600,   // Standard Cisco, Juniper, Fortinet, pfSense default
        19200,
        38400,
        57600,
        115200  // Arista EOS, modern high-speed consoles
    ]

    /// Enumerate active calling unit devices (`/dev/cu.*`)
    public func discoverPorts() -> [SerialPortInfo] {
        let devDir = "/dev"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: devDir) else {
            return fallbackPorts()
        }

        var ports: [SerialPortInfo] = []

        // Filter for calling units (cu.*) as they do not block waiting for carrier detect
        let cuFiles = files.filter { $0.hasPrefix("cu.") }

        for file in cuFiles {
            let fullPath = "\(devDir)/\(file)"
            let isUSB = isUSBSerialDevice(file)
            let friendlyName = resolveFriendlyName(file)

            ports.append(SerialPortInfo(
                devicePath: fullPath,
                friendlyName: friendlyName,
                isUSB: isUSB
            ))
        }

        // Sort so USB devices are displayed first, then alphabetical
        return ports.sorted {
            if $0.isUSB != $1.isUSB {
                return $0.isUSB && !$1.isUSB
            }
            return $0.friendlyName < $1.friendlyName
        }
    }

    /// Identify known USB-to-serial chipsets based on macOS device node naming conventions
    public func isUSBSerialDevice(_ fileName: String) -> Bool {
        let lower = fileName.lowercased()
        return lower.contains("usbserial") ||
               lower.contains("usbmodem") ||
               lower.contains("slab_usbtouart") ||
               lower.contains("wchusbserial") ||
               lower.contains("ftdi") ||
               lower.contains("cp210") ||
               lower.contains("ch34")
    }

    /// Provide friendly labels for common network console adapters
    public func resolveFriendlyName(_ fileName: String) -> String {
        let lower = fileName.lowercased()
        if lower.contains("usbserial") {
            return "FTDI / Prolific USB-Serial (\(fileName))"
        } else if lower.contains("slab_usbtouart") {
            return "Silicon Labs CP210x UART (\(fileName))"
        } else if lower.contains("wchusbserial") {
            return "WCH CH340 USB-Serial (\(fileName))"
        } else if lower.contains("usbmodem") {
            return "Cisco USB Console Cable (\(fileName))"
        } else if lower.contains("bluetooth") {
            return "Bluetooth Serial (\(fileName))"
        } else if lower.contains("debug-console") {
            return "Darwin Debug Console"
        }
        return fileName
    }

    private func fallbackPorts() -> [SerialPortInfo] {
        [
            SerialPortInfo(devicePath: "/dev/cu.usbserial-10", friendlyName: "USB Serial Console (Simulated)", isUSB: true)
        ]
    }
}
